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

  // Database
  static const String databaseName = 'autoride.db';
  static const int databaseVersion = 1;
}
