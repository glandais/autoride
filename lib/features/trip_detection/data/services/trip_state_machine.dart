import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/trip_state.dart';
import '../../../../core/constants/app_constants.dart';
import 'notification_service.dart';
import 'trip_recorder_service.dart';

part 'trip_state_machine.g.dart';

/// State machine for managing trip lifecycle
@riverpod
class TripStateMachine extends _$TripStateMachine {
  @override
  TripState build() {
    return const TripState.idle();
  }

  /// Transition to Detecting state when motion is detected
  void startDetecting() {
    state.mapOrNull(
      idle: (_) {
        state = TripState.detecting(detectionStartTime: DateTime.now());
      },
    );
  }

  /// Transition to Active state when cycling is confirmed
  /// Accepts trip ID from database (T015)
  void startTripWithId(int tripId) {
    state.mapOrNull(
      detecting: (_) {
        state = TripState.active(tripId: tripId, startTime: DateTime.now());

        // Show trip start notification
        ref
            .read(notificationServiceProvider.notifier)
            .showTripStartNotification();
      },
    );
  }

  /// Transition to Paused state when stationary during active trip
  void pauseTrip() {
    state.mapOrNull(
      active: (activeState) {
        state = TripState.paused(
          tripId: activeState.tripId,
          startTime: activeState.startTime,
          pauseStartTime: DateTime.now(),
        );
      },
    );
  }

  /// Resume trip from Paused state
  void resumeTrip() {
    state.mapOrNull(
      paused: (pausedState) {
        state = TripState.active(
          tripId: pausedState.tripId,
          startTime: pausedState.startTime,
        );
      },
    );
  }

  /// Stop trip and return to Idle (manual stop or timeout)
  void stopTrip() {
    // Capture trip metrics before stopping (for notification)
    final recorderAsync = ref.read(tripRecorderServiceProvider);

    state.mapOrNull(
      detecting: (_) {
        state = const TripState.idle();
      },
      active: (_) {
        // Show trip stop notification with final metrics
        recorderAsync.whenData((metrics) {
          ref
              .read(notificationServiceProvider.notifier)
              .showTripStopNotification(
                distance: metrics.distanceMeters,
                duration: Duration(seconds: metrics.durationSeconds),
                avgSpeed: metrics.avgSpeedKmh ?? 0.0,
              );

          // Cancel foreground notification
          ref
              .read(notificationServiceProvider.notifier)
              .cancelForegroundNotification();
        });

        state = const TripState.idle();
      },
      paused: (_) {
        // Show trip stop notification with final metrics
        recorderAsync.whenData((metrics) {
          ref
              .read(notificationServiceProvider.notifier)
              .showTripStopNotification(
                distance: metrics.distanceMeters,
                duration: Duration(seconds: metrics.durationSeconds),
                avgSpeed: metrics.avgSpeedKmh ?? 0.0,
              );

          // Cancel foreground notification
          ref
              .read(notificationServiceProvider.notifier)
              .cancelForegroundNotification();
        });

        state = const TripState.idle();
      },
    );
  }

  /// Check if detection phase has timed out
  /// Returns true if in Detecting state for > detection timeout
  bool hasDetectionTimedOut() {
    return state.mapOrNull(
          detecting: (detectingState) {
            final elapsed = DateTime.now().difference(
              detectingState.detectionStartTime,
            );
            return elapsed.inSeconds > AppConstants.detectionTimeoutSeconds;
          },
        ) ??
        false;
  }

  /// Check if pause has timed out (exceeded max pause duration)
  /// Returns true if paused for > max pause time
  bool hasPauseTimedOut() {
    return state.mapOrNull(
          paused: (pausedState) {
            final elapsed = DateTime.now().difference(
              pausedState.pauseStartTime,
            );
            return elapsed.inSeconds > AppConstants.maxPauseDurationSeconds;
          },
        ) ??
        false;
  }
}
