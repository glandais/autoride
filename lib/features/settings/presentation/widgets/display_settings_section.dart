import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/user_settings.dart' as models;
import '../providers/settings_provider.dart';
import 'setting_section.dart';
import 'setting_radio_group.dart';

/// Display and appearance preferences section
class DisplaySettingsSection extends ConsumerWidget {
  const DisplaySettingsSection({required this.settings, super.key});

  final models.UserSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingSection(
      title: 'Display',
      subtitle: 'Customize units and appearance',
      children: [
        // Distance unit selector
        SettingRadioGroup<models.DistanceUnit>(
          title: 'Distance unit',
          value: settings.distanceUnit,
          options: const [
            RadioOption(
              value: models.DistanceUnit.metric,
              label: 'Metric (km)',
              description: 'Kilometers',
            ),
            RadioOption(
              value: models.DistanceUnit.imperial,
              label: 'Imperial (mi)',
              description: 'Miles',
            ),
          ],
          onChanged: (value) {
            ref
                .read(displaySettingsProvider.notifier)
                .updateDistanceUnit(value);
          },
        ),

        const Divider(height: 1),

        // Speed unit selector
        SettingRadioGroup<models.SpeedUnit>(
          title: 'Speed unit',
          value: settings.speedUnit,
          options: const [
            RadioOption(
              value: models.SpeedUnit.kmh,
              label: 'km/h',
              description: 'Kilometers per hour',
            ),
            RadioOption(
              value: models.SpeedUnit.mph,
              label: 'mph',
              description: 'Miles per hour',
            ),
            RadioOption(
              value: models.SpeedUnit.ms,
              label: 'm/s',
              description: 'Meters per second',
            ),
          ],
          onChanged: (value) {
            ref.read(displaySettingsProvider.notifier).updateSpeedUnit(value);
          },
        ),

        const Divider(height: 1),

        // Theme mode selector
        SettingRadioGroup<models.ThemeMode>(
          title: 'Theme',
          value: settings.themeMode,
          options: const [
            RadioOption(
              value: models.ThemeMode.light,
              label: 'Light',
              icon: Icons.light_mode,
            ),
            RadioOption(
              value: models.ThemeMode.dark,
              label: 'Dark',
              icon: Icons.dark_mode,
            ),
            RadioOption(
              value: models.ThemeMode.system,
              label: 'System',
              icon: Icons.brightness_auto,
              description: 'Follow system theme',
            ),
          ],
          onChanged: (value) {
            ref.read(displaySettingsProvider.notifier).updateThemeMode(value);
          },
        ),
      ],
    );
  }
}
