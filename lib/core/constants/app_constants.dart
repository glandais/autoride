/// App-wide constants for AutoRide
class AppConstants {
  // Prevent instantiation
  AppConstants._();

  // Detection thresholds
  static const double cyclingSpeedMin = 8.0; // km/h
  static const double cyclingSpeedMax = 40.0; // km/h
  static const double movementThreshold = 1.5; // m/s² acceleration

  // Location settings
  static const double distanceFilter = 15.0; // meters
  static const int locationTimeLimit = 30; // seconds

  // ML settings
  static const int sensorSamplingRate = 50; // Hz
  static const int mlInferenceInterval = 10; // seconds
  static const double confidenceThreshold = 0.85;

  // Battery optimization
  static const int batteryCheckIntervalMinutes = 5;
  static const int criticalBatteryThreshold = 10; // %
  static const int lowBatteryThreshold = 20; // %
  static const int mediumBatteryThreshold = 50; // %
  static const int sensorBufferSize = 3000; // samples (60s at 50Hz)

  // GPS Inactivity Timeout
  static const Duration gpsInactivityTimeout = Duration(seconds: 30);

  // Distance Filters by State
  static const int distanceFilterStationary = 100; // meters
  static const int distanceFilterMoving = 20; // meters
  static const int distanceFilterCycling = 15; // meters (optimal for cycling)

  // Location Update Intervals by Power Mode
  static const Duration locationUpdateNormal = Duration(seconds: 30);
  static const Duration locationUpdateMedium = Duration(seconds: 40);
  static const Duration locationUpdateLow = Duration(seconds: 60);
  static const Duration locationUpdateCritical = Duration(seconds: 90);

  // Sensor Sampling Rates by Power Mode (Hz)
  static const int sensorSamplingRateNormal = 50;
  static const int sensorSamplingRateMedium = 40;
  static const int sensorSamplingRateLow = 25;
  static const int sensorSamplingRateCritical = 20;

  // Cycling Detection Thresholds (T008)

  // Acceleration thresholds (m/s²)
  static const double cyclingAccelerationMin = 10.0;  // Minimum for cycling
  static const double cyclingAccelerationMax = 20.0;  // Maximum typical cycling
  static const double walkingAccelerationMax = 12.0;  // Walking typically <12

  // Rotation thresholds (rad/s)
  static const double cyclingRotationMin = 0.5;   // Minimum rotation for cycling
  static const double cyclingRotationMax = 3.0;   // Maximum typical rotation

  // Stationary thresholds (T007, used in T014)
  static const double stationaryAccelerationMax = 1.0;  // m/s² - max for stationary
  static const double stationaryRotationMax = 0.2;      // rad/s - max for stationary

  // Pedaling frequency (Hz)
  static const double pedalingFrequencyMin = 0.5;   // 30 RPM minimum
  static const double pedalingFrequencyMax = 2.0;   // 120 RPM maximum
  static const double pedalingFrequencyTypical = 1.2; // 72 RPM typical

  // Speed validation (km/h) - extending existing
  static const double cyclingSpeedTypical = 18.0; // Typical commuting speed

  // Pattern analysis
  static const int minSamplesForPattern = 100;  // ~2 seconds at 50Hz
  static const int pedalingCycleSamples = 50;   // ~1 second for one pedal cycle

  // Confidence thresholds
  static const double minConfidenceForDetection = 0.6;  // Minimum to trigger
  static const double highConfidenceThreshold = 0.8;    // High confidence

  // Activity classification weights
  static const double motionScoreWeight = 0.4;     // 40% weight
  static const double speedScoreWeight = 0.35;     // 35% weight
  static const double frequencyScoreWeight = 0.25; // 25% weight

  // Trip State Machine Configuration (T012)
  static const int detectionTimeoutSeconds = 30; // Max time in Detecting before timeout
  static const int stationaryThresholdSeconds = 10; // Stationary time before pause
  static const int maxPauseDurationSeconds = 300; // 5 min - max pause before auto-stop
  static const int resumeMovementThresholdSeconds = 5; // Movement time before resume

  // Trip Start Detection Configuration (T013)

  // Confidence threshold to trigger trip start (0.0-1.0)
  static const double tripStartConfidenceThreshold = 0.7;

  // Minimum consecutive detections before starting trip
  static const int tripStartMinConsecutiveDetections = 3;

  // Time window for consecutive detection counting (seconds)
  static const int tripStartDetectionWindowSeconds = 5;

  // Cooldown period after false start (seconds)
  static const int tripStartCooldownPeriodSeconds = 30;

  // GPS speed range for cycling validation (km/h)
  // Note: cyclingSpeedMin and cyclingSpeedMax already defined above

  // Grace period before GPS required (seconds)
  // Allows motion-only detection for first N seconds (e.g., GPS lock delay)
  static const int tripStartGpsGracePeriodSeconds = 10;

  // Weighting for confidence calculation
  static const double tripStartMotionWeight = 0.6;    // 60% when GPS available
  static const double tripStartSpeedWeight = 0.4;     // 40% when GPS available
  // When GPS unavailable, motion weight = 1.0 (100%)

  // Trip Stop Detection Configuration (T014)

  // Minimum pause duration before considering pause state (seconds)
  // Brief stops (< this value) keep trip active
  static const int minPauseDurationSeconds = 30; // 30s - traffic lights, intersections

  // Maximum pause duration before auto-stop (seconds)
  // Note: maxPauseDurationSeconds already defined above = 300 (5 min)

  // Minimum consecutive stationary detections before pause
  static const int minConsecutiveStationaryDetections = 3;

  // Minimum movement duration to resume trip (seconds)
  // Note: resumeMovementThresholdSeconds already defined above = 5

  // Stationary thresholds already defined in T007:
  // - stationaryAccelerationMax = 1.0 m/s²
  // - stationaryRotationMax = 0.2 rad/s

  // Trip Recording Configuration (T015)

  // Route point distance filtering (meters)
  // Reuses cycling distance filter value for consistency
  static const double minRoutePointDistanceMeters = 15.0;

  // Route point buffer size before batch database save
  // 100 points ≈ 2KB memory, saves every ~1.5km at 15m intervals
  static const int routePointBufferSize = 100;

  // Maximum interval between buffer flushes (seconds)
  // Fallback if distance filter not triggered (ensures data persistence)
  static const int maxRecordingIntervalSeconds = 30;

  // Maximum GPS accuracy threshold (meters)
  // Route points with accuracy > this value are rejected (poor GPS fix)
  static const double maxLocationAccuracyMeters = 50.0;

  // Maximum cycling speed for outlier rejection (km/h)
  // Route points with speed > this value are rejected (likely GPS error)
  // Higher than cyclingSpeedMax to allow safety margin
  static const double maxCyclingSpeedKmh = 60.0;

  // Database
  static const String databaseName = 'autoride.db';
  static const int databaseVersion = 1;

  // Onboarding Configuration (T021)
  static const String onboardingCompleteKey = 'onboarding_complete';
  static const int onboardingPageCount = 5;
  static const Duration onboardingAnimationDuration = Duration(milliseconds: 300);
  static const Duration onboardingPageTransitionDuration = Duration(milliseconds: 250);
}
