import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/user_settings.dart';
import '../../data/services/settings_service.dart';
import 'setting_section.dart';
import 'setting_tile.dart';

/// Notification preferences section
class NotificationSettingsSection extends ConsumerWidget {
  const NotificationSettingsSection({required this.settings, super.key});

  final UserSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingSection(
      title: 'Notifications',
      subtitle: 'Configure notification preferences',
      children: [
        SettingTile(
          title: 'Trip notifications',
          subtitle: 'Notify when trips start and stop',
          trailing: Switch(
            value: settings.tripNotificationsEnabled,
            onChanged: (value) {
              ref
                  .read(settingsServiceProvider.notifier)
                  .updatePartial(
                    (s) => s.copyWith(tripNotificationsEnabled: value),
                  );
            },
          ),
        ),

        const Divider(height: 1),

        SettingTile(
          title: 'Ongoing notification',
          subtitle: 'Show notification during active trip',
          trailing: Switch(
            value: settings.showOngoingNotification,
            onChanged: (value) {
              ref
                  .read(settingsServiceProvider.notifier)
                  .updatePartial(
                    (s) => s.copyWith(showOngoingNotification: value),
                  );
            },
          ),
        ),

        const Divider(height: 1),

        SettingTile(
          title: 'Sound',
          subtitle: 'Play sound on trip start/stop',
          trailing: Switch(
            value: settings.soundOnTripStartStop,
            onChanged: (value) {
              ref
                  .read(settingsServiceProvider.notifier)
                  .updatePartial(
                    (s) => s.copyWith(soundOnTripStartStop: value),
                  );
            },
          ),
        ),
      ],
    );
  }
}
