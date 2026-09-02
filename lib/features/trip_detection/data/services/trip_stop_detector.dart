import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/location_data.dart';
import '../../domain/models/motion_data.dart';
import '../../domain/models/trip_stop_state.dart';
import '../../../../core/audit/audit_event.dart';
import '../../../../core/audit/audit_log.dart';
import '../../../../core/constants/app_constants.dart';
import 'stationary_window.dart';

part 'trip_stop_detector.g.dart';

/// Service that detects when a cycling trip should pause or stop
///
/// Analyzes motion and GPS data to distinguish between:
/// - Brief stops (traffic lights): Keep trip active
/// - Moderate pauses (rest stops): Pause trip, allow resume
/// - Extended stops (trip end): Stop trip and finalize
@riverpod
class TripStopDetector extends _$TripStopDetector {
  @override
  TripStopState build() {
    return TripStopState.initial();
  }

  /// Sliding window of recent sensor samples backing the stationary verdict.
  ///
  /// Scratch state, not observable state: it never belongs in [TripStopState],
  /// which is watched by the UI. Cleared by [reset].
  final StationaryWindow _window = StationaryWindow();

  /// Last sample fed to the window. While paused the coordinator runs both
  /// [shouldResumeTrip] and [analyzeForTripStop] on the same reading, and each
  /// must not enter the window twice.
  MotionData? _lastWindowedMotion;

  /// Analyze motion and GPS data to determine trip stop decision
  ///
  /// Returns [StopDecision] indicating whether to continue, pause, or stop trip.
  ///
  /// Called for every motion sample (50 Hz). The stationary and movement
  /// counters only advance once per
  /// [AppConstants.detectionEvaluationInterval], so
  /// `minConsecutiveStationaryDetections` and
  /// `tripStopMovementHysteresisSamples` mean seconds rather than a few tens of
  /// milliseconds. Uncounted samples still keep the pause timer up to date and
  /// still feed the sliding window.
  ///
  /// [tripIsPaused] must be true when the trip is already in the paused state.
  /// It disables the movement hysteresis that clears the pause: while paused,
  /// only a real resume ([shouldResumeTrip], after which the coordinator calls
  /// [reset]) may clear the accumulated pause. Otherwise intermittent movement
  /// — a rider shuffling the bike around every few seconds — kept resetting the
  /// auto-stop countdown without ever satisfying the 5 s continuous-movement
  /// resume rule, leaving a "zombie" pause that neither resumed nor stopped
  /// while GPS and the foreground service stayed up.
  ///
  /// [now] exists so tests can drive the clock deterministically; production
  /// callers omit it.
  Future<StopDecision> analyzeForTripStop(
    MotionData motion,
    LocationData? location, {
    DateTime? now,
    bool tripIsPaused = false,
  }) async {
    final timestamp = now ?? DateTime.now();

    // Check if currently stationary
    final isStationary = _isStationary(motion, location, timestamp);

    final canCount = state.canCountDetection(
      timestamp,
      AppConstants.detectionEvaluationInterval,
    );

    if (isStationary) {
      // Increment consecutive stationary detections.
      // A stationary reading also clears the movement hysteresis counter so a
      // single transient spike between two stationary readings is forgiven.
      if (state.consecutiveStationaryDetections == 0) {
        // First stationary detection - start pause timer
        state = state.startPause(timestamp);
      } else if (canCount) {
        // Continue tracking stationary state
        state = state.incrementStationary(timestamp);
      }

      // Update pause duration
      state = state.updatePauseDuration(timestamp);

      // Determine decision based on pause duration
      return _evaluatePauseDuration();
    } else {
      // Movement detected. GPS speed at a true standstill is noisy, so we
      // debounce: only reset the accumulated pause once movement is sustained
      // across `tripStopMovementHysteresisSamples` counted readings. A single
      // transient reading must not zero the pause timer.
      if (state.isStationary) {
        if (canCount) {
          state = state.incrementMovement(timestamp);
        }

        if (!tripIsPaused &&
            state.consecutiveMovementDetections >=
                AppConstants.tripStopMovementHysteresisSamples) {
          // Sustained movement confirmed on a still-active trip - reset the
          // pause so brief stops don't accumulate towards the auto-stop.
          state = state.resetPause();
          return StopDecision.continueTrip;
        }

        // Not yet confirmed as movement (or the trip is paused, where only a
        // real resume may clear the pause): keep the pause accumulating so the
        // auto-stop / auto-pause logic still applies.
        state = state.updatePauseDuration(timestamp);
        return _evaluatePauseDuration();
      }
      return StopDecision.continueTrip;
    }
  }

  /// Check if trip should resume after pause
  ///
  /// Returns true only once movement has been sustained for
  /// [AppConstants.resumeMovementThresholdSeconds]; a single non-stationary
  /// sample (a bump, a GPS speed spike) must not resume a paused trip.
  ///
  /// [now] exists so tests can drive the clock deterministically.
  bool shouldResumeTrip(
    MotionData motion,
    LocationData? location, {
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();

    if (_isStationary(motion, location, timestamp)) {
      // Movement interrupted - restart the sustained-movement timer.
      if (state.movementStartTime != null) {
        state = state.copyWith(movementStartTime: null);
      }
      return false;
    }

    final movementStart = state.movementStartTime;
    if (movementStart == null) {
      state = state.copyWith(movementStartTime: timestamp);
      return false;
    }

    return timestamp.difference(movementStart) >=
        const Duration(seconds: AppConstants.resumeMovementThresholdSeconds);
  }

  /// Reset detection state
  void reset() {
    state = TripStopState.initial();
    _window.clear();
    _lastWindowedMotion = null;
  }

  /// Check if motion and GPS indicate a stationary rider.
  ///
  /// Combination rule, in order of trust:
  ///
  /// 1. A **fresh** fix (younger than [AppConstants.stationaryGpsMaxAge])
  ///    reading at or above [AppConstants.movingSpeedMinKmh] means moving,
  ///    whatever the sensors say — a phone lying in a pannier is calm while the
  ///    bike rolls.
  /// 2. A fresh fix below [AppConstants.stationarySpeedMaxKmh] is strong
  ///    evidence of a standstill, so only the vibration criterion has to agree;
  ///    the rotation criterion is dropped, because a pocketed phone turns
  ///    freely while the bike stands still. Sustained vibration still overrides
  ///    the fix (a bad fix during a rough descent).
  /// 3. Between the two speeds, and whenever GPS is missing or stale, the
  ///    windowed sensor criteria decide on their own (both must agree).
  bool _isStationary(MotionData motion, LocationData? location, DateTime now) {
    if (!identical(motion, _lastWindowedMotion)) {
      _window.add(motion, now);
      _lastWindowedMotion = motion;
    }

    final speedKmh = _freshSpeedKmh(location, now);
    final verdict = _stationaryVerdict(speedKmh);

    if (AuditLog.verbose) {
      // Emitted from the detector rather than from `StationaryWindow`: the
      // window is mutable scratch state with no vocabulary of its own, and the
      // interesting part is which of the three arms decided.
      //
      // This is the event item 9 of the device checklist turns on. The
      // "basket case" reads as src:gps with a high speed and sta:false; and a
      // false pause on a slow climb shows up as src:sensors with a speed
      // sitting in the dead band between stationarySpeedMaxKmh and
      // movingSpeedMinKmh, where neither GPS arm applies and the sensors decide
      // alone.
      AuditLog.emitVerbose(
        AuditEvent.window,
        () => <String, Object?>{
          'n': _window.length,
          'sd': _window.accelerationStdDev,
          'gy': _window.averageRotation,
          'sta': verdict,
          // Three arms, three sources: GPS alone decides "moving"; below the
          // stationary threshold GPS only *admits* a stop and the vibration
          // check has the last word (`gps+vib`); in the dead band between the
          // two the sensors decide alone.
          'src': speedKmh == null
              ? 'sensors'
              : speedKmh >= AppConstants.movingSpeedMinKmh
              ? 'gps'
              : speedKmh < AppConstants.stationarySpeedMaxKmh
              ? 'gps+vib'
              : 'sensors',
          'spk': speedKmh,
        },
      );
    }

    return verdict;
  }

  /// The stationary verdict itself, kept separate so it can be reported
  /// without being computed twice.
  bool _stationaryVerdict(double? speedKmh) {
    if (speedKmh != null) {
      if (speedKmh >= AppConstants.movingSpeedMinKmh) return false;
      if (speedKmh < AppConstants.stationarySpeedMaxKmh) {
        return _window.isVibrationFree;
      }
    }

    return _window.isCalm;
  }

  /// GPS speed in km/h if the fix is recent enough to be trusted, else null.
  double? _freshSpeedKmh(LocationData? location, DateTime now) {
    if (location == null) return null;

    final age = now.difference(location.timestamp).abs();
    if (age > AppConstants.stationaryGpsMaxAge) return null;

    return location.speedKmh;
  }

  /// Evaluate pause duration and return appropriate decision
  StopDecision _evaluatePauseDuration() {
    final pauseSeconds = state.pauseDuration.inSeconds;

    // Check if should stop trip (extended pause)
    if (pauseSeconds >= AppConstants.maxPauseDurationSeconds) {
      return StopDecision.stopTrip;
    }

    // Check if should pause trip (moderate pause)
    if (pauseSeconds >= AppConstants.minPauseDurationSeconds &&
        state.consecutiveStationaryDetections >=
            AppConstants.minConsecutiveStationaryDetections) {
      return StopDecision.pauseTrip;
    }

    // Brief pause - continue trip
    return StopDecision.continueTrip;
  }
}
