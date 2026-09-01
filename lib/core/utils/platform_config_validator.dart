import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Validates platform configuration at app startup.
///
/// Every check below reads REAL runtime state (permission statuses, whether the
/// OS location service is on). Nothing here prints a hardcoded claim: a check
/// that would report success no matter what the manifest or the device says is
/// worse than no check, because it hides the problem it appears to cover.
class PlatformConfigValidator {
  /// Validate all platform configurations
  static Future<List<ConfigValidationIssue>> validateAll() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const [];
    }

    final issues = <ConfigValidationIssue>[];

    // OS-level location switch. Nothing in the app can produce a fix while
    // this is off, whatever the permissions say.
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      issues.add(
        const ConfigValidationIssue(
          severity: ConfigIssueSeverity.warning,
          message: 'Device location services are disabled',
          suggestion: 'Enable location in the OS settings before tracking.',
        ),
      );
    }

    issues.addAll(
      await _checkPermission(
        Permission.locationWhenInUse,
        label: 'Foreground location',
        severityWhenMissing: ConfigIssueSeverity.warning,
      ),
    );

    issues.addAll(
      await _checkPermission(
        Permission.locationAlways,
        label: 'Background location',
        severityWhenMissing: ConfigIssueSeverity.info,
      ),
    );

    // POST_NOTIFICATIONS (Android 13+) / iOS notification authorization. The
    // foreground service and every trip alert depend on it.
    issues.addAll(
      await _checkPermission(
        Permission.notification,
        label: 'Notifications',
        severityWhenMissing: ConfigIssueSeverity.warning,
      ),
    );

    return issues;
  }

  /// Report the real status of one permission.
  ///
  /// A permission that is missing from the platform manifest resolves as
  /// permanently denied without a dialog, so that case is reported as an error
  /// rather than as a user choice.
  static Future<List<ConfigValidationIssue>> _checkPermission(
    Permission permission, {
    required String label,
    required ConfigIssueSeverity severityWhenMissing,
  }) async {
    final status = await permission.status;

    if (kDebugMode) {
      debugPrint('  - $label: ${status.name}');
    }

    if (status.isGranted || status.isLimited) {
      return const [];
    }

    if (status.isPermanentlyDenied || status.isRestricted) {
      return [
        ConfigValidationIssue(
          severity: ConfigIssueSeverity.error,
          message: '$label is permanently denied or restricted',
          suggestion:
              'Check that the permission is declared for this platform and '
              're-grant it from the app settings.',
        ),
      ];
    }

    return [
      ConfigValidationIssue(
        severity: severityWhenMissing,
        message: '$label not granted (${status.name})',
        suggestion: 'Request it from the onboarding flow before it is needed.',
      ),
    ];
  }

  /// Print configuration status to console (development only)
  static Future<void> printConfigStatus() async {
    if (!kDebugMode) return;

    debugPrint('');
    debugPrint('='.padRight(50, '='));
    debugPrint('Platform Configuration Status');
    debugPrint('='.padRight(50, '='));

    final issues = await validateAll();

    if (issues.isEmpty) {
      debugPrint('✅ All configuration checks passed');
    } else {
      debugPrint('⚠️  Configuration issues found:');
      for (final issue in issues) {
        debugPrint('  - ${issue.severity.name}: ${issue.message}');
        final suggestion = issue.suggestion;
        if (suggestion != null) {
          debugPrint('      → $suggestion');
        }
      }
    }

    debugPrint('='.padRight(50, '='));
    debugPrint('');
  }
}

/// Configuration validation issue
class ConfigValidationIssue {
  const ConfigValidationIssue({
    required this.severity,
    required this.message,
    this.suggestion,
  });

  final ConfigIssueSeverity severity;
  final String message;
  final String? suggestion;
}

enum ConfigIssueSeverity { error, warning, info }
