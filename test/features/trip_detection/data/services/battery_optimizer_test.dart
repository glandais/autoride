import 'package:flutter_test/flutter_test.dart';
import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/features/trip_detection/data/services/battery_optimizer.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  group('PowerModeConfig', () {
    test('normal config should have highest performance', () {
      const config = PowerModeConfig.normal;

      expect(config.sensorSamplingRate, equals(50));
      expect(config.distanceFilter, equals(15));
      expect(
        config.locationUpdateInterval,
        equals(const Duration(seconds: 30)),
      );
      expect(config.locationAccuracy, equals(LocationAccuracy.medium));
    });

    test('critical config should have lowest power consumption', () {
      const config = PowerModeConfig.critical;

      expect(config.sensorSamplingRate, equals(20));
      expect(config.distanceFilter, equals(50));
      expect(
        config.locationUpdateInterval,
        equals(const Duration(seconds: 90)),
      );
      expect(config.locationAccuracy, equals(LocationAccuracy.low));
    });

    test('configs should be comparable', () {
      const config1 = PowerModeConfig.normal;
      const config2 = PowerModeConfig.normal;
      const config3 = PowerModeConfig.low;

      expect(config1, equals(config2));
      expect(config1, isNot(equals(config3)));
    });
  });

  group('BatteryLevel', () {
    test('should have all battery level categories', () {
      expect(BatteryLevel.values.length, equals(4));
      expect(BatteryLevel.values, contains(BatteryLevel.critical));
      expect(BatteryLevel.values, contains(BatteryLevel.low));
      expect(BatteryLevel.values, contains(BatteryLevel.medium));
      expect(BatteryLevel.values, contains(BatteryLevel.normal));
    });
  });

  // The `bat` line's own de-duplication (L-086). Kept as a value object
  // precisely so it is testable without the platform channels below.
  group('BatteryAuditThrottle', () {
    final at = DateTime(2026, 9, 2, 17, 5);

    test('the first reading is always journalled', () {
      final throttle = BatteryAuditThrottle();

      expect(throttle.accept(level: 97, charging: false, at: at), isTrue);
    });

    test('a repeat in the same second is not', () {
      final throttle = BatteryAuditThrottle();
      throttle.accept(level: 97, charging: false, at: at);

      // What a session restart produced: the battery stream replays its
      // current state to the rebuilt notifier's fresh subscription.
      expect(
        throttle.accept(
          level: 97,
          charging: false,
          at: at.add(const Duration(milliseconds: 40)),
        ),
        isFalse,
      );
    });

    test('a level that moved is journalled immediately', () {
      final throttle = BatteryAuditThrottle();
      throttle.accept(level: 97, charging: false, at: at);

      expect(
        throttle.accept(
          level: 96,
          charging: false,
          at: at.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
    });

    test('plugging in is journalled immediately', () {
      final throttle = BatteryAuditThrottle();
      throttle.accept(level: 97, charging: false, at: at);

      expect(
        throttle.accept(
          level: 97,
          charging: true,
          at: at.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
    });

    test('an unchanged level is journalled again on the next tick', () {
      final throttle = BatteryAuditThrottle();
      throttle.accept(level: 97, charging: false, at: at);

      // A flat battery still has to leave proof that it was being read.
      expect(
        throttle.accept(
          level: 97,
          charging: false,
          at: at.add(
            const Duration(minutes: AppConstants.batteryCheckIntervalMinutes),
          ),
        ),
        isTrue,
      );
    });
  });

  // Note: BatteryOptimizer tests require mocking Battery class
  // which is complex due to platform channels
  // These tests would be integration tests run on actual devices
  // For now, we test the PowerModeConfig class which contains the core logic
}
