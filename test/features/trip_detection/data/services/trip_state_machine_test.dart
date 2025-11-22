import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:autoride/features/trip_detection/data/services/trip_state_machine.dart';
import 'package:autoride/features/trip_detection/domain/models/trip_state.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
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
        paused: (tripId, startTime, pauseStartTime) => fail('Should be Detecting'),
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
        active: (id, startTime) => expect(id, equals(testTripId)), // State is Active
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
        paused: (tripId, startTime, pauseStartTime) => expect(true, isTrue), // State is Paused
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
        active: (id, startTime) => expect(id, equals(testTripId)), // State is Active
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

      // Would need to wait 30+ seconds for real timeout
      // In actual usage, a timer will check this periodically
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
      final detecting = TripState.detecting(
        detectionStartTime: DateTime.now(),
      );
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
      final detecting = TripState.detecting(
        detectionStartTime: DateTime.now(),
      );
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
