import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/trip.dart';
import '../../domain/models/trip_state.dart';
import '../../../../core/constants/app_constants.dart';
import 'notification_service.dart';

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

  /// Stop trip and return to Idle (manual stop or timeout).
  ///
  /// [finalTrip] is the finalized ride the recorder has just written, and is
  /// the only source the end-of-trip notification reads. It used to read the
  /// recorder provider's live `TripMetrics` instead, which announced either a
  /// value up to a metrics tick stale or — depending on the order of the
  /// recorder's own cleanup — a freshly zeroed 0 m / 0 s / 0 km/h, and skipped
  /// the notification entirely whenever that provider happened to be
  /// loading/erroring (L-069).
  ///
  /// [discarded] is set by the recorder when the recording was not a ride worth
  /// keeping — too short (L-068), or with too few route points to say anything
  /// happened (L-081). Its row is deleted, not saved, and such a ride must not
  /// announce itself with a "trip recorded" notification — but the foreground
  /// notification still has to be cancelled, or a phantom "trip in progress"
  /// would outlive the trip.
  void stopTrip({bool discarded = false, Trip? finalTrip}) {
    state.mapOrNull(
      detecting: (_) {
        state = const TripState.idle();
      },
      active: (_) {
        _finishRecording(discarded: discarded, finalTrip: finalTrip);
      },
      paused: (_) {
        _finishRecording(discarded: discarded, finalTrip: finalTrip);
      },
    );
  }

  /// Close out a recording: announce it (unless discarded) and return to Idle.
  ///
  /// The foreground notification is cancelled unconditionally — it is the one
  /// piece of UI that would otherwise survive the trip.
  void _finishRecording({required bool discarded, required Trip? finalTrip}) {
    final notifications = ref.read(notificationServiceProvider.notifier);

    if (!discarded && finalTrip != null) {
      notifications.showTripStopNotification(
        distance: finalTrip.distance,
        duration: Duration(seconds: finalTrip.duration),
        avgSpeed: finalTrip.avgSpeed ?? 0.0,
        // Null only if the row was never persisted; the notification then
        // opens the history list instead of a detail screen.
        tripId: finalTrip.id,
      );
    }

    notifications.cancelForegroundNotification();

    state = const TripState.idle();
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
}
