import 'package:flutter_test/flutter_test.dart';
import 'package:autoride/features/settings/domain/models/detection_settings.dart';
import 'package:autoride/features/settings/domain/models/user_settings.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  group('UserSettings', () {
    test('should create default settings', () {
      const settings = UserSettings();

      // Detection defaults. Automatic detection ships ON: the app root starts
      // the coordinator as soon as permissions allow (audit #11).
      expect(settings.detection.automaticDetectionEnabled, isTrue);
      expect(settings.detection.autoStartEnabled, isTrue);
      expect(settings.detection.sensitivity, equals(CyclingSensitivity.medium));
      expect(settings.detection.minimumTripDurationSeconds, equals(120));
      expect(settings.detection.stationaryTimeoutSeconds, equals(300));

      // Battery defaults
      expect(settings.batteryMode, equals(BatteryOptimizationMode.balanced));

      // Location defaults
      expect(settings.locationAccuracy, equals(LocationAccuracyPreference.medium));
      expect(settings.distanceFilterMeters, equals(15));
      expect(settings.backgroundLocationEnabled, isTrue);

      // Notification defaults
      expect(settings.tripNotificationsEnabled, isTrue);
      expect(settings.showOngoingNotification, isTrue);
      expect(settings.soundOnTripStartStop, isFalse);

      // Privacy defaults
      expect(settings.dataCollectionConsent, isFalse);
      expect(settings.anonymousUsageStats, isFalse);

      // Display defaults
      expect(settings.distanceUnit, equals(DistanceUnit.metric));
      expect(settings.speedUnit, equals(SpeedUnit.kmh));
      expect(settings.themeMode, equals(ThemeMode.system));

      // Developer defaults
      expect(settings.debugLoggingEnabled, isFalse);
      expect(settings.showSensorOverlay, isFalse);

      // Metadata
      expect(settings.version, equals(1));
      expect(settings.lastModified, isNull);
    });

    test('should serialize to JSON', () {
      const settings = UserSettings(
        backgroundLocationEnabled: false,
        distanceFilterMeters: 20,
        distanceUnit: DistanceUnit.imperial,
        speedUnit: SpeedUnit.mph,
      );

      final json = settings.toJson();

      expect(json['backgroundLocationEnabled'], isFalse);
      expect(json['distanceFilterMeters'], equals(20));
      expect(json['distanceUnit'], equals('imperial'));
      expect(json['speedUnit'], equals('mph'));
    });

    test('should deserialize from JSON', () {
      final json = {
        'detection': {
          'autoStartEnabled': false,
          'sensitivity': 'high',
          'minimumTripDurationSeconds': 180,
          'stationaryTimeoutSeconds': 400,
        },
        'batteryMode': 'performance',
        'locationAccuracy': 'high',
        'distanceFilterMeters': 30,
        'backgroundLocationEnabled': true,
        'tripNotificationsEnabled': false,
        'showOngoingNotification': false,
        'soundOnTripStartStop': true,
        'dataCollectionConsent': true,
        'anonymousUsageStats': true,
        'distanceUnit': 'imperial',
        'speedUnit': 'mph',
        'themeMode': 'dark',
        'debugLoggingEnabled': true,
        'showSensorOverlay': true,
        'version': 1,
      };

      final settings = UserSettings.fromJson(json);

      expect(settings.detection.autoStartEnabled, isFalse);
      expect(settings.detection.sensitivity, equals(CyclingSensitivity.high));
      expect(settings.batteryMode, equals(BatteryOptimizationMode.performance));
      expect(settings.locationAccuracy, equals(LocationAccuracyPreference.high));
      expect(settings.distanceUnit, equals(DistanceUnit.imperial));
      expect(settings.speedUnit, equals(SpeedUnit.mph));
      expect(settings.themeMode, equals(ThemeMode.dark));
    });

    test('should convert distance correctly for metric', () {
      const metricSettings = UserSettings(distanceUnit: DistanceUnit.metric);

      // 1000 meters = 1 km
      expect(metricSettings.convertDistance(1000), closeTo(1.0, 0.01));

      // 5000 meters = 5 km
      expect(metricSettings.convertDistance(5000), closeTo(5.0, 0.01));

      // 500 meters = 0.5 km
      expect(metricSettings.convertDistance(500), closeTo(0.5, 0.01));
    });

    test('should convert distance correctly for imperial', () {
      const imperialSettings = UserSettings(distanceUnit: DistanceUnit.imperial);

      // 1000 meters ≈ 0.621 miles
      expect(imperialSettings.convertDistance(1000), closeTo(0.621, 0.01));

      // 1609.34 meters ≈ 1 mile
      expect(imperialSettings.convertDistance(1609.34), closeTo(1.0, 0.01));

      // 5000 meters ≈ 3.107 miles
      expect(imperialSettings.convertDistance(5000), closeTo(3.107, 0.01));
    });

    test('should convert speed correctly for km/h', () {
      const kmhSettings = UserSettings(speedUnit: SpeedUnit.kmh);

      // 10 m/s = 36 km/h
      expect(kmhSettings.convertSpeed(10), closeTo(36.0, 0.1));

      // 5 m/s = 18 km/h
      expect(kmhSettings.convertSpeed(5), closeTo(18.0, 0.1));

      // 0 m/s = 0 km/h
      expect(kmhSettings.convertSpeed(0), closeTo(0.0, 0.1));
    });

    test('should convert speed correctly for mph', () {
      const mphSettings = UserSettings(speedUnit: SpeedUnit.mph);

      // 10 m/s ≈ 22.37 mph
      expect(mphSettings.convertSpeed(10), closeTo(22.37, 0.1));

      // 5 m/s ≈ 11.18 mph
      expect(mphSettings.convertSpeed(5), closeTo(11.18, 0.1));

      // 0 m/s = 0 mph
      expect(mphSettings.convertSpeed(0), closeTo(0.0, 0.1));
    });

    test('should convert speed correctly for m/s', () {
      const msSettings = UserSettings(speedUnit: SpeedUnit.ms);

      // 10 m/s = 10 m/s
      expect(msSettings.convertSpeed(10), closeTo(10.0, 0.1));

      // 5 m/s = 5 m/s
      expect(msSettings.convertSpeed(5), closeTo(5.0, 0.1));
    });

    test('should provide correct distance unit labels', () {
      const metricSettings = UserSettings(distanceUnit: DistanceUnit.metric);
      const imperialSettings = UserSettings(distanceUnit: DistanceUnit.imperial);

      expect(metricSettings.distanceUnitLabel, equals('km'));
      expect(imperialSettings.distanceUnitLabel, equals('mi'));
    });

    test('should provide correct speed unit labels', () {
      const kmhSettings = UserSettings(speedUnit: SpeedUnit.kmh);
      const mphSettings = UserSettings(speedUnit: SpeedUnit.mph);
      const msSettings = UserSettings(speedUnit: SpeedUnit.ms);

      expect(kmhSettings.speedUnitLabel, equals('km/h'));
      expect(mphSettings.speedUnitLabel, equals('mph'));
      expect(msSettings.speedUnitLabel, equals('m/s'));
    });

    test('should map location accuracy preference to geolocator accuracy', () {
      const lowSettings = UserSettings(
        locationAccuracy: LocationAccuracyPreference.low,
      );
      const mediumSettings = UserSettings(
        locationAccuracy: LocationAccuracyPreference.medium,
      );
      const highSettings = UserSettings(
        locationAccuracy: LocationAccuracyPreference.high,
      );

      expect(lowSettings.geolocatorAccuracy, equals(LocationAccuracy.low));
      expect(mediumSettings.geolocatorAccuracy, equals(LocationAccuracy.medium));
      expect(highSettings.geolocatorAccuracy, equals(LocationAccuracy.high));
    });

    test('should use copyWith correctly', () {
      const original = UserSettings(
        distanceFilterMeters: 15,
        backgroundLocationEnabled: true,
      );

      final updated = original.copyWith(
        distanceFilterMeters: 25,
        backgroundLocationEnabled: false,
      );

      expect(updated.distanceFilterMeters, equals(25));
      expect(updated.backgroundLocationEnabled, isFalse);

      // Other fields should remain unchanged
      expect(updated.batteryMode, equals(original.batteryMode));
      expect(updated.distanceUnit, equals(original.distanceUnit));
    });
  });

  group('DetectionSettings', () {
    test('should create default detection settings', () {
      const settings = DetectionSettings();

      expect(settings.autoStartEnabled, isTrue);
      expect(settings.sensitivity, equals(CyclingSensitivity.medium));
      expect(settings.minimumTripDurationSeconds, equals(120));
      expect(settings.stationaryTimeoutSeconds, equals(300));
    });

    test('should provide correct sensitivity multipliers', () {
      const lowSettings = DetectionSettings(sensitivity: CyclingSensitivity.low);
      const mediumSettings = DetectionSettings(sensitivity: CyclingSensitivity.medium);
      const highSettings = DetectionSettings(sensitivity: CyclingSensitivity.high);

      // Low: 0.8 (more lenient, easier to trigger)
      expect(lowSettings.sensitivityMultiplier, closeTo(0.8, 0.01));

      // Medium: 1.0 (standard)
      expect(mediumSettings.sensitivityMultiplier, closeTo(1.0, 0.01));

      // High: 1.2 (stricter, harder to trigger)
      expect(highSettings.sensitivityMultiplier, closeTo(1.2, 0.01));
    });

    test('should convert seconds to Duration objects', () {
      const settings = DetectionSettings(
        minimumTripDurationSeconds: 120,
        stationaryTimeoutSeconds: 300,
      );

      expect(settings.minimumTripDuration, equals(const Duration(seconds: 120)));
      expect(settings.stationaryTimeout, equals(const Duration(seconds: 300)));
    });

    test('should serialize and deserialize correctly', () {
      const original = DetectionSettings(
        autoStartEnabled: false,
        sensitivity: CyclingSensitivity.high,
        minimumTripDurationSeconds: 180,
        stationaryTimeoutSeconds: 400,
      );

      final json = original.toJson();
      final deserialized = DetectionSettings.fromJson(json);

      expect(deserialized.autoStartEnabled, equals(original.autoStartEnabled));
      expect(deserialized.sensitivity, equals(original.sensitivity));
      expect(deserialized.minimumTripDurationSeconds, equals(original.minimumTripDurationSeconds));
      expect(deserialized.stationaryTimeoutSeconds, equals(original.stationaryTimeoutSeconds));
    });
  });
}
