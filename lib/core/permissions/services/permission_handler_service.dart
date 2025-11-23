import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:geolocator/geolocator.dart' hide
    PermissionDeniedException,
    PermissionRequestInProgressException,
    LocationServiceDisabledException;
import '../models/permission_status.dart';
import '../exceptions/permission_exceptions.dart';
import '../../platform/models/platform_info.dart';
import '../../platform/services/platform_info_service.dart';

part 'permission_handler_service.g.dart';

/// Permission handler service
///
/// Manages all runtime permissions with proper error handling,
/// progressive permission flow, and duplicate request prevention.
@riverpod
class PermissionHandlerService extends _$PermissionHandlerService {
  final Set<AppPermission> _requestsInProgress = {};

  @override
  Future<void> build() async {
    // Initialize service
    // Could check all permissions here if needed
  }

  /// Map AppPermission to permission_handler Permission
  ph.Permission _toPermissionHandler(AppPermission permission) {
    return switch (permission) {
      AppPermission.locationWhenInUse => ph.Permission.locationWhenInUse,
      AppPermission.locationAlways => ph.Permission.locationAlways,
      AppPermission.notification => ph.Permission.notification,
      AppPermission.activityRecognition => ph.Permission.activityRecognition,
    };
  }

  /// Check if location service is enabled
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Check permission status
  Future<AppPermissionStatus> checkPermission(AppPermission permission) async {
    final phPermission = _toPermissionHandler(permission);
    final status = await phPermission.status;

    return AppPermissionStatus.fromPermissionHandlerStatus(
      permission,
      status,
    );
  }

  /// Request permission with validation and error handling
  ///
  /// Throws:
  /// - [PermissionRequestInProgressException] if request already in progress
  /// - [LocationServiceDisabledException] if location service is disabled
  /// - [PermissionDeniedException] if user denies foreground permission
  /// - [PermissionPermanentlyDeniedException] if permanently denied
  Future<AppPermissionStatus> requestPermission(
    AppPermission permission, {
    bool throwOnDenied = false,
  }) async {
    // Prevent duplicate requests
    if (_requestsInProgress.contains(permission)) {
      throw PermissionRequestInProgressException(permission);
    }

    _requestsInProgress.add(permission);

    try {
      // Special handling for location permissions
      if (permission == AppPermission.locationWhenInUse ||
          permission == AppPermission.locationAlways) {
        // Check if location service is enabled first
        final serviceEnabled = await isLocationServiceEnabled();
        if (!serviceEnabled) {
          throw const LocationServiceDisabledException();
        }
      }

      // Special handling for background location (Android 10+)
      if (permission == AppPermission.locationAlways) {
        // Must have foreground permission first
        final foregroundStatus = await checkPermission(
          AppPermission.locationWhenInUse,
        );
        if (!foregroundStatus.isGranted) {
          throw const PermissionDeniedException(
            AppPermission.locationWhenInUse,
          );
        }

        // Android 11+ requires user to manually enable in settings
        // We can't request it directly via permission dialog
        final platformInfo = await ref.read(platformInfoServiceProvider.future);
        if (platformInfo.isAndroid11Plus) {
          // Check current status - if not granted, user must go to settings
          final currentStatus = await checkPermission(permission);
          if (!currentStatus.isGranted) {
            // Open settings and let user manually enable
            await openAppSettings();
            // Return current status (user will need to check again after returning)
            return currentStatus;
          }
        }
      }

      // Android 13+ requires notification permission before showing notifications
      if (permission == AppPermission.notification) {
        final platformInfo = await ref.read(platformInfoServiceProvider.future);
        if (!platformInfo.isAndroid13Plus) {
          // Notification permission not required on Android <13
          // Return granted status without requesting
          return const AppPermissionStatus(
            permission: AppPermission.notification,
            isGranted: true,
            isDenied: false,
            isPermanentlyDenied: false,
            isRestricted: false,
            isLimited: false,
          );
        }
      }

      // Request the permission
      final phPermission = _toPermissionHandler(permission);
      final status = await phPermission.request();

      final result = AppPermissionStatus.fromPermissionHandlerStatus(
        permission,
        status,
      );

      // Throw exceptions for denied states if requested
      if (result.isPermanentlyDenied) {
        throw PermissionPermanentlyDeniedException(permission);
      }

      if (throwOnDenied && result.isDenied) {
        throw PermissionDeniedException(permission);
      }

      return result;
    } finally {
      _requestsInProgress.remove(permission);
    }
  }

  /// Request multiple permissions at once
  ///
  /// Returns a map of permission status for each requested permission.
  /// Continues requesting all permissions even if some fail.
  Future<Map<AppPermission, AppPermissionStatus>> requestPermissions(
    List<AppPermission> permissions,
  ) async {
    final results = <AppPermission, AppPermissionStatus>{};

    for (final permission in permissions) {
      try {
        final status = await requestPermission(permission);
        results[permission] = status;
      } catch (e) {
        // Continue requesting other permissions even if one fails
        final status = await checkPermission(permission);
        results[permission] = status;
      }
    }

    return results;
  }

  /// Open app settings
  ///
  /// Returns true if settings were opened successfully
  Future<bool> openAppSettings() async {
    return await ph.openAppSettings();
  }

  /// Check if permission is granted
  Future<bool> isGranted(AppPermission permission) async {
    final status = await checkPermission(permission);
    return status.isGranted;
  }

  /// Check if permission should show rationale
  ///
  /// Returns true if permission is denied but not permanently,
  /// indicating we should show rationale before requesting again.
  Future<bool> shouldShowRationale(AppPermission permission) async {
    final phPermission = _toPermissionHandler(permission);
    final status = await phPermission.status;
    return status.isDenied && !status.isPermanentlyDenied;
  }

  /// Check if background location is granted
  ///
  /// Convenience method for checking the most commonly needed permission
  Future<bool> hasBackgroundLocation() async {
    return await isGranted(AppPermission.locationAlways);
  }

  /// Check if foreground location is granted
  ///
  /// Convenience method for checking the most commonly needed permission
  Future<bool> hasForegroundLocation() async {
    return await isGranted(AppPermission.locationWhenInUse);
  }
}
