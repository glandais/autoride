import 'package:flutter_test/flutter_test.dart';
import 'package:autoride/core/platform/models/platform_info.dart';

void main() {
  group('PlatformInfo', () {
    test('androidApiAtLeast returns true for equal or higher API', () {
      const info = PlatformInfo(
        type: PlatformType.android,
        version: '11',
        apiLevel: 30,
        isPhysicalDevice: true,
      );

      expect(info.androidApiAtLeast(29), true);
      expect(info.androidApiAtLeast(30), true);
      expect(info.androidApiAtLeast(31), false);
    });

    test('androidApiAtLeast returns false for non-Android platforms', () {
      const info = PlatformInfo(
        type: PlatformType.ios,
        version: '14.0',
        apiLevel: 0,
        isPhysicalDevice: true,
      );

      expect(info.androidApiAtLeast(29), false);
    });

    test('isAndroid10Plus correctly identifies API 29+', () {
      const api29 = PlatformInfo(
        type: PlatformType.android,
        version: '10',
        apiLevel: 29,
        isPhysicalDevice: true,
      );

      const api28 = PlatformInfo(
        type: PlatformType.android,
        version: '9',
        apiLevel: 28,
        isPhysicalDevice: true,
      );

      expect(api29.isAndroid10Plus, true);
      expect(api28.isAndroid10Plus, false);
    });

    test('isAndroid11Plus correctly identifies API 30+', () {
      const api30 = PlatformInfo(
        type: PlatformType.android,
        version: '11',
        apiLevel: 30,
        isPhysicalDevice: true,
      );

      const api29 = PlatformInfo(
        type: PlatformType.android,
        version: '10',
        apiLevel: 29,
        isPhysicalDevice: true,
      );

      expect(api30.isAndroid11Plus, true);
      expect(api29.isAndroid11Plus, false);
    });

    test('isAndroid12Plus correctly identifies API 31+', () {
      const api31 = PlatformInfo(
        type: PlatformType.android,
        version: '12',
        apiLevel: 31,
        isPhysicalDevice: true,
      );

      const api30 = PlatformInfo(
        type: PlatformType.android,
        version: '11',
        apiLevel: 30,
        isPhysicalDevice: true,
      );

      expect(api31.isAndroid12Plus, true);
      expect(api30.isAndroid12Plus, false);
    });

    test('isAndroid13Plus correctly identifies API 33+', () {
      const api33 = PlatformInfo(
        type: PlatformType.android,
        version: '13',
        apiLevel: 33,
        isPhysicalDevice: true,
      );

      const api32 = PlatformInfo(
        type: PlatformType.android,
        version: '12L',
        apiLevel: 32,
        isPhysicalDevice: true,
      );

      expect(api33.isAndroid13Plus, true);
      expect(api32.isAndroid13Plus, false);
    });

    test('iosVersionAtLeast correctly compares major versions', () {
      const ios14 = PlatformInfo(
        type: PlatformType.ios,
        version: '14.5',
        apiLevel: 0,
        isPhysicalDevice: true,
      );

      expect(ios14.iosVersionAtLeast(13), true);
      expect(ios14.iosVersionAtLeast(14), true);
      expect(ios14.iosVersionAtLeast(15), false);
    });

    test('iosVersionAtLeast correctly compares minor versions', () {
      const ios14_5 = PlatformInfo(
        type: PlatformType.ios,
        version: '14.5',
        apiLevel: 0,
        isPhysicalDevice: true,
      );

      expect(ios14_5.iosVersionAtLeast(14, 4), true);
      expect(ios14_5.iosVersionAtLeast(14, 5), true);
      expect(ios14_5.iosVersionAtLeast(14, 6), false);
    });

    test('iosVersionAtLeast handles version without minor', () {
      const ios14 = PlatformInfo(
        type: PlatformType.ios,
        version: '14',
        apiLevel: 0,
        isPhysicalDevice: true,
      );

      expect(ios14.iosVersionAtLeast(14), true);
      expect(ios14.iosVersionAtLeast(14, 1), false);
    });

    test('iosVersionAtLeast returns false for non-iOS platforms', () {
      const info = PlatformInfo(
        type: PlatformType.android,
        version: '11',
        apiLevel: 30,
        isPhysicalDevice: true,
      );

      expect(info.iosVersionAtLeast(14), false);
    });

    test('isIos14Plus correctly identifies iOS 14+', () {
      const ios14 = PlatformInfo(
        type: PlatformType.ios,
        version: '14.0',
        apiLevel: 0,
        isPhysicalDevice: true,
      );

      const ios13 = PlatformInfo(
        type: PlatformType.ios,
        version: '13.7',
        apiLevel: 0,
        isPhysicalDevice: true,
      );

      expect(ios14.isIos14Plus, true);
      expect(ios13.isIos14Plus, false);
    });

    test('isIos17Plus correctly identifies iOS 17+', () {
      const ios17 = PlatformInfo(
        type: PlatformType.ios,
        version: '17.0',
        apiLevel: 0,
        isPhysicalDevice: true,
      );

      const ios16 = PlatformInfo(
        type: PlatformType.ios,
        version: '16.6',
        apiLevel: 0,
        isPhysicalDevice: true,
      );

      expect(ios17.isIos17Plus, true);
      expect(ios16.isIos17Plus, false);
    });

    test('isPhysicalDevice correctly identifies emulator', () {
      const emulator = PlatformInfo(
        type: PlatformType.android,
        version: '11',
        apiLevel: 30,
        isPhysicalDevice: false,
      );

      const device = PlatformInfo(
        type: PlatformType.android,
        version: '11',
        apiLevel: 30,
        isPhysicalDevice: true,
      );

      expect(emulator.isPhysicalDevice, false);
      expect(device.isPhysicalDevice, true);
    });
  });
}
