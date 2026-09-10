import '../constants/app_constants.dart';

/// Schema version and the build's active thresholds, written into the header
/// of every exported audit log.
///
/// Why the thresholds travel with the file: a log read three weeks later is
/// interpreted against `AppConstants` *as it was when the log was written*.
/// Reading today's `app_constants.dart` to explain a decision taken by an older
/// build is how you conclude the opposite of what happened.
abstract final class AuditSchema {
  /// Bumped when the meaning of an existing key changes.
  ///
  /// Adding a new event type or a new field does **not** need a bump: the
  /// analysis side ignores what it does not know, and the stored line is opaque
  /// text, so old and new lines coexist in one file.
  ///
  /// * 2 — the stop/resume detector clock is `so` (seconds since the
  ///   stationary onset), where it used to be `pd` and read like the trip's
  ///   own `pau` (L-086).
  /// * 3 — `start.c` is computed from a *window* (T050, L-079). The key is the
  ///   same and so is its range, but its motion half no longer comes from the
  ///   `mag`/`gyr` on the same line, so reconstructing `c` from those two — the
  ///   recipe every earlier reading of this log used — silently reproduces the
  ///   old arithmetic. Read `asd`/`gav` against `k.asd*`/`k.gav*` instead.
  static const int version = 3;

  /// The detection thresholds this build is running with, under short keys.
  ///
  /// Pinned by `test/core/audit/audit_event_test.dart`: a detection constant
  /// added without being exposed here fails the suite, because the next log
  /// would silently be missing the number needed to read it.
  static Map<String, Object?> thresholds() => <String, Object?>{
    // Speed envelope
    'cycMin': AppConstants.cyclingSpeedMin,
    'cycMax': AppConstants.cyclingSpeedMax,
    'maxKmh': AppConstants.maxCyclingSpeedKmh,
    // GPS gate and watchdog
    'gpsIdle': AppConstants.gpsInactivityTimeout.inSeconds,
    'gpsLoss': AppConstants.gpsLossStopTimeout.inSeconds,
    'gpsAge': AppConstants.stationaryGpsMaxAge.inSeconds,
    // Trip start
    'conf': AppConstants.tripStartConfidenceThreshold,
    'nDet': AppConstants.tripStartMinConsecutiveDetections,
    'detWin': AppConstants.tripStartDetectionWindowSeconds,
    'detTo': AppConstants.detectionTimeoutSeconds,
    'evalMs': AppConstants.detectionEvaluationInterval.inMilliseconds,
    'cool': AppConstants.tripStartCooldownPeriodSeconds,
    'wMot': AppConstants.tripStartMotionWeight,
    'wSpd': AppConstants.tripStartSpeedWeight,
    // Windowed cycling fit (T050, L-079) — the bands `asd` and `gav` are
    // scored against. The instantaneous `cyclingAcceleration*`/`cyclingRotation*`
    // bands are deliberately absent: since T050 no start decision reads them.
    'asdMin': AppConstants.cyclingAccelStdMin,
    'asdIdeal': AppConstants.cyclingAccelStdIdeal,
    'asdMax': AppConstants.cyclingAccelStdMax,
    'gavMin': AppConstants.cyclingGyroMeanMin,
    'gavIdeal': AppConstants.cyclingGyroMeanIdeal,
    'gavMax': AppConstants.cyclingGyroMeanMax,
    'wnMin': AppConstants.tripStartMotionWindowMinSamples,
    // Suspected-vehicle flag (T053, L-106) — measured speeds only, and a
    // badge rather than a refusal. Not to be recalibrated; see `veh`.
    'vehKmh': AppConstants.vehicleSpeedKmh,
    'vehMin': AppConstants.vehicleSpeedMinFixes,
    'vehShare': AppConstants.vehicleSpeedMinShare,
    // Speed trust and derived speed (T048)
    'spAcc': AppConstants.speedTrustMaxAccuracyMeters,
    'spAge': AppConstants.speedTrustMaxAge.inSeconds,
    'dspMin': AppConstants.derivedSpeedMinGap.inSeconds,
    // A factor, not a duration: the effective bound is `pwr.ui × dspFac`,
    // because a fixed one below the mode's own update interval never fires.
    'dspFac': AppConstants.derivedSpeedMaxGapFactor,
    // Stationary window (L-070)
    'winMs': AppConstants.stationaryWindowDuration.inMilliseconds,
    'winMax': AppConstants.stationaryWindowMaxSamples,
    'sdMax': AppConstants.stationaryAccelerationStdDevMax,
    'gyMax': AppConstants.stationaryRotationAverageMax,
    'staKmh': AppConstants.stationarySpeedMaxKmh,
    'movKmh': AppConstants.movingSpeedMinKmh,
    // Pause / stop
    'minPause': AppConstants.minPauseDurationSeconds,
    'maxPause': AppConstants.maxPauseDurationSeconds,
    'resume': AppConstants.resumeMovementThresholdSeconds,
    'nSta': AppConstants.minConsecutiveStationaryDetections,
    'hyst': AppConstants.tripStopMovementHysteresisSamples,
    // Recording filters
    'rpDist': AppConstants.minRoutePointDistanceMeters,
    'rpAcc': AppConstants.maxLocationAccuracyMeters,
    // A ratio, not a distance: a point must beat its own accuracy times this
    // (L-094), which is why `rpDist` and `rpAcc` alone cannot explain a drop.
    'rpRatio': AppConstants.routePointAccuracyRatio,
    'rpBuf': AppConstants.routePointBufferSize,
    'recInt': AppConstants.maxRecordingIntervalSeconds,
    'minTrip': AppConstants.minTripDurationSeconds,
    'minTripPts': AppConstants.minTripRoutePoints,
    'minTripNet': AppConstants.minTripNetDisplacementMeters,
    'minTripKmh': AppConstants.minTripAvgSpeedKmh,
    // The distance the speed arm of the discard rule needs before it may keep a
    // recording whose displacement failed (T052, L-103).
    'minTripLoop': AppConstants.minTripLoopDistanceMeters,
    // The no-progress deadline (T052, L-103), in seconds.
    'noProg': AppConstants.noProgressStopTimeout.inSeconds,
    // Pre-trip buffer (L-076)
    'preBufS': AppConstants.preTripLocationBufferDuration.inSeconds,
    'preBufN': AppConstants.preTripLocationBufferMaxPoints,
    // Power modes
    'hzN': AppConstants.sensorSamplingRateNormal,
    'hzM': AppConstants.sensorSamplingRateMedium,
    'hzL': AppConstants.sensorSamplingRateLow,
    'hzC': AppConstants.sensorSamplingRateCritical,
    'dfCyc': AppConstants.distanceFilterCycling,
    'dfMov': AppConstants.distanceFilterMoving,
    'dfLow': AppConstants.distanceFilterLowPower,
    'dfCrit': AppConstants.distanceFilterCriticalPower,
    'batCrit': AppConstants.criticalBatteryThreshold,
    'batLow': AppConstants.lowBatteryThreshold,
    'batMed': AppConstants.mediumBatteryThreshold,
  };
}
