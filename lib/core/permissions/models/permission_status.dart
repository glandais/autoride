import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import '../exceptions/permission_exceptions.dart';

part 'permission_status.freezed.dart';

/// App permission status model
///
/// Wraps permission_handler status with type-safe app permission enum
@freezed
sealed class AppPermissionStatus with _$AppPermissionStatus {
  const AppPermissionStatus._();

  const factory AppPermissionStatus({
    required AppPermission permission,
    required bool isGranted,
    required bool isDenied,
    required bool isPermanentlyDenied,
    required bool isRestricted,
    required bool isLimited,
  }) = _AppPermissionStatus;

  /// Create from permission_handler status
  factory AppPermissionStatus.fromPermissionHandlerStatus(
    AppPermission permission,
    ph.PermissionStatus status,
  ) {
    return AppPermissionStatus(
      permission: permission,
      isGranted: status.isGranted,
      isDenied: status.isDenied,
      isPermanentlyDenied: status.isPermanentlyDenied,
      isRestricted: status.isRestricted,
      isLimited: status.isLimited,
    );
  }
}

/// Extension for convenience methods
extension AppPermissionStatusExtensions on AppPermissionStatus {
  /// Can request permission (not permanently denied or restricted)
  bool get canRequest => !isPermanentlyDenied && !isRestricted;

  /// Needs to open settings (permanently denied)
  bool get needsSettings => isPermanentlyDenied;

  /// Should show rationale (denied but not permanently)
  bool get shouldShowRationale => isDenied && !isPermanentlyDenied;
}
