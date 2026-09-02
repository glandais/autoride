import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/user_settings.dart';
import '../../data/services/settings_service.dart';
import 'setting_section.dart';
import 'setting_tile.dart';

/// Developer settings section (debug builds only)
class DeveloperSettingsSection extends ConsumerWidget {
  const DeveloperSettingsSection({required this.settings, super.key});

  final UserSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only show in debug builds
    if (!kDebugMode) {
      return const SizedBox.shrink();
    }

    return SettingSection(
      title: 'Developer',
      subtitle: 'Debug tools (only in debug builds)',
      children: [
        SettingTile(
          title: 'Sensor overlay',
          subtitle: 'Show real-time sensor data on screen',
          trailing: Switch(
            value: settings.showSensorOverlay,
            onChanged: (value) {
              ref
                  .read(settingsServiceProvider.notifier)
                  .updatePartial((s) => s.copyWith(showSensorOverlay: value));
            },
          ),
        ),
      ],
    );
  }
}
