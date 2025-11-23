import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/extensions/async_value_extensions.dart';
import '../models/platform_info.dart';

part 'platform_info_service.g.dart';

@riverpod
class PlatformInfoService extends _$PlatformInfoService {
  @override
  Future<PlatformInfo> build() async {
    return await _getPlatformInfo();
  }

  Future<PlatformInfo> _getPlatformInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return PlatformInfo(
          type: PlatformType.android,
          version: androidInfo.version.release,
          apiLevel: androidInfo.version.sdkInt,
          isPhysicalDevice: androidInfo.isPhysicalDevice,
        );
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return PlatformInfo(
          type: PlatformType.ios,
          version: iosInfo.systemVersion,
          apiLevel: 0, // Not applicable for iOS
          isPhysicalDevice: iosInfo.isPhysicalDevice,
        );
      } else {
        return const PlatformInfo(
          type: PlatformType.other,
          version: 'unknown',
          apiLevel: 0,
          isPhysicalDevice: false,
        );
      }
    } catch (e) {
      // Return safe defaults on error
      return const PlatformInfo(
        type: PlatformType.other,
        version: 'unknown',
        apiLevel: 0,
        isPhysicalDevice: false,
      );
    }
  }

  /// Get user-friendly platform description
  String getPlatformDescription() {
    final info = state.dataOrNull;
    if (info == null) return 'Unknown';

    return switch (info.type) {
      PlatformType.android => 'Android ${info.version} (API ${info.apiLevel})',
      PlatformType.ios => 'iOS ${info.version}',
      _ => 'Unknown platform',
    };
  }

  /// Check if emulator/simulator (for testing warnings)
  bool isEmulator() {
    final info = state.dataOrNull;
    return info?.isPhysicalDevice == false;
  }
}
