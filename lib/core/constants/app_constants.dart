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
  static const int lowBatteryThreshold = 20; // percent
  static const int sensorBufferSize = 3000; // samples (60s at 50Hz)

  // Database
  static const String databaseName = 'autoride.db';
  static const int databaseVersion = 1;
}
