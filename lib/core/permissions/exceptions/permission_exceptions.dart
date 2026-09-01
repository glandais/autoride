// Permission exception types
//
// These exceptions are thrown by permission-related services and handled
// by the error handler to provide user-friendly error messages.

/// Enum for app permissions
enum AppPermission {
  locationWhenInUse,
  locationAlways,
  notification,
  activityRecognition,
}

/// Extension for permission display names
extension AppPermissionExtension on AppPermission {
  String get displayName {
    return switch (this) {
      AppPermission.locationWhenInUse => 'Location (While Using)',
      AppPermission.locationAlways => 'Background Location',
      AppPermission.notification => 'Notifications',
      AppPermission.activityRecognition => 'Activity Recognition',
    };
  }
}

/// Base exception for permission-related errors
abstract class PermissionException implements Exception {
  const PermissionException(this.message, this.permission);

  final String message;
  final AppPermission permission;

  @override
  String toString() => '$message (${permission.displayName})';
}

/// Permission was denied by the user
class PermissionDeniedException extends PermissionException {
  const PermissionDeniedException(AppPermission permission)
    : super('Permission denied', permission);
}

/// Permission was permanently denied (requires settings)
class PermissionPermanentlyDeniedException extends PermissionException {
  const PermissionPermanentlyDeniedException(AppPermission permission)
    : super(
        'Permission permanently denied. Please enable in settings.',
        permission,
      );
}

/// Permission request already in progress
class PermissionRequestInProgressException extends PermissionException {
  const PermissionRequestInProgressException(AppPermission permission)
    : super('Permission request is already in progress', permission);
}

/// Location service is disabled
class LocationServiceDisabledException implements Exception {
  const LocationServiceDisabledException([
    this.message =
        'Location service is disabled. Please enable it in settings.',
  ]);

  final String message;

  @override
  String toString() => message;
}
