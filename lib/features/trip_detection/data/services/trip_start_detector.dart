import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/location_data.dart';
import '../../domain/models/motion_data.dart';
import '../../domain/models/trip_start_state.dart';
import 'stationary_window.dart';
import '../../../../core/audit/audit_event.dart';
import '../../../../core/audit/audit_log.dart';
import '../../../../core/constants/app_constants.dart';

part 'trip_start_detector.g.dart';

/// Service that detects when a cycling trip should start
///
/// Combines motion pattern analysis with GPS speed validation
/// to determine trip start with high confidence and minimal false positives.
@riverpod
class TripStartDetector extends _$TripStartDetector {
  /// The samples the confidence is computed over (T050, L-079).
  ///
  /// Same class the stop path uses, read for the opposite question — see
  /// [_getMotionScore]. Plain mutable scratch state, like the coordinator's own
  /// windows: it is a measurement of the last second and a half, not part of
  /// the detector's observable state.
  final StationaryWindow _motionWindow = StationaryWindow(
    // Exactly the interval the streak counts, so that "this second was cycling"
    // is a statement about that second and nothing before it.
    duration: AppConstants.detectionEvaluationInterval,
  );

  /// Spread of accelerometer magnitude over the current window (m/s²).
  ///
  /// Exposed for the audit's `asd`, which is what makes a refusal to start
  /// readable: the two numbers below are the whole of the motion score now.
  double get accelerationStdDev => _motionWindow.accelerationStdDev;

  /// Mean gyroscope magnitude over the current window (rad/s) — the audit's
  /// `gav`.
  double get averageRotation => _motionWindow.averageRotation;

  /// Samples currently retained — the audit's `wn`, without which an `asd` of 0
  /// cannot be told from a window that has not filled yet.
  int get motionWindowSamples => _motionWindow.length;

  @override
  TripStartState build() {
    return TripStartState.initial();
  }

  /// Analyze motion and GPS data to determine if trip should start
  ///
  /// Updates internal state and returns whether trip start should be triggered.
  ///
  /// This is called for every motion sample (50 Hz), but a *detection* is
  /// counted at most once per [AppConstants.detectionEvaluationInterval], so
  /// `tripStartMinConsecutiveDetections` means seconds of sustained cycling
  /// rather than a few tens of milliseconds. Samples arriving inside the
  /// current interval still refresh the confidence score.
  ///
  /// "Sustained" is now literal (L-093): the streak requires a positive
  /// detection in *every* interval, and one interval passing without one
  /// resets it to zero. `tripStartDetectionWindowSeconds` no longer bounds the
  /// streak — it only guards against resuming a stale one across a gap in
  /// which nothing was evaluated at all.
  ///
  /// [now] exists so tests can drive the clock deterministically; production
  /// callers omit it.
  Future<bool> analyzeForTripStart(
    MotionData motion,
    LocationData? location, {
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now();
    return _analyze(motion, location, timestamp);
  }

  Future<bool> _analyze(
    MotionData motion,
    LocationData? location,
    DateTime now,
  ) async {
    // Fed before the cooldown check, and before anything reads the window: the
    // sample is a measurement, not a decision, and a cooldown that ends mid-ride
    // must find a full window rather than spend another interval filling one.
    _motionWindow.add(motion, now);

    // Check if cooldown is still active
    if (state.cooldownActive) {
      if (state.isCooldownExpired(
        now,
        const Duration(seconds: AppConstants.tripStartCooldownPeriodSeconds),
      )) {
        // Cooldown expired, deactivate it. Journalled because the blind
        // window it opened is a reason a departure could be missed, and its
        // end is what makes the window measurable against `cool a:"arm"`.
        final period =
            state.cooldownDuration ??
            const Duration(
              seconds: AppConstants.tripStartCooldownPeriodSeconds,
            );
        AuditLog.emit(
          AuditEvent.cooldown,
          () => <String, Object?>{'a': 'expire', 'd': period.inSeconds},
          critical: true,
        );
        state = state.deactivateCooldown();
      } else {
        // Still in cooldown, don't detect
        return false;
      }
    }

    // Calculate confidence score
    final confidence = _calculateStartConfidence(location, now);

    // A new detection is only counted once per evaluation interval, and the
    // same boundary decides when the streak has missed one.
    final lastDetection = state.lastDetectionTime;
    final intervalElapsed =
        lastDetection == null ||
        now.difference(lastDetection) >=
            AppConstants.detectionEvaluationInterval;

    // Update state based on confidence and timing
    if (confidence >= AppConstants.tripStartConfidenceThreshold) {
      // Positive detection
      if (!intervalElapsed) {
        // Same evaluation interval: refresh confidence only. Do NOT advance
        // the streak or the detection timestamp, otherwise 50 Hz sampling
        // would satisfy the consecutive-detection threshold in ~60 ms.
        state = state.copyWith(confidence: confidence);
      } else {
        // A gap with no evaluation at all — the process was suspended, the
        // sensor stream stalled — leaves a streak that describes a moment that
        // is over. Start a new one rather than continuing it.
        final stale = !state.isWithinDetectionWindow(
          now,
          const Duration(seconds: AppConstants.tripStartDetectionWindowSeconds),
        );
        state = state.copyWith(
          confidence: confidence,
          consecutiveDetections: stale ? 1 : state.consecutiveDetections + 1,
          lastDetectionTime: now,
        );
      }
    } else {
      // Negative detection. The streak means *consecutive* evaluation
      // intervals, so it dies as soon as one of them has gone by without a
      // positive detection in it — which is precisely what `intervalElapsed`
      // says here, the last positive being more than one interval old (L-093).
      //
      // The previous rule kept the streak alive for as long as a positive
      // landed within `tripStartDetectionWindowSeconds` of the previous one:
      // Pixel trip 3 of the 2026-09-03 run held `n=2` through five consecutive
      // sub-threshold seconds and started a ride on the sixth. Three firm
      // gestures inside twelve seconds of cooking were enough.
      //
      // Sub-threshold samples *inside* the current interval only refresh the
      // confidence. That mattered more before T050, when the fit was a single
      // sample and dipped below the threshold constantly; a windowed score
      // barely moves within one interval, which is the point of it.
      if (intervalElapsed) {
        // `confidence` is carried rather than zeroed, unlike `reset()`: the
        // audit's `c` is the reason the reset happened and reading a flat 0
        // cannot distinguish a near miss from no motion at all.
        state = state.copyWith(
          confidence: confidence,
          consecutiveDetections: 0,
          lastDetectionTime: null,
        );
      } else {
        state = state.copyWith(confidence: confidence);
      }
    }

    // Check if should trigger trip start
    return shouldStartTrip();
  }

  /// Check if conditions are met to start trip
  bool shouldStartTrip() {
    return state.confidence >= AppConstants.tripStartConfidenceThreshold &&
        state.consecutiveDetections >=
            AppConstants.tripStartMinConsecutiveDetections &&
        !state.cooldownActive;
  }

  /// Activate cooldown period (e.g., after false start)
  ///
  /// [period] overrides `tripStartCooldownPeriodSeconds` — the vehicle veto
  /// arms a much longer one (T051).
  void activateCooldown({Duration? period}) {
    state = state.activateCooldown(DateTime.now(), period: period);
  }

  /// Reset detection state
  ///
  /// The motion window goes with it: a reset means the detector is to forget
  /// what it has seen — a session starting, a departure that failed, a ride
  /// that has just ended — and a window still holding the last second of that
  /// ride would score the first sample after it as if nothing had happened.
  void reset() {
    state = TripStartState.initial();
    _motionWindow.clear();
  }

  /// Calculate confidence score for trip start (0.0-1.0)
  ///
  /// Combines motion pattern score with GPS speed validation.
  /// If GPS unavailable, uses motion-only detection.
  ///
  /// "Unavailable" means *no usable speed*, not *no object*: a fix too coarse
  /// or too old for its speed to be believed takes the motion-only path as
  /// well (T048). The alternative is the arithmetic of L-087 — such a fix
  /// scores `speedScore` 0, caps the total at `tripStartMotionWeight` (0.60)
  /// below the 0.7 threshold, and no fix at all ends up scoring higher than a
  /// bad one.
  double _calculateStartConfidence(LocationData? location, DateTime now) {
    // Get motion pattern score from the window (T050)
    final motionScore = _getMotionScore();

    // If no usable GPS speed, use motion-only
    if (location == null || !location.speedIsTrustworthyAt(now)) {
      return motionScore;
    }

    // Get speed score from GPS
    final speedScore = _getSpeedScore(location);

    // Combine scores with weighted average
    final confidence =
        (motionScore * AppConstants.tripStartMotionWeight) +
        (speedScore * AppConstants.tripStartSpeedWeight);

    return confidence.clamp(0.0, 1.0);
  }

  /// Calculate motion pattern score (0.0-1.0) over the current window.
  ///
  /// **What changed in T050 (L-079).** This used to score the single sample it
  /// was handed, against the instantaneous bands `cyclingAccelerationMin/Max`
  /// and `cyclingRotationMin/Max`. On a bike |a| swings between 4 and 24 m/s²
  /// from one 20 ms sample to the next, so which side of the threshold the
  /// score landed on was decided by whichever sample happened to arrive on the
  /// evaluation boundary — a coin toss, and one weighted against starting:
  /// 6.5 % of the sampled instants of the confirmed 2026-09-06 ride cleared
  /// 0.7. Requiring three *consecutive* such boundaries (L-093) then turned a
  /// low per-sample probability into a ten-minute wait.
  ///
  /// The two quantities below are properties of a window, not of an instant,
  /// and they are what actually separates a bicycle from a pocket:
  ///
  /// * **spread of |a|** — gravity dominates the *level* in every orientation
  ///   (a still phone reads 9.81, a pedalling one 10.2), so the mean says
  ///   nothing; the standard deviation is the road coming up through the frame.
  /// * **mean |gyro|** — a sustained rotation rate, not a flick of the wrist.
  ///
  /// Both are already computed by [StationaryWindow], which the stop path uses
  /// to ask the opposite question. Reusing it keeps one implementation of the
  /// statistics and one buffer shape; its window (1.5 s) covers a full
  /// evaluation interval, which is the requirement here.
  double _getMotionScore() {
    // Too few samples to have a spread at all — the first sample of a session,
    // or a stream that has just stalled. Scoring 0 costs at most one interval.
    if (_motionWindow.length < AppConstants.tripStartMotionWindowMinSamples) {
      return 0.0;
    }

    final accelScore = _rampScore(
      _motionWindow.accelerationStdDev,
      min: AppConstants.cyclingAccelStdMin,
      ideal: AppConstants.cyclingAccelStdIdeal,
      max: AppConstants.cyclingAccelStdMax,
    );

    final gyroScore = _rampScore(
      _motionWindow.averageRotation,
      min: AppConstants.cyclingGyroMeanMin,
      ideal: AppConstants.cyclingGyroMeanIdeal,
      max: AppConstants.cyclingGyroMeanMax,
    );

    // Combine acceleration and gyroscope scores
    return ((accelScore * 0.5) + (gyroScore * 0.5)).clamp(0.0, 1.0);
  }

  /// 0 below [min], ramping to 1 at [ideal], 1 up to [max], 0 above it.
  ///
  /// Asymmetric on purpose, where the bands it replaces were triangular around
  /// a midpoint. There is no "too much vibration for a bicycle" short of
  /// something that is not a bicycle at all, so the plateau runs all the way to
  /// [max]: a rough road must not score *lower* than a smooth one, which is
  /// what a peak at a midpoint would do.
  static double _rampScore(
    double value, {
    required double min,
    required double ideal,
    required double max,
  }) {
    if (value < min || value > max) return 0.0;
    if (value >= ideal) return 1.0;
    return ((value - min) / (ideal - min)).clamp(0.0, 1.0);
  }

  /// Calculate GPS speed score (0.0-1.0)
  double _getSpeedScore(LocationData location) {
    final speedKmh = location.speedKmh;

    // Check if speed is in cycling range
    if (speedKmh < AppConstants.cyclingSpeedMin) {
      // Too slow (likely walking or stationary)
      return 0.0;
    } else if (speedKmh > AppConstants.cyclingSpeedMax) {
      // Too fast (likely driving)
      return 0.0;
    }

    // Within cycling range - calculate how well it fits
    // Highest score at typical cycling speed (18 km/h)
    const typicalSpeed = AppConstants.cyclingSpeedTypical;
    const speedRange =
        AppConstants.cyclingSpeedMax - AppConstants.cyclingSpeedMin;
    final deviation = (speedKmh - typicalSpeed).abs();

    // Score decreases as deviation from typical speed increases
    return (1.0 - (deviation / speedRange)).clamp(0.0, 1.0);
  }
}
