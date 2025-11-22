import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:autoride/features/settings/data/repositories/settings_repository.dart';
import 'package:autoride/features/settings/domain/models/user_settings.dart';
import 'package:autoride/features/settings/domain/models/detection_settings.dart';

void main() {
  late SettingsRepository repository;

  setUp(() async {
    // Initialize mock SharedPreferences with empty data
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repository = SettingsRepository(prefs);
  });

  group('SettingsRepository', () {
    test('should return default settings when no data exists', () async {
      final settings = await repository.loadSettings();

      expect(settings, equals(const UserSettings()));
      expect(settings.batteryMode, equals(BatteryOptimizationMode.balanced));
      expect(settings.distanceUnit, equals(DistanceUnit.metric));
    });

    test('should save and load settings', () async {
      const testSettings = UserSettings(
        backgroundLocationEnabled: false,
        distanceFilterMeters: 25,
        distanceUnit: DistanceUnit.imperial,
        speedUnit: SpeedUnit.mph,
        batteryMode: BatteryOptimizationMode.performance,
      );

      await repository.saveSettings(testSettings);
      final loadedSettings = await repository.loadSettings();

      expect(loadedSettings.backgroundLocationEnabled, isFalse);
      expect(loadedSettings.distanceFilterMeters, equals(25));
      expect(loadedSettings.distanceUnit, equals(DistanceUnit.imperial));
      expect(loadedSettings.speedUnit, equals(SpeedUnit.mph));
      expect(loadedSettings.batteryMode, equals(BatteryOptimizationMode.performance));
    });

    test('should update lastModified timestamp when saving', () async {
      const settings = UserSettings(
        distanceFilterMeters: 20,
      );

      // First save
      await repository.saveSettings(settings);
      final firstLoad = await repository.loadSettings();
      expect(firstLoad.lastModified, isNotNull);

      final firstTimestamp = firstLoad.lastModified!;

      // Wait a bit to ensure timestamp changes
      await Future.delayed(const Duration(milliseconds: 10));

      // Second save
      await repository.saveSettings(firstLoad.copyWith(distanceFilterMeters: 30));
      final secondLoad = await repository.loadSettings();
      expect(secondLoad.lastModified, isNotNull);

      final secondTimestamp = secondLoad.lastModified!;

      // Second timestamp should be after first
      expect(secondTimestamp.isAfter(firstTimestamp), isTrue);
    });

    test('should save nested detection settings correctly', () async {
      const testSettings = UserSettings(
        detection: DetectionSettings(
          autoStartEnabled: false,
          sensitivity: CyclingSensitivity.high,
          minimumTripDurationSeconds: 180,
          stationaryTimeoutSeconds: 400,
        ),
      );

      await repository.saveSettings(testSettings);
      final loadedSettings = await repository.loadSettings();

      expect(loadedSettings.detection.autoStartEnabled, isFalse);
      expect(loadedSettings.detection.sensitivity, equals(CyclingSensitivity.high));
      expect(loadedSettings.detection.minimumTripDurationSeconds, equals(180));
      expect(loadedSettings.detection.stationaryTimeoutSeconds, equals(400));
    });

    test('should clear settings', () async {
      const settings = UserSettings(
        backgroundLocationEnabled: false,
        distanceFilterMeters: 25,
      );

      await repository.saveSettings(settings);

      // Verify settings were saved
      expect(repository.hasSettings(), isTrue);
      final loadedSettings = await repository.loadSettings();
      expect(loadedSettings.backgroundLocationEnabled, isFalse);

      // Clear settings
      await repository.clearSettings();

      // Verify settings were cleared
      expect(repository.hasSettings(), isFalse);
      final defaultSettings = await repository.loadSettings();
      expect(defaultSettings, equals(const UserSettings()));
    });

    test('should check if settings exist', () async {
      // Initially no settings
      expect(repository.hasSettings(), isFalse);

      // After saving, settings should exist
      await repository.saveSettings(const UserSettings());
      expect(repository.hasSettings(), isTrue);

      // After clearing, settings should not exist
      await repository.clearSettings();
      expect(repository.hasSettings(), isFalse);
    });

    test('should handle corrupted JSON data gracefully', () async {
      // Manually insert corrupted data into SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_settings', '{invalid json data}');

      // Should return default settings instead of throwing
      final settings = await repository.loadSettings();
      expect(settings, equals(const UserSettings()));
    });

    test('should preserve all settings fields during save/load cycle', () async {
      const testSettings = UserSettings(
        detection: DetectionSettings(
          autoStartEnabled: false,
          sensitivity: CyclingSensitivity.low,
          minimumTripDurationSeconds: 90,
          stationaryTimeoutSeconds: 200,
        ),
        batteryMode: BatteryOptimizationMode.aggressive,
        locationAccuracy: LocationAccuracyPreference.low,
        distanceFilterMeters: 30,
        backgroundLocationEnabled: false,
        tripNotificationsEnabled: false,
        showOngoingNotification: false,
        soundOnTripStartStop: true,
        dataCollectionConsent: true,
        anonymousUsageStats: true,
        distanceUnit: DistanceUnit.imperial,
        speedUnit: SpeedUnit.mph,
        themeMode: ThemeMode.dark,
        debugLoggingEnabled: true,
        showSensorOverlay: true,
      );

      await repository.saveSettings(testSettings);
      final loadedSettings = await repository.loadSettings();

      // Verify all fields (except lastModified and version)
      expect(loadedSettings.detection.autoStartEnabled, equals(testSettings.detection.autoStartEnabled));
      expect(loadedSettings.detection.sensitivity, equals(testSettings.detection.sensitivity));
      expect(loadedSettings.batteryMode, equals(testSettings.batteryMode));
      expect(loadedSettings.locationAccuracy, equals(testSettings.locationAccuracy));
      expect(loadedSettings.distanceFilterMeters, equals(testSettings.distanceFilterMeters));
      expect(loadedSettings.backgroundLocationEnabled, equals(testSettings.backgroundLocationEnabled));
      expect(loadedSettings.tripNotificationsEnabled, equals(testSettings.tripNotificationsEnabled));
      expect(loadedSettings.showOngoingNotification, equals(testSettings.showOngoingNotification));
      expect(loadedSettings.soundOnTripStartStop, equals(testSettings.soundOnTripStartStop));
      expect(loadedSettings.dataCollectionConsent, equals(testSettings.dataCollectionConsent));
      expect(loadedSettings.anonymousUsageStats, equals(testSettings.anonymousUsageStats));
      expect(loadedSettings.distanceUnit, equals(testSettings.distanceUnit));
      expect(loadedSettings.speedUnit, equals(testSettings.speedUnit));
      expect(loadedSettings.themeMode, equals(testSettings.themeMode));
      expect(loadedSettings.debugLoggingEnabled, equals(testSettings.debugLoggingEnabled));
      expect(loadedSettings.showSensorOverlay, equals(testSettings.showSensorOverlay));
    });

    test('should handle multiple save/load cycles', () async {
      // First cycle
      const settings1 = UserSettings(distanceFilterMeters: 10);
      await repository.saveSettings(settings1);
      final loaded1 = await repository.loadSettings();
      expect(loaded1.distanceFilterMeters, equals(10));

      // Second cycle
      final settings2 = loaded1.copyWith(distanceFilterMeters: 20);
      await repository.saveSettings(settings2);
      final loaded2 = await repository.loadSettings();
      expect(loaded2.distanceFilterMeters, equals(20));

      // Third cycle
      final settings3 = loaded2.copyWith(distanceFilterMeters: 30);
      await repository.saveSettings(settings3);
      final loaded3 = await repository.loadSettings();
      expect(loaded3.distanceFilterMeters, equals(30));
    });
  });
}
