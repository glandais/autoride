import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/user_settings.dart';
import '../../data/services/settings_service.dart';
import 'setting_section.dart';
import 'setting_tile.dart';
import 'setting_slider.dart';
import 'setting_radio_group.dart';

/// Location settings section for GPS configuration
class LocationSettingsSection extends ConsumerWidget {
  const LocationSettingsSection({
    required this.settings,
    super.key,
  });

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
            ref.read(settingsServiceProvider.notifier).updatePartial(
                  (s) => s.copyWith(locationAccuracy: value),
                );
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
            ref.read(settingsServiceProvider.notifier).updatePartial(
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
                // TODO: Request background location permission in T027
                // For now, just update the setting
                ref.read(settingsServiceProvider.notifier).updatePartial(
                      (s) => s.copyWith(backgroundLocationEnabled: value),
                    );
              } else {
                ref.read(settingsServiceProvider.notifier).updatePartial(
                      (s) => s.copyWith(backgroundLocationEnabled: value),
                    );
              }
            },
          ),
        ),
      ],
    );
  }
}
