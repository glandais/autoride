import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:autoride/features/trip_detection/data/services/trip_state_machine.dart';
import 'package:autoride/features/trip_detection/data/services/notification_service.dart';
import 'package:autoride/features/trip_detection/data/services/trip_recorder_service.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_detection/domain/models/trip_state.dart';
import 'package:autoride/features/settings/data/services/settings_service.dart';
import 'package:autoride/core/constants/app_constants.dart';

/// One recorded call to [NotificationService.showTripStopNotification].
class _StopNotification {
  const _StopNotification(
    this.distance,
    this.duration,
    this.avgSpeed,
    this.tripId,
  );

  final double distance;
  final Duration duration;
  final double avgSpeed;
  final int? tripId;
}

/// Mock NotificationService that skips all plugin calls and records what the
/// state machine asked it to display.
class _MockNotificationService extends NotificationService {
  final List<_StopNotification> stopNotifications = [];
  int foregroundCancelCount = 0;

  @override
  Future<void> build() async {
    // No-op: skip plugin initialization
  }

  @override
  Future<void> showTripStartNotification() async {}

  @override
  Future<void> showTripStopNotification({
    required double distance,
    required Duration duration,
    required double avgSpeed,
    int? tripId,
  }) async {
    stopNotifications.add(
      _StopNotification(distance, duration, avgSpeed, tripId),
    );
  }

  @override
  Future<void> cancelForegroundNotification() async {
    foregroundCancelCount++;
  }
}

/// Mock TripRecorderService that returns empty metrics
class _MockTripRecorderService extends TripRecorderService {
  @override
  Future<TripMetrics> build() async {
    return const TripMetrics(
      distanceMeters: 0,
      durationSeconds: 0,
      routePointCount: 0,
    );
  }
}

/// Recorder whose build never resolves successfully. Before L-069 the stop
/// notification (and the foreground cancel with it) was wrapped in a
/// `whenData` on this provider, so an error here silently swallowed both.
class _FailingTripRecorderService extends TripRecorderService {
  @override
  Future<TripMetrics> build() async {
    throw StateError('recorder unavailable');
  }
}

/// A finalized ride, as the recorder hands it to `stopTrip`.
Trip _finalTrip({
  double distance = 4200.0,
  int duration = 900,
  double? avgSpeed = 16.8,
}) {
  return Trip(
    id: 1,
    startTime: DateTime.now().subtract(const Duration(minutes: 20)),
    endTime: DateTime.now(),
    distance: distance,
    duration: duration,
    avgSpeed: avgSpeed,
    maxSpeed: 31.0,
    detectedActivity: ActivityType.cycling,
    confidenceScore: 0.9,
    status: TripStatus.completed,
  );
}

// NOTE: Some tests that trigger notifications may fail in unit test environment
// due to flutter_local_notifications plugin not being available.
// These tests pass functionally but fail at the plugin layer.
// The notification functionality is tested separately with widget tests.

void main() {
  late ProviderContainer container;
  late _MockNotificationService notifications;

  setUpAll(() {
    // Initialize Flutter binding for plugin tests
    TestWidgetsFlutterBinding.ensureInitialized();

    // Mock SharedPreferences for all tests
    SharedPreferences.setMockInitialValues({
      // Default settings values
      'tripNotificationsEnabled': true,
      'showOngoingNotification': true,
      'soundOnTripStartStop': false,
      'autoPauseEnabled': true,
      'minDistanceMeters': 500.0,
    });
  });

  setUp(() async {
    notifications = _MockNotificationService();
    container = ProviderContainer(
      overrides: [
        // Mock NotificationService to avoid flutter_local_notifications plugin
        notificationServiceProvider.overrideWith(() => notifications),
        // Mock TripRecorderService to avoid database dependency
        tripRecorderServiceProvider.overrideWith(_MockTripRecorderService.new),
      ],
    );

    // Wait for async providers to initialize
    await container.read(settingsServiceProvider.future);
  });

  tearDown(() {
    container.dispose();
  });

  group('TripStateMachine', () {
    test('should initialize in Idle state', () {
      final state = container.read(tripStateMachineProvider);

      // Check state using when pattern
      state.when(
        idle: () => expect(true, isTrue), // State is Idle
        detecting: (_) => fail('Should be Idle'),
        active: (_, _) => fail('Should be Idle'),
        paused: (tripId, startTime, pauseStartTime) => fail('Should be Idle'),
      );
      expect(state.hasActiveTrip, isFalse);
      expect(state.isRecording, isFalse);
    });

    test('should transition from Idle to Detecting', () {
      final stateMachine = container.read(tripStateMachineProvider.notifier);

      stateMachine.startDetecting();

      final state = container.read(tripStateMachineProvider);
      state.when(
        idle: () => fail('Should be Detecting'),
        detecting: (_) => expect(true, isTrue), // State is Detecting
        active: (_, _) => fail('Should be Detecting'),
        paused: (tripId, startTime, pauseStartTime) =>
            fail('Should be Detecting'),
      );
      expect(state.hasActiveTrip, isFalse);
      expect(state.isRecording, isFalse);
    });

    test('should transition from Detecting to Active', () async {
      final stateMachine = container.read(tripStateMachineProvider.notifier);

      stateMachine.startDetecting();
      const testTripId = 1; // Mock database trip ID
      stateMachine.startTripWithId(testTripId);

      final state = container.read(tripStateMachineProvider);
      state.when(
        idle: () => fail('Should be Active'),
        detecting: (_) => fail('Should be Active'),
        active: (id, startTime) =>
            expect(id, equals(testTripId)), // State is Active
        paused: (tripId, startTime, pauseStartTime) => fail('Should be Active'),
      );
      expect(state.hasActiveTrip, isTrue);
      expect(state.isRecording, isTrue);
      expect(state.currentTripId, equals(testTripId));
    });

    test('should transition from Active to Paused', () async {
      final stateMachine = container.read(tripStateMachineProvider.notifier);

      stateMachine.startDetecting();
      stateMachine.startTripWithId(1); // Mock database trip ID
      stateMachine.pauseTrip();

      final state = container.read(tripStateMachineProvider);
      state.when(
        idle: () => fail('Should be Paused'),
        detecting: (_) => fail('Should be Paused'),
        active: (_, _) => fail('Should be Paused'),
        paused: (tripId, startTime, pauseStartTime) =>
            expect(true, isTrue), // State is Paused
      );
      expect(state.hasActiveTrip, isTrue);
      expect(state.isRecording, isFalse);
    });

    test('should transition from Paused to Active on resume', () async {
      final stateMachine = container.read(tripStateMachineProvider.notifier);

      stateMachine.startDetecting();
      const testTripId = 1; // Mock database trip ID
      stateMachine.startTripWithId(testTripId);
      stateMachine.pauseTrip();
      stateMachine.resumeTrip();

      final state = container.read(tripStateMachineProvider);
      state.when(
        idle: () => fail('Should be Active'),
        detecting: (_) => fail('Should be Active'),
        active: (id, startTime) =>
            expect(id, equals(testTripId)), // State is Active
        paused: (tripId, startTime, pauseStartTime) => fail('Should be Active'),
      );
      expect(state.currentTripId, equals(testTripId));
    });

    test('should transition from Active to Idle on stop', () async {
      final stateMachine = container.read(tripStateMachineProvider.notifier);

      stateMachine.startDetecting();
      stateMachine.startTripWithId(1); // Mock database trip ID
      stateMachine.stopTrip();

      final state = container.read(tripStateMachineProvider);
      state.when(
        idle: () => expect(true, isTrue), // State is Idle
        detecting: (_) => fail('Should be Idle'),
        active: (_, _) => fail('Should be Idle'),
        paused: (tripId, startTime, pauseStartTime) => fail('Should be Idle'),
      );
      expect(state.hasActiveTrip, isFalse);
    });

    test('stop notification reports the finalized trip metrics', () async {
      final stateMachine = container.read(tripStateMachineProvider.notifier);

      stateMachine.startDetecting();
      stateMachine.startTripWithId(1);
      stateMachine.stopTrip(finalTrip: _finalTrip());

      final notification = notifications.stopNotifications.single;
      expect(notification.distance, equals(4200.0));
      expect(notification.duration, equals(const Duration(seconds: 900)));
      expect(notification.avgSpeed, equals(16.8));
      // The id is what the "View Details" action opens; without it the tap
      // can only fall back to the history list.
      expect(notification.tripId, equals(1));
      expect(notifications.foregroundCancelCount, equals(1));
    });

    test('stop from Paused also reports the finalized metrics', () async {
      final stateMachine = container.read(tripStateMachineProvider.notifier);

      stateMachine.startDetecting();
      stateMachine.startTripWithId(1);
      stateMachine.pauseTrip();
      stateMachine.stopTrip(
        finalTrip: _finalTrip(distance: 800, duration: 300),
      );

      final notification = notifications.stopNotifications.single;
      expect(notification.distance, equals(800.0));
      expect(notification.duration, equals(const Duration(seconds: 300)));
      expect(container.read(tripStateMachineProvider).hasActiveTrip, isFalse);
    });

    test('a discarded trip is not announced but still clears the foreground '
        'notification', () async {
      final stateMachine = container.read(tripStateMachineProvider.notifier);

      stateMachine.startDetecting();
      stateMachine.startTripWithId(1);
      stateMachine.stopTrip(discarded: true, finalTrip: _finalTrip());

      expect(notifications.stopNotifications, isEmpty);
      expect(notifications.foregroundCancelCount, equals(1));
    });

    test('the foreground notification is cancelled even when the recorder '
        'provider is in error', () async {
      final erroring = ProviderContainer(
        overrides: [
          notificationServiceProvider.overrideWith(() => notifications),
          tripRecorderServiceProvider.overrideWith(
            _FailingTripRecorderService.new,
          ),
        ],
      );
      addTearDown(erroring.dispose);
      await erroring.read(settingsServiceProvider.future);

      final stateMachine = erroring.read(tripStateMachineProvider.notifier);
      stateMachine.startDetecting();
      stateMachine.startTripWithId(1);
      stateMachine.stopTrip(finalTrip: _finalTrip());

      expect(notifications.stopNotifications, hasLength(1));
      expect(notifications.foregroundCancelCount, equals(1));
    });

    test('a stop with no final trip still clears the foreground '
        'notification', () async {
      final stateMachine = container.read(tripStateMachineProvider.notifier);

      stateMachine.startDetecting();
      stateMachine.startTripWithId(1);
      stateMachine.stopTrip();

      expect(notifications.stopNotifications, isEmpty);
      expect(notifications.foregroundCancelCount, equals(1));
    });

    test('should prevent invalid transitions', () async {
      final stateMachine = container.read(tripStateMachineProvider.notifier);

      // Try to pause from Idle (should do nothing)
      stateMachine.pauseTrip();
      var state = container.read(tripStateMachineProvider);
      state.when(
        idle: () => expect(true, isTrue), // State is Idle
        detecting: (_) => fail('Should be Idle'),
        active: (_, _) => fail('Should be Idle'),
        paused: (tripId, startTime, pauseStartTime) => fail('Should be Idle'),
      );

      // Try to resume from Idle (should do nothing)
      stateMachine.resumeTrip();
      state = container.read(tripStateMachineProvider);
      state.when(
        idle: () => expect(true, isTrue), // State is Idle
        detecting: (_) => fail('Should be Idle'),
        active: (_, _) => fail('Should be Idle'),
        paused: (tripId, startTime, pauseStartTime) => fail('Should be Idle'),
      );
    });

    test('should detect detection timeout', () async {
      final stateMachine = container.read(tripStateMachineProvider.notifier);

      stateMachine.startDetecting();

      // Immediately should not be timed out
      expect(stateMachine.hasDetectionTimedOut(), isFalse);

      // Back-date the detection start past the timeout to exercise the
      // expired branch (a clock can't be injected, so set state directly).
      stateMachine.state = TripState.detecting(
        detectionStartTime: DateTime.now().subtract(
          const Duration(seconds: AppConstants.detectionTimeoutSeconds + 5),
        ),
      );
      expect(stateMachine.hasDetectionTimedOut(), isTrue);

      // Not in a detecting state -> never timed out.
      stateMachine.state = const TripState.idle();
      expect(stateMachine.hasDetectionTimedOut(), isFalse);
    });

    test('should preserve trip ID across state transitions', () async {
      final stateMachine = container.read(tripStateMachineProvider.notifier);

      stateMachine.startDetecting();
      const testTripId = 1; // Mock database trip ID
      stateMachine.startTripWithId(testTripId);

      stateMachine.pauseTrip();
      var state = container.read(tripStateMachineProvider);
      expect(state.currentTripId, equals(testTripId));

      stateMachine.resumeTrip();
      state = container.read(tripStateMachineProvider);
      expect(state.currentTripId, equals(testTripId));
    });
  });

  group('TripState Extensions', () {
    test('hasActiveTrip should be true for Active and Paused', () {
      const idle = TripState.idle();
      final detecting = TripState.detecting(detectionStartTime: DateTime.now());
      final active = TripState.active(tripId: 1, startTime: DateTime.now());
      final paused = TripState.paused(
        tripId: 1,
        startTime: DateTime.now(),
        pauseStartTime: DateTime.now(),
      );

      expect(idle.hasActiveTrip, isFalse);
      expect(detecting.hasActiveTrip, isFalse);
      expect(active.hasActiveTrip, isTrue);
      expect(paused.hasActiveTrip, isTrue);
    });

    test('isRecording should only be true for Active', () {
      const idle = TripState.idle();
      final detecting = TripState.detecting(detectionStartTime: DateTime.now());
      final active = TripState.active(tripId: 1, startTime: DateTime.now());
      final paused = TripState.paused(
        tripId: 1,
        startTime: DateTime.now(),
        pauseStartTime: DateTime.now(),
      );

      expect(idle.isRecording, isFalse);
      expect(detecting.isRecording, isFalse);
      expect(active.isRecording, isTrue);
      expect(paused.isRecording, isFalse);
    });

    test('currentTripId should return ID for Active and Paused', () {
      const idle = TripState.idle();
      final active = TripState.active(tripId: 123, startTime: DateTime.now());
      final paused = TripState.paused(
        tripId: 456,
        startTime: DateTime.now(),
        pauseStartTime: DateTime.now(),
      );

      expect(idle.currentTripId, isNull);
      expect(active.currentTripId, equals(123));
      expect(paused.currentTripId, equals(456));
    });
  });
}
