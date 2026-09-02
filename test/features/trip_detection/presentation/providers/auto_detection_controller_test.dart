import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' show LocationAccuracyStatus;
// `Override` is not re-exported by flutter_riverpod.
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;

import 'package:autoride/core/audit/audit_log.dart';
import 'package:autoride/core/audit/audit_sink.dart';
import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/core/permissions/exceptions/permission_exceptions.dart';
import 'package:autoride/core/permissions/models/background_location_state.dart';
import 'package:autoride/core/permissions/models/permission_status.dart';
import 'package:autoride/core/permissions/providers/background_location_status.dart';
import 'package:autoride/features/onboarding/data/services/onboarding_service.dart';
import 'package:autoride/features/settings/data/services/settings_service.dart';
import 'package:autoride/features/settings/domain/models/detection_settings.dart';
import 'package:autoride/features/settings/domain/models/user_settings.dart';
import 'package:autoride/features/trip_detection/data/services/location_permission_service.dart';
import 'package:autoride/features/trip_detection/data/services/trip_detection_coordinator.dart';
import 'package:autoride/features/trip_detection/data/services/trip_recorder_service.dart';
import 'package:autoride/features/trip_detection/data/services/trip_state_machine.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';
import 'package:autoride/features/trip_detection/domain/models/auto_detection_state.dart';
import 'package:autoride/features/trip_detection/domain/models/location_data.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_detection/domain/models/trip_state.dart';
import 'package:autoride/features/trip_detection/presentation/providers/auto_detection_controller.dart';
import 'package:autoride/features/trip_detection/services/background_location_service.dart';

// ===========================================================================
// AutoDetectionController is the entry point automatic detection never had
// (audit #11 / L-001). What is under test here is the LIFECYCLE decision —
// which of startListening/stopListening is called for a given combination of
// setting, permission and onboarding state, and what the manual start button
// does — not the detection logic itself, so the coordinator is a spy.
// ===========================================================================

class _CoordinatorLog {
  int startCalls = 0;
  int stopCalls = 0;
}

class _SpyCoordinator extends TripDetectionCoordinator {
  _SpyCoordinator(this.log);

  final _CoordinatorLog log;

  @override
  Future<TripState> build() async => const TripState.idle();

  @override
  Future<void> startListening() async {
    log.startCalls++;
  }

  @override
  void stopListening() {
    log.stopCalls++;
  }
}

/// State machine double that transitions without reading other providers.
class _TestTripStateMachine extends TripStateMachine {
  @override
  TripState build() => const TripState.idle();

  @override
  void startDetecting() {
    state.mapOrNull(
      idle: (_) =>
          state = TripState.detecting(detectionStartTime: DateTime.now()),
    );
  }

  @override
  void startTripWithId(int tripId) {
    state.mapOrNull(
      detecting: (_) =>
          state = TripState.active(tripId: tripId, startTime: DateTime.now()),
    );
  }

  @override
  void stopTrip({bool discarded = false, Trip? finalTrip}) {
    state.mapOrNull(
      detecting: (_) => state = const TripState.idle(),
      active: (_) => state = const TripState.idle(),
      paused: (_) => state = const TripState.idle(),
    );
  }
}

class _RecorderLog {
  final List<double> startedWithConfidence = [];
  final List<ActivityType> startedWithActivity = [];
  bool throwOnStart = false;
}

class _SpyTripRecorderService extends TripRecorderService {
  _SpyTripRecorderService(this.log);

  final _RecorderLog log;

  @override
  Future<TripMetrics> build() async => const TripMetrics(
    distanceMeters: 0,
    durationSeconds: 0,
    routePointCount: 0,
  );

  @override
  Future<void> startRecording({
    required double confidenceScore,
    required ActivityType activity,
    List<LocationData> priorLocations = const [],
  }) async {
    if (log.throwOnStart) throw StateError('forced start failure');
    log.startedWithConfidence.add(confidenceScore);
    log.startedWithActivity.add(activity);
    ref.read(tripStateMachineProvider.notifier).startTripWithId(1);
  }

  @override
  Future<Trip> stopRecording() async {
    ref.read(tripStateMachineProvider.notifier).stopTrip();
    return Trip(
      id: 1,
      startTime: DateTime.now(),
      endTime: DateTime.now(),
      distance: 0,
      duration: 0,
      detectedActivity: ActivityType.cycling,
      confidenceScore: 1.0,
      routePoints: const [],
    );
  }

  /// Publish new metrics the way the live recorder's ticker does.
  void publish(TripMetrics metrics) => state = AsyncValue.data(metrics);
}

/// Settings double whose "Automatic detection" value can be flipped at will.
class _FakeSettingsService extends SettingsService {
  _FakeSettingsService({required this.enabled});

  final bool enabled;

  @override
  Future<UserSettings> build() async => UserSettings(
    detection: DetectionSettings(automaticDetectionEnabled: enabled),
  );

  void setEnabled(bool value) {
    state = AsyncValue.data(
      UserSettings(
        detection: DetectionSettings(automaticDetectionEnabled: value),
      ),
    );
  }
}

/// The status lives outside the notifier so it can change between rebuilds,
/// the way the real one does after the user grants permission.
class _PermissionLog {
  _PermissionLog(this.status);

  LocationPermissionStatus status;
}

class _FakePermissionService extends LocationPermissionService {
  _FakePermissionService(this.log);

  final _PermissionLog log;

  @override
  Future<LocationPermissionStatus> build() async => log.status;
}

class _FakeOnboardingService extends OnboardingService {
  _FakeOnboardingService({required this.firstLaunch});

  final bool firstLaunch;

  @override
  Future<bool> build() async => firstLaunch;
}

/// Foreground-service double: no plugin, records what was asked of it.
///
/// The counters live outside the notifier because the provider is autoDispose:
/// it is recreated between reads, and a Riverpod notifier instance may not be
/// reused across elements.
class _BackgroundServiceLog {
  int initializeCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  final List<String> notificationContents = [];
}

class _FakeBackgroundLocationService extends BackgroundLocationService {
  _FakeBackgroundLocationService(this.log);

  final _BackgroundServiceLog log;

  @override
  Future<bool> build() async => false;

  @override
  Future<void> initialize() async => log.initializeCalls++;

  @override
  Future<void> startTracking() async {
    log.startCalls++;
    state = const AsyncValue.data(true);
  }

  @override
  Future<void> stopTracking() async {
    log.stopCalls++;
    state = const AsyncValue.data(false);
  }

  @override
  void updateNotification({required String title, required String content}) {
    log.notificationContents.add(content);
  }
}

/// Fails the way the real service failed on iOS: after an `await`, so the
/// controller has already committed to the start.
class _ThrowingBackgroundLocationService extends BackgroundLocationService {
  @override
  Future<bool> build() async => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> startTracking() async {
    await Future<void>.delayed(Duration.zero);
    throw StateError('Cannot use the Ref of backgroundLocationServiceProvider');
  }
}

class _FakeBackgroundLocationStatus extends BackgroundLocationStatus {
  _FakeBackgroundLocationStatus({required this.always, required this.accuracy});

  final bool always;
  final LocationAccuracyStatus accuracy;

  @override
  Future<BackgroundLocationState> build() async => BackgroundLocationState(
    permission: AppPermissionStatus(
      permission: AppPermission.locationAlways,
      isGranted: always,
      isDenied: !always,
      isPermanentlyDenied: !always,
      isRestricted: false,
      isLimited: false,
    ),
    accuracy: accuracy,
  );
}

/// Controller whose notification throttle is effectively off.
class _FastNotificationController extends AutoDetectionController {
  @override
  Duration get notificationUpdateInterval => Duration.zero;
}

void main() {
  late _CoordinatorLog coordinator;
  late _RecorderLog recorder;
  late _BackgroundServiceLog backgroundService;
  late ProviderContainer container;
  late ProviderSubscription<AutoDetectionState> controllerSubscription;

  List<Override> overridesFor({
    bool enabled = true,
    LocationPermissionStatus permission = LocationPermissionStatus.granted,
    _PermissionLog? permissionLog,
    bool isFirstLaunch = false,
    _FakeSettingsService? settings,
    Override? backgroundServiceOverride,
    Override? backgroundStatusOverride,
  }) => [
    settingsServiceProvider.overrideWith(
      () => settings ?? _FakeSettingsService(enabled: enabled),
    ),
    locationPermissionServiceProvider.overrideWith(
      () => _FakePermissionService(permissionLog ?? _PermissionLog(permission)),
    ),
    onboardingServiceProvider.overrideWith(
      () => _FakeOnboardingService(firstLaunch: isFirstLaunch),
    ),
    tripDetectionCoordinatorProvider.overrideWith(
      () => _SpyCoordinator(coordinator),
    ),
    tripStateMachineProvider.overrideWith(_TestTripStateMachine.new),
    tripRecorderServiceProvider.overrideWith(
      () => _SpyTripRecorderService(recorder),
    ),
    backgroundServiceOverride ??
        backgroundLocationServiceProvider.overrideWith(
          () => _FakeBackgroundLocationService(backgroundService),
        ),
    ?backgroundStatusOverride,
  ];

  /// Builds the controller and lets the async settings/permission/onboarding
  /// values resolve, so the lifecycle decision has actually been applied.
  Future<AutoDetectionController> startController(
    List<Override> overrides,
  ) async {
    container = ProviderContainer(overrides: overrides);
    controllerSubscription = container.listen(
      autoDetectionControllerProvider,
      (_, _) {},
    );
    await pumpEventQueue();
    return container.read(autoDetectionControllerProvider.notifier);
  }

  setUp(() {
    coordinator = _CoordinatorLog();
    recorder = _RecorderLog();
    backgroundService = _BackgroundServiceLog();
  });

  tearDown(() {
    controllerSubscription.close();
    container.dispose();
  });

  group('AutoDetectionController - detection lifecycle', () {
    test(
      'starts the coordinator when the setting is on and permission granted',
      () async {
        await startController(overridesFor());

        expect(coordinator.startCalls, 1);
        expect(coordinator.stopCalls, 0);
        expect(
          container.read(autoDetectionControllerProvider).shouldListen,
          isTrue,
        );
      },
    );

    test('never starts while location permission is missing', () async {
      await startController(
        overridesFor(permission: LocationPermissionStatus.denied),
      );

      expect(coordinator.startCalls, 0);
      final state = container.read(autoDetectionControllerProvider);
      expect(state.shouldListen, isFalse);
      expect(state.blockedReason, 'Location permission required');
    });

    test('never starts before onboarding is complete', () async {
      await startController(overridesFor(isFirstLaunch: true));

      expect(coordinator.startCalls, 0);
      expect(
        container.read(autoDetectionControllerProvider).blockedReason,
        'Finish setup to enable detection',
      );
    });

    test('never starts while the setting is off', () async {
      await startController(overridesFor(enabled: false));

      expect(coordinator.startCalls, 0);
      expect(
        container.read(autoDetectionControllerProvider).blockedReason,
        'Automatic detection is off',
      );
    });

    // Onboarding grants location through PermissionHandlerService, which leaves
    // this provider's cached status stale; without the re-read, detection would
    // only start on the next cold launch.
    test('picks up a permission granted after the status was cached', () async {
      final permission = _PermissionLog(LocationPermissionStatus.denied);
      final controller = await startController(
        overridesFor(permissionLog: permission),
      );
      expect(coordinator.startCalls, 0);

      permission.status = LocationPermissionStatus.granted;
      controller.refreshPermission();
      await pumpEventQueue();

      expect(coordinator.startCalls, 1);
    });

    test(
      'turning the setting off stops the coordinator, on starts it again',
      () async {
        final settings = _FakeSettingsService(enabled: true);
        await startController(overridesFor(settings: settings));
        expect(coordinator.startCalls, 1);

        settings.setEnabled(false);
        await pumpEventQueue();
        expect(coordinator.stopCalls, 1);
        expect(
          container.read(autoDetectionControllerProvider).shouldListen,
          isFalse,
        );

        settings.setEnabled(true);
        await pumpEventQueue();
        expect(coordinator.startCalls, 2);
      },
    );

    test(
      'turning the setting off during a trip does not stop the recording',
      () async {
        final settings = _FakeSettingsService(enabled: true);
        final controller = await startController(
          overridesFor(settings: settings),
        );

        await controller.startTripManually();
        await pumpEventQueue();
        expect(container.read(tripStateMachineProvider).hasActiveTrip, isTrue);

        settings.setEnabled(false);
        await pumpEventQueue();

        // The coordinator is asked to stop (it defers the teardown itself, see
        // trip_detection_coordinator_test.dart) but the trip keeps running.
        expect(coordinator.stopCalls, greaterThan(0));
        expect(container.read(tripStateMachineProvider).hasActiveTrip, isTrue);
      },
    );
  });

  group('AutoDetectionController - manual start', () {
    test(
      'starts a trip with full confidence even when detection is off',
      () async {
        final controller = await startController(overridesFor(enabled: false));
        expect(coordinator.startCalls, 0);

        await controller.startTripManually();
        await pumpEventQueue();

        expect(recorder.startedWithConfidence, [1.0]);
        expect(recorder.startedWithActivity, [ActivityType.cycling]);
        expect(container.read(tripStateMachineProvider).currentTripId, 1);

        // The session is started for the ride (auto-pause/stop need motion) and
        // handed back afterwards, since automatic detection is off.
        expect(coordinator.startCalls, 1);
        expect(coordinator.stopCalls, 1);
      },
    );

    test('does not release the session when detection is on', () async {
      final controller = await startController(overridesFor());

      await controller.startTripManually();
      await pumpEventQueue();

      expect(coordinator.stopCalls, 0);
    });

    test('is a no-op while a trip is already running', () async {
      final controller = await startController(overridesFor());
      await controller.startTripManually();
      await pumpEventQueue();

      await controller.startTripManually();

      expect(recorder.startedWithConfidence, hasLength(1));
    });

    test('a failing start returns to idle and rethrows', () async {
      recorder.throwOnStart = true;
      final controller = await startController(overridesFor());

      await expectLater(controller.startTripManually(), throwsStateError);

      expect(container.read(tripStateMachineProvider).hasActiveTrip, isFalse);
    });
  });

  group('AutoDetectionController - foreground service (audit #7/#8)', () {
    // Detection listens to the sensors from the main isolate. Without a
    // foreground service that isolate is Doze-suspended as soon as the screen
    // goes off, so the service must cover the whole listening window, not just
    // the recording (L-067).
    test('starts as soon as automatic detection begins listening', () async {
      await startController(overridesFor());

      expect(backgroundService.initializeCalls, 1);
      expect(backgroundService.startCalls, 1);
      expect(backgroundService.stopCalls, 0);
    });

    test('does not start while the setting is off', () async {
      await startController(overridesFor(enabled: false));
      expect(backgroundService.startCalls, 0);
    });

    test('does not start while the permission is missing', () async {
      await startController(
        overridesFor(permission: LocationPermissionStatus.denied),
      );
      expect(backgroundService.startCalls, 0);
    });

    test('stops when automatic detection is turned off', () async {
      final settings = _FakeSettingsService(enabled: true);
      await startController(overridesFor(settings: settings));
      expect(backgroundService.startCalls, 1);

      settings.setEnabled(false);
      await pumpEventQueue();

      expect(backgroundService.stopCalls, 1);
    });

    test('stops when the location permission is revoked', () async {
      final permission = _PermissionLog(LocationPermissionStatus.granted);
      final controller = await startController(
        overridesFor(permissionLog: permission),
      );
      expect(backgroundService.startCalls, 1);

      permission.status = LocationPermissionStatus.denied;
      controller.refreshPermission();
      await pumpEventQueue();

      expect(backgroundService.stopCalls, 1);
    });

    // The trip must not restart (or, at its end, stop) a service the detection
    // session still needs.
    test('keeps running across a trip started while listening', () async {
      final controller = await startController(overridesFor());
      expect(backgroundService.startCalls, 1);

      await controller.startTripManually();
      await pumpEventQueue();
      expect(backgroundService.startCalls, 1);
      expect(backgroundService.stopCalls, 0);

      await container
          .read(tripRecorderServiceProvider.notifier)
          .stopRecording();
      await pumpEventQueue();
      expect(backgroundService.startCalls, 1);
      expect(backgroundService.stopCalls, 0);
      // Back to the waiting phase.
      expect(
        backgroundService.notificationContents.last,
        AppConstants.notificationContentDetecting,
      );
    });

    // Manual ride with automatic detection off: the service exists only for
    // that trip, exactly as before.
    test('runs only for the trip when detection is off', () async {
      final controller = await startController(overridesFor(enabled: false));
      expect(backgroundService.startCalls, 0);

      await controller.startTripManually();
      await pumpEventQueue();
      expect(backgroundService.initializeCalls, 1);
      expect(backgroundService.startCalls, 1);

      await container
          .read(tripRecorderServiceProvider.notifier)
          .stopRecording();
      await pumpEventQueue();
      expect(backgroundService.stopCalls, 1);
    });

    test('survives detection being turned off mid-trip', () async {
      final settings = _FakeSettingsService(enabled: true);
      final controller = await startController(
        overridesFor(settings: settings),
      );
      await controller.startTripManually();
      await pumpEventQueue();

      settings.setEnabled(false);
      await pumpEventQueue();
      expect(backgroundService.stopCalls, 0);

      await container
          .read(tripRecorderServiceProvider.notifier)
          .stopRecording();
      await pumpEventQueue();
      expect(backgroundService.stopCalls, 1);
    });

    test('pushes live trip metrics into its notification', () async {
      // Real throttle is 5 s (AppConstants.notificationUpdateInterval); this
      // subclass makes the second push observable without waiting.
      final controller = await startController([
        ...overridesFor(),
        autoDetectionControllerProvider.overrideWith(
          _FastNotificationController.new,
        ),
      ]);
      await controller.startTripManually();
      await pumpEventQueue();

      final spy = container.read(
        tripRecorderServiceProvider.notifier,
      ) as _SpyTripRecorderService;
      spy.publish(
        const TripMetrics(
          distanceMeters: 1500,
          durationSeconds: 300,
          routePointCount: 12,
        ),
      );
      await pumpEventQueue();

      expect(
        backgroundService.notificationContents,
        contains('1.50 km • 5m 0s'),
      );
    });
  });

  // What the 2026-09-02 iPhone audit could not answer. The foreground service
  // failed to start and nothing said so in the log; and nothing said whether
  // the OS had granted "Always", which on iOS is the difference between the
  // process surviving in the background and being killed minutes after
  // `app paused`.
  group('AutoDetectionController - what the audit log has to say', () {
    late _RecordingAuditSink sink;

    setUp(() {
      sink = _RecordingAuditSink();
      AuditLog.install(sink, verbose: false);
    });

    tearDown(AuditLog.uninstall);

    test('journals a failed foreground service instead of swallowing it', () {
      // Deliberately not `startController`: the failure is asynchronous and
      // must not take detection down with it.
      return startController(
        overridesFor(
          backgroundServiceOverride: backgroundLocationServiceProvider
              .overrideWith(_ThrowingBackgroundLocationService.new),
        ),
      ).then((_) async {
        await pumpEventQueue();

        final fgs = sink.fieldsOf('fgs').toList();
        expect(fgs, hasLength(1));
        expect(fgs.single['a'], 'fail');
        expect(fgs.single['plat'], isNotNull);
        expect(fgs.single['ex'], contains('Cannot use the Ref'));

        // Detection keeps running without the service.
        expect(coordinator.startCalls, 1);
        expect(
          container.read(autoDetectionControllerProvider).shouldListen,
          isTrue,
        );
      });
    });

    test('journals the platform on a successful start', () async {
      await startController(overridesFor());

      final fgs = sink.fieldsOf('fgs').toList();
      expect(fgs.single['a'], 'start');
      expect(fgs.single['plat'], isNotNull);
    });

    test('journals "Always" and precise accuracy on session start', () async {
      await startController(
        overridesFor(
          backgroundStatusOverride: backgroundLocationStatusProvider
              .overrideWith(
                () => _FakeBackgroundLocationStatus(
                  always: true,
                  accuracy: LocationAccuracyStatus.precise,
                ),
              ),
        ),
      );

      final perms = sink
          .fieldsOf('perm')
          .where((f) => f['k'] == 'background')
          .toList();
      expect(perms, isNotEmpty);
      final session = perms.firstWhere((f) => f['why'] == 'session');
      expect(session['alw'], isTrue);
      expect(session['acc'], 'precise');
      expect(session['issue'], isNull);
    });

    test('journals a "While Using" downgrade as the blocking issue', () async {
      await startController(
        overridesFor(
          backgroundStatusOverride: backgroundLocationStatusProvider
              .overrideWith(
                () => _FakeBackgroundLocationStatus(
                  always: false,
                  accuracy: LocationAccuracyStatus.precise,
                ),
              ),
        ),
      );

      final session = sink
          .fieldsOf('perm')
          .firstWhere((f) => f['k'] == 'background' && f['why'] == 'session');
      expect(session['alw'], isFalse);
      expect(session['issue'], 'alwaysMissing');
    });
  });
}

class _RecordingAuditSink implements AuditSink {
  final List<String> lines = <String>[];

  @override
  void write(
    String line, {
    required int t,
    required String type,
    required int lvl,
    required bool critical,
  }) => lines.add(line);

  @override
  Future<void> flush() async {}

  Iterable<Map<String, dynamic>> fieldsOf(String type) => lines
      .map((l) => jsonDecode(l) as Map<String, dynamic>)
      .where((m) => m['e'] == type);
}
