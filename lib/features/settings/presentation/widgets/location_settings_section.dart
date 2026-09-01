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
import '../../../../core/permissions/services/permission_handler_service.dart';

/// Location settings section for GPS configuration
class LocationSettingsSection extends ConsumerWidget {
  const LocationSettingsSection({required this.settings, super.key});

  final UserSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

        // Background location toggle
        SettingTile(
          title: 'Background location',
          subtitle: 'Track trips when app is in background',
          trailing: Switch(
            value: settings.backgroundLocationEnabled,
            onChanged: (value) async {
              if (value) {
                // Show rationale dialog before requesting permission
                final shouldRequest = await PermissionRationaleDialog.show(
                  context,
                  PermissionRationale.locationAlways,
                );

                if (shouldRequest == true) {
                  // Request background location permission
                  final service = ref.read(
                    permissionHandlerServiceProvider.notifier,
                  );

                  try {
                    final status = await service.requestPermission(
                      AppPermission.locationAlways,
                    );

                    if (status.isGranted) {
                      // Update setting
                      if (context.mounted) {
                        ref
                            .read(settingsServiceProvider.notifier)
                            .updatePartial(
                              (s) =>
                                  s.copyWith(backgroundLocationEnabled: true),
                            );
                      }
                    } else if (status.isPermanentlyDenied) {
                      // Show settings dialog
                      if (context.mounted) {
                        _showOpenSettingsDialog(context, ref);
                      }
                    }
                  } on PermissionDeniedException {
                    // User denied, don't update setting
                  } on LocationServiceDisabledException {
                    // Show enable location service dialog
                    if (context.mounted) {
                      _showEnableLocationDialog(context);
                    }
                  }
                }
              } else {
                // Just disable the setting
                ref
                    .read(settingsServiceProvider.notifier)
                    .updatePartial(
                      (s) => s.copyWith(backgroundLocationEnabled: false),
                    );
              }
            },
          ),
        ),
      ],
    );
  }

  /// Show dialog to open app settings for permanently denied permissions
  void _showOpenSettingsDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
          'Background location permission is permanently denied. '
          'Please enable it in app settings.',
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
