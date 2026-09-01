import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/user_settings.dart';
import '../../data/services/settings_service.dart';
import 'setting_section.dart';
import 'setting_radio_group.dart';

/// Battery optimization settings section
class BatterySettingsSection extends ConsumerWidget {
  const BatterySettingsSection({required this.settings, super.key});

  final UserSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingSection(
      title: 'Battery Optimization',
      subtitle: 'Adjust battery usage vs accuracy trade-off',
      children: [
        SettingRadioGroup<BatteryOptimizationMode>(
          title: 'Battery mode',
          value: settings.batteryMode,
          options: const [
            RadioOption(
              value: BatteryOptimizationMode.aggressive,
              label: 'Aggressive',
              description: 'Maximum battery savings, lower GPS accuracy',
            ),
            RadioOption(
              value: BatteryOptimizationMode.balanced,
              label: 'Balanced',
              description: 'Good balance of accuracy and battery life',
            ),
            RadioOption(
              value: BatteryOptimizationMode.performance,
              label: 'Performance',
              description: 'Best accuracy, higher battery usage',
            ),
          ],
          onChanged: (value) {
            ref
                .read(settingsServiceProvider.notifier)
                .updatePartial((s) => s.copyWith(batteryMode: value));
          },
        ),
      ],
    );
  }
}
