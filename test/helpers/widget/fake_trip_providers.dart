import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not re-exported by flutter_riverpod.
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;

import 'package:geolocator/geolocator.dart' show LocationAccuracyStatus;

import 'package:autoride/core/permissions/exceptions/permission_exceptions.dart';
import 'package:autoride/core/permissions/models/background_location_state.dart';
import 'package:autoride/core/permissions/models/permission_status.dart';
import 'package:autoride/core/permissions/providers/background_location_status.dart';
import 'package:autoride/core/platform/models/platform_info.dart';
import 'package:autoride/core/platform/services/platform_info_service.dart';
import 'package:autoride/features/onboarding/data/services/onboarding_service.dart';
import 'package:autoride/features/settings/data/services/settings_service.dart';
import 'package:autoride/features/settings/domain/models/detection_settings.dart';
import 'package:autoride/features/settings/domain/models/user_settings.dart';
import 'package:autoride/features/trip_detection/data/services/trip_recorder_service.dart';
import 'package:autoride/features/trip_detection/data/services/trip_state_machine.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';
import 'package:autoride/features/trip_detection/domain/models/auto_detection_state.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_detection/domain/models/trip_state.dart';
import 'package:autoride/features/trip_detection/presentation/providers/auto_detection_controller.dart';
import 'package:autoride/features/trip_history/presentation/providers/trip_history_provider.dart';

// ===========================================================================
// Provider doubles shared by the presentation-layer widget tests.
//
// Everything a screen touches is behind an overridable provider since T041, so
// these subclass the real notifiers and answer without plugins, database or
// GPS. Mutable logs live OUTSIDE the notifiers: autoDispose providers are
// recreated between reads and a Riverpod notifier instance may not be reused
// across elements.
// ===========================================================================

/// State machine double that transitions without touching the notification
/// service (which would reach flutter_local_notifications).
class FakeTripStateMachine extends TripStateMachine {
  FakeTripStateMachine([this.initial = const TripState.idle()]);

  final TripState initial;

  @override
  TripState build() => initial;

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
  void pauseTrip() {
    state.mapOrNull(
      active: (active) => state = TripState.paused(
        tripId: active.tripId,
        startTime: active.startTime,
        pauseStartTime: DateTime.now(),
      ),
    );
  }

  @override
  void resumeTrip() {
    state.mapOrNull(
      paused: (paused) => state = TripState.active(
        tripId: paused.tripId,
        startTime: paused.startTime,
      ),
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

/// Everything the recorder double was asked to do, plus the metrics it serves.
class RecorderLog {
  RecorderLog({
    this.metrics = const TripMetrics(
      distanceMeters: 0,
      durationSeconds: 0,
      routePointCount: 0,
    ),
  });

  TripMetrics metrics;
  int buildCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  int stopCalls = 0;
  final List<double> startedWithConfidence = [];
}

/// Recorder double.
///
/// It reproduces the two structural properties the tracking screen and the tab
/// shell depend on — the container-owned state-machine subscription and the
/// `keepAlive` session held for the duration of a recording (T041) — without
/// the repository, the GPS stream or the timers.
class FakeTripRecorderService extends TripRecorderService {
  FakeTripRecorderService(this.log);

  final RecorderLog log;
  void Function()? _releaseSession;
  void Function()? _closeStateMachineSubscription;

  @override
  Future<TripMetrics> build() async {
    log.buildCalls++;
    _closeStateMachineSubscription ??= ref.container
        .listen(tripStateMachineProvider, (_, _) {})
        .close;
    ref.onDispose(() {
      _closeStateMachineSubscription?.call();
      _closeStateMachineSubscription = null;
      _releaseSession?.call();
      _releaseSession = null;
    });
    return log.metrics;
  }

  @override
  Future<void> startRecording({
    required double confidenceScore,
    required ActivityType activity,
  }) async {
    _releaseSession ??= ref.keepAlive().close;
    log.startedWithConfidence.add(confidenceScore);
    ref.read(tripStateMachineProvider.notifier).startTripWithId(1);
  }

  @override
  Future<void> pauseRecording() async {
    log.pauseCalls++;
    ref.read(tripStateMachineProvider.notifier).pauseTrip();
  }

  @override
  Future<void> resumeRecording() async {
    log.resumeCalls++;
    ref.read(tripStateMachineProvider.notifier).resumeTrip();
  }

  @override
  Future<Trip> stopRecording() async {
    log.stopCalls++;
    ref.read(tripStateMachineProvider.notifier).stopTrip();
    _releaseSession?.call();
    _releaseSession = null;
    return Trip(
      id: 1,
      startTime: DateTime.now(),
      endTime: DateTime.now(),
      distance: log.metrics.distanceMeters,
      duration: log.metrics.durationSeconds,
      detectedActivity: ActivityType.cycling,
      confidenceScore: 1.0,
      routePoints: const [],
    );
  }

  /// Publish new metrics the way the live recorder's 1 s ticker does.
  void publish(TripMetrics metrics) {
    log.metrics = metrics;
    state = AsyncValue.data(metrics);
  }
}

/// What the tracking screen asked of the detection controller.
class AutoDetectionLog {
  AutoDetectionLog({
    this.state = const AutoDetectionState(
      enabled: true,
      permissionGranted: true,
      onboardingComplete: true,
    ),
    this.throwOnManualStart = false,
  });

  AutoDetectionState state;
  bool throwOnManualStart;
  int manualStartCalls = 0;
}

/// Detection-controller double: no coordinator, no foreground service.
class FakeAutoDetectionController extends AutoDetectionController {
  FakeAutoDetectionController(this.log);

  final AutoDetectionLog log;

  @override
  AutoDetectionState build() => log.state;

  @override
  Future<void> startTripManually() async {
    log.manualStartCalls++;
    if (log.throwOnManualStart) {
      throw StateError('forced manual start failure');
    }
    ref.read(tripStateMachineProvider.notifier).startDetecting();
    await ref
        .read(tripRecorderServiceProvider.notifier)
        .startRecording(confidenceScore: 1.0, activity: ActivityType.cycling);
  }
}

class FakeSettingsService extends SettingsService {
  FakeSettingsService({this.automaticDetectionEnabled = true});

  final bool automaticDetectionEnabled;

  @override
  Future<UserSettings> build() async => UserSettings(
    detection: DetectionSettings(
      automaticDetectionEnabled: automaticDetectionEnabled,
    ),
  );
}

class FakeOnboardingService extends OnboardingService {
  FakeOnboardingService({this.firstLaunch = false});

  final bool firstLaunch;
  int completeCalls = 0;

  @override
  Future<bool> build() async => firstLaunch;

  @override
  Future<void> completeOnboarding() async {
    completeCalls++;
    state = const AsyncValue.data(false);
  }
}

/// A background-location state without the permission or location plugins.
BackgroundLocationState backgroundLocationState({
  bool granted = true,
  bool precise = true,
}) => BackgroundLocationState(
  permission: AppPermissionStatus(
    permission: AppPermission.locationAlways,
    isGranted: granted,
    isDenied: !granted,
    // What permission_handler reports on iOS for "While Using", and on
    // Android when "Allow all the time" was not picked.
    isPermanentlyDenied: !granted,
    isRestricted: false,
    isLimited: false,
  ),
  accuracy: precise
      ? LocationAccuracyStatus.precise
      : LocationAccuracyStatus.reduced,
);

class FakeBackgroundLocationStatus extends BackgroundLocationStatus {
  FakeBackgroundLocationStatus({this.granted = true, this.precise = true});

  final bool granted;
  final bool precise;
  int refreshCalls = 0;

  @override
  Future<BackgroundLocationState> build() async =>
      backgroundLocationState(granted: granted, precise: precise);

  @override
  void refresh() {
    refreshCalls++;
  }
}

class FakePlatformInfoService extends PlatformInfoService {
  FakePlatformInfoService([this.info = androidPlatform]);

  final PlatformInfo info;

  @override
  Future<PlatformInfo> build() async => info;
}

const androidPlatform = PlatformInfo(
  type: PlatformType.android,
  version: '14',
  apiLevel: 34,
  isPhysicalDevice: true,
);

const iosPlatform = PlatformInfo(
  type: PlatformType.ios,
  version: '17.4',
  apiLevel: 0,
  isPhysicalDevice: true,
);

class FakeTripHistory extends TripHistory {
  FakeTripHistory([this.trips = const []]);

  final List<Trip> trips;

  @override
  Future<List<Trip>> build() async => trips;

  @override
  Future<void> refresh() async {}
}

/// The override set every tracking/shell widget test starts from.
///
/// Individual tests append their own overrides (later entries win).
List<Override> tripSurfaceOverrides({
  required RecorderLog recorder,
  required AutoDetectionLog detection,
  TripState initialTripState = const TripState.idle(),
  bool automaticDetectionEnabled = true,
  bool backgroundLocationGranted = true,
  bool backgroundLocationPrecise = true,
  PlatformInfo platform = androidPlatform,
  List<Trip> trips = const [],
}) => [
  backgroundLocationStatusProvider.overrideWith(
    () => FakeBackgroundLocationStatus(
      granted: backgroundLocationGranted,
      precise: backgroundLocationPrecise,
    ),
  ),
  platformInfoServiceProvider.overrideWith(
    () => FakePlatformInfoService(platform),
  ),
  tripStateMachineProvider.overrideWith(
    () => FakeTripStateMachine(initialTripState),
  ),
  tripRecorderServiceProvider.overrideWith(
    () => FakeTripRecorderService(recorder),
  ),
  autoDetectionControllerProvider.overrideWith(
    () => FakeAutoDetectionController(detection),
  ),
  settingsServiceProvider.overrideWith(
    () => FakeSettingsService(
      automaticDetectionEnabled: automaticDetectionEnabled,
    ),
  ),
  onboardingServiceProvider.overrideWith(FakeOnboardingService.new),
  tripHistoryProvider.overrideWith(() => FakeTripHistory(trips)),
];
