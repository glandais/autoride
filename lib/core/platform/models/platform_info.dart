import 'package:freezed_annotation/freezed_annotation.dart';

part 'platform_info.freezed.dart';

/// Platform information for runtime adaptation
@freezed
sealed class PlatformInfo with _$PlatformInfo {
  const PlatformInfo._();

  const factory PlatformInfo({
    required PlatformType type,
    required String version,
    required int apiLevel, // Android only
    required bool isPhysicalDevice,
  }) = _PlatformInfo;
}

extension PlatformInfoExtensions on PlatformInfo {
  /// Check if Android API level meets minimum requirement
  bool androidApiAtLeast(int minimumApiLevel) {
    return type == PlatformType.android && apiLevel >= minimumApiLevel;
  }

  /// Check if iOS version meets minimum requirement
  bool iosVersionAtLeast(int major, [int minor = 0]) {
    if (type != PlatformType.ios) return false;

    final parts = version.split('.');
    final currentMajor = int.tryParse(parts[0]) ?? 0;
    final currentMinor = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    if (currentMajor > major) return true;
    if (currentMajor == major && currentMinor >= minor) return true;
    return false;
  }

  /// Check if running on Android 10+ (scoped storage, background location changes)
  bool get isAndroid10Plus => androidApiAtLeast(29);

  /// Check if running on Android 11+ (background location requires settings)
  bool get isAndroid11Plus => androidApiAtLeast(30);

  /// Check if running on Android 12+ (precise vs approximate location)
  bool get isAndroid12Plus => androidApiAtLeast(31);

  /// Check if running on Android 13+ (notification permission required)
  bool get isAndroid13Plus => androidApiAtLeast(33);

  /// Check if running on iOS 14+ (Allow Once, approximate location)
  bool get isIos14Plus => iosVersionAtLeast(14);

  /// Check if running on iOS 17+ (privacy manifest required)
  bool get isIos17Plus => iosVersionAtLeast(17);
}

enum PlatformType {
  android,
  ios,
  web,
  other,
}
