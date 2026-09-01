import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/user_settings.dart';
import '../../domain/models/detection_settings.dart';
import '../providers/settings_provider.dart';
import 'setting_section.dart';
import 'setting_tile.dart';
import 'setting_slider.dart';
import 'setting_radio_group.dart';

/// Detection settings section for configuring trip detection behavior
class DetectionSettingsSection extends ConsumerWidget {
  const DetectionSettingsSection({required this.settings, super.key});

  final UserSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingSection(
      title: 'Trip Detection',
      subtitle: 'Configure automatic trip detection behavior',
      children: [
        // Master switch: drives the detection coordinator's lifecycle.
        // (It replaces the old "Auto-start trips" tile, which toggled a field
        // no code ever read.)
        SettingTile(
          title: 'Automatic detection',
          subtitle:
              'Watch for motion and start tracking cycling trips on '
              'their own',
          trailing: Switch(
            value: settings.detection.automaticDetectionEnabled,
            onChanged: (value) {
              ref
                  .read(detectionSettingsProvider.notifier)
                  .updateAutomaticDetection(value);
            },
          ),
        ),

        const Divider(height: 1),

        // Sensitivity selector
        SettingRadioGroup<CyclingSensitivity>(
          title: 'Detection sensitivity',
          value: settings.detection.sensitivity,
          options: const [
            RadioOption(
              value: CyclingSensitivity.low,
              label: 'Low',
              description: 'Fewer false positives, may miss some trips',
            ),
            RadioOption(
              value: CyclingSensitivity.medium,
              label: 'Medium',
              description: 'Balanced detection (recommended)',
            ),
            RadioOption(
              value: CyclingSensitivity.high,
              label: 'High',
              description: 'Catch all trips, may have false positives',
            ),
          ],
          onChanged: (value) {
            ref
                .read(detectionSettingsProvider.notifier)
                .updateSensitivity(value);
          },
        ),

        const Divider(height: 1),

        // Minimum duration slider
        SettingSlider(
          title: 'Minimum trip duration',
          value: settings.detection.minimumTripDurationSeconds.toDouble(),
          min: 60,
          max: 300,
          unit: 's',
          divisions: 48,
          valueFormatter: (value) {
            final seconds = value.toInt();
            final minutes = (seconds / 60).floor();
            final remainingSeconds = seconds % 60;
            if (remainingSeconds == 0) {
              return '${minutes}min';
            }
            return '${minutes}min ${remainingSeconds}s';
          },
          onChanged: (value) {
            ref
                .read(detectionSettingsProvider.notifier)
                .updateMinimumDuration(value.toInt());
          },
        ),

        const Divider(height: 1),

        // Stationary timeout slider
        SettingSlider(
          title: 'Stationary timeout',
          value: settings.detection.stationaryTimeoutSeconds.toDouble(),
          min: 60,
          max: 600,
          unit: 's',
          divisions: 54,
          valueFormatter: (value) {
            final seconds = value.toInt();
            final minutes = (seconds / 60).floor();
            if (seconds % 60 == 0) {
              return '${minutes}min';
            }
            return '${minutes}min ${seconds % 60}s';
          },
          onChanged: (value) {
            ref
                .read(detectionSettingsProvider.notifier)
                .updateStationaryTimeout(value.toInt());
          },
        ),
      ],
    );
  }
}
