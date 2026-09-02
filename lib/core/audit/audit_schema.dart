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
  static const int version = 2;

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
    'rpBuf': AppConstants.routePointBufferSize,
    'recInt': AppConstants.maxRecordingIntervalSeconds,
    'minTrip': AppConstants.minTripDurationSeconds,
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
