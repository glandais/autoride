import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/user_settings.dart';
import '../../data/services/settings_service.dart';
import 'setting_section.dart';
import 'setting_tile.dart';
import 'setting_slider.dart';
import 'setting_radio_group.dart';
import '../../../../core/permissions/widgets/permission_rationale_dialog.dart';
import '../../../../core/permissions/models/permission_rationale.dart';
import '../../../../core/permissions/exceptions/permission_exceptions.dart';
import '../../../../core/permissions/models/background_location_state.dart';
import '../../../../core/permissions/providers/background_location_status.dart';
import '../../../../core/permissions/services/permission_handler_service.dart';
import '../../../../core/platform/models/platform_info.dart';
import '../../../../core/platform/services/platform_info_service.dart';

/// Location settings section for GPS configuration
class LocationSettingsSection extends ConsumerWidget {
  const LocationSettingsSection({required this.settings, super.key});

  final UserSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The real OS permission, not the stored preference: the preference can
    // say "on" while the OS only granted "While Using" (iOS) or never got
    // "Allow all the time" (Android 11+).
    final backgroundStatus = ref.watch(backgroundLocationStatusProvider);
    final platform = ref.watch(platformInfoServiceProvider).value;
    final backgroundGranted = backgroundStatus.value?.isReady ?? false;
    final issue = backgroundStatus.value?.issue;

    return SettingSection(
      title: 'Location',
      subtitle: 'Configure GPS accuracy and tracking behavior',
      children: [
        // Location accuracy selector
        SettingRadioGroup<LocationAccuracyPreference>(
          title: 'Location accuracy',
          value: settings.locationAccuracy,
          options: const [
            RadioOption(
              value: LocationAccuracyPreference.low,
              label: 'Low',
              description: '~100m accuracy, saves battery',
            ),
            RadioOption(
              value: LocationAccuracyPreference.medium,
              label: 'Medium',
              description: '~10m accuracy (recommended)',
            ),
            RadioOption(
              value: LocationAccuracyPreference.high,
              label: 'High',
              description: '<10m accuracy, uses more battery',
            ),
          ],
          onChanged: (value) {
            ref
                .read(settingsServiceProvider.notifier)
                .updatePartial((s) => s.copyWith(locationAccuracy: value));
          },
        ),

        const Divider(height: 1),

        // Distance filter slider
        SettingSlider(
          title: 'Distance filter',
          value: settings.distanceFilterMeters.toDouble(),
          min: 5,
          max: 50,
          unit: 'm',
          divisions: 9,
          onChanged: (value) {
            ref
                .read(settingsServiceProvider.notifier)
                .updatePartial(
                  (s) => s.copyWith(distanceFilterMeters: value.toInt()),
                );
          },
        ),

        const Divider(height: 1),

        // Background location toggle - mirrors the OS permission
        SettingTile(
          title: 'Background location',
          subtitle: _backgroundSubtitle(backgroundStatus, platform),
          trailing: Switch(
            value: backgroundGranted,
            // Greyed out until the OS has answered.
            onChanged: backgroundStatus.hasValue
                ? (value) async {
                    if (value) {
                      if (issue == BackgroundLocationIssue.preciseMissing) {
                        // "Always" is already granted: asking for it again
                        // shows no prompt and changes no accuracy. Only the
                        // Settings app can turn "Precise" back on.
                        await _fixReducedAccuracy(context, ref, platform);
                      } else {
                        await _requestBackgroundLocation(
                          context,
                          ref,
                          platform,
                        );
                      }
                    } else {
                      // The app cannot revoke an OS permission, so nothing is
                      // persisted here: only the system settings can turn it off.
                      _showRevokeInSettingsDialog(context, ref);
                    }
                  }
                : null,
          ),
        ),
      ],
    );
  }

  /// Whether the running platform is iOS (wording differs from Android).
  bool _isIos(PlatformInfo? platform) => platform?.type == PlatformType.ios;

  /// What the user has to change, in the platform's own words.
  String _issueLabel(BackgroundLocationIssue issue, PlatformInfo? platform) =>
      switch (issue) {
        BackgroundLocationIssue.alwaysMissing =>
          _isIos(platform)
              ? 'Location is not set to "Always"'
              : '"Allow all the time" is not enabled',
        BackgroundLocationIssue.preciseMissing =>
          _isIos(platform)
              ? '"Precise Location" is off'
              : 'Location is not set to "Precise"',
      };

  /// How to fix it, in the platform's own words.
  String _settingsInstructions(
    BackgroundLocationIssue issue,
    PlatformInfo? platform,
  ) => switch (issue) {
    BackgroundLocationIssue.alwaysMissing =>
      _isIos(platform)
          ? 'Set Location to "Always" for AutoRide in the Settings app.'
          : 'Choose "Allow all the time" for AutoRide\'s location in the '
                'Settings app.',
    BackgroundLocationIssue.preciseMissing =>
      _isIos(platform)
          ? 'Turn on "Precise Location" for AutoRide in the Settings app.'
          : 'Choose "Precise" location for AutoRide in the Settings app.',
  };

  String _backgroundSubtitle(
    AsyncValue<BackgroundLocationState> status,
    PlatformInfo? platform,
  ) {
    final state = status.value;
    if (state == null) return 'Track trips when app is in background';
    final issue = state.issue;
    if (issue == null) return 'Trips can start while the app is closed';
    return _issueLabel(issue, platform);
  }

  /// Ask for "Always" / "Allow all the time", then re-read what the OS says.
  Future<void> _requestBackgroundLocation(
    BuildContext context,
    WidgetRef ref,
    PlatformInfo? platform,
  ) async {
    // Show rationale dialog before requesting permission
    final shouldRequest = await PermissionRationaleDialog.show(
      context,
      PermissionRationale.locationAlways,
    );
    if (shouldRequest != true || !context.mounted) return;

    final service = ref.read(permissionHandlerServiceProvider.notifier);

    try {
      final status = await service.requestPermission(
        AppPermission.locationAlways,
      );

      if (status.isGranted && context.mounted) {
        ref
            .read(settingsServiceProvider.notifier)
            .updatePartial((s) => s.copyWith(backgroundLocationEnabled: true));
      }
    } on PermissionPermanentlyDeniedException {
      // Not necessarily a permanent refusal: iOS offers the "Always" upgrade
      // prompt only once per install, and Android 11+ never offers it at all.
      if (context.mounted) {
        _showOpenSettingsDialog(
          context,
          ref,
          platform,
          BackgroundLocationIssue.alwaysMissing,
        );
      }
    } on PermissionDeniedException {
      // User denied, don't update setting
    } on LocationServiceDisabledException {
      // Show enable location service dialog
      if (context.mounted) {
        _showEnableLocationDialog(context);
      }
    } finally {
      // Whatever happened, the status we hold is now stale.
      if (context.mounted) {
        ref.read(backgroundLocationStatusProvider.notifier).refresh();
      }
    }
  }

  /// The permission is granted but the fix is out of the app's reach: no
  /// prompt exists for turning "Precise" back on, only the Settings app.
  Future<void> _fixReducedAccuracy(
    BuildContext context,
    WidgetRef ref,
    PlatformInfo? platform,
  ) async {
    try {
      await _showOpenSettingsDialog(
        context,
        ref,
        platform,
        BackgroundLocationIssue.preciseMissing,
      );
    } finally {
      // Whatever happened, the status we hold is now stale.
      if (context.mounted) {
        ref.read(backgroundLocationStatusProvider.notifier).refresh();
      }
    }
  }

  /// Show dialog pointing the user at the system setting they must change.
  Future<void> _showOpenSettingsDialog(
    BuildContext context,
    WidgetRef ref,
    PlatformInfo? platform,
    BackgroundLocationIssue issue,
  ) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change in Settings'),
        content: Text(_settingsInstructions(issue, platform)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await ref
                  .read(permissionHandlerServiceProvider.notifier)
                  .openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Explain that only the system settings can take the permission back.
  void _showRevokeInSettingsDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke in Settings'),
        content: const Text(
          'AutoRide cannot turn background location off for you. Change '
          "AutoRide's location permission in the Settings app.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await ref
                  .read(permissionHandlerServiceProvider.notifier)
                  .openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Show dialog to enable location service
  void _showEnableLocationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Service Disabled'),
        content: const Text(
          'Please enable location services in your device settings to use background tracking.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
