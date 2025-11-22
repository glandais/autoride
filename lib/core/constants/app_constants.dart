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

  // Database
  static const String databaseName = 'autoride.db';
  static const int databaseVersion = 1;
}
