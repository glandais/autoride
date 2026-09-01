import 'package:flutter/material.dart';

import '../exceptions/permission_exceptions.dart';

/// Permission rationale data
///
/// Contains information to display to users explaining why a permission
/// is needed before requesting it.
class PermissionRationale {
  const PermissionRationale({
    required this.permission,
    required this.title,
    required this.description,
    required this.icon,
    required this.benefits,
    this.privacyNote,
    this.isOptional = false,
  });

  final AppPermission permission;
  final String title;
  final String description;
  final IconData icon;
  final List<String> benefits;
  final String? privacyNote;
  final bool isOptional;

  /// Location when in use permission rationale
  static const locationWhenInUse = PermissionRationale(
    permission: AppPermission.locationWhenInUse,
    title: 'Location Permission',
    description: 'AutoRide needs location access to track your cycling routes.',
    icon: Icons.location_on,
    benefits: [
      'Record your cycling routes on a map',
      'Calculate distance, speed, and duration',
      'Mark trip start and end locations',
    ],
    privacyNote:
        'Your location data stays on your device. We never share or upload it.',
  );

  /// Background location permission rationale
  static const locationAlways = PermissionRationale(
    permission: AppPermission.locationAlways,
    title: 'Background Location',
    description: 'Enable automatic trip detection even when the app is closed.',
    icon: Icons.auto_awesome,
    benefits: [
      'Completely automatic - no need to start/stop manually',
      'Battery optimized - only uses GPS when cycling',
      'Never miss a trip - records every ride',
    ],
    privacyNote: 'Background location is only used for trip detection.',
    isOptional: true,
  );

  /// Notification permission rationale
  static const notification = PermissionRationale(
    permission: AppPermission.notification,
    title: 'Notification Permission',
    description: 'Stay informed about your active trips.',
    icon: Icons.notifications_active,
    benefits: [
      'See trip progress in notification',
      'Control tracking from notification',
      'Battery status updates',
    ],
  );

  /// Activity recognition permission rationale
  static const activityRecognition = PermissionRationale(
    permission: AppPermission.activityRecognition,
    title: 'Activity Recognition',
    description: 'Improve trip detection accuracy with activity recognition.',
    icon: Icons.directions_bike,
    benefits: [
      'Better cycling detection accuracy',
      'Distinguish cycling from other activities',
      'Reduce false trip detections',
    ],
    isOptional: true,
  );

  /// Get rationale for a specific permission
  static PermissionRationale forPermission(AppPermission permission) {
    return switch (permission) {
      AppPermission.locationWhenInUse => locationWhenInUse,
      AppPermission.locationAlways => locationAlways,
      AppPermission.notification => notification,
      AppPermission.activityRecognition => activityRecognition,
    };
  }
}
