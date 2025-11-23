import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/user_settings.dart';
import '../../data/services/settings_service.dart';
import 'setting_section.dart';
import 'setting_tile.dart';

/// Privacy and data collection preferences section
class PrivacySettingsSection extends ConsumerWidget {
  const PrivacySettingsSection({
    required this.settings,
    super.key,
  });

  final UserSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingSection(
      title: 'Data & Privacy',
      subtitle: 'Control data collection and usage',
      children: [
        SettingTile(
          title: 'Data collection',
          subtitle: 'Allow anonymous sensor data collection for ML improvement',
          trailing: Switch(
            value: settings.dataCollectionConsent,
            onChanged: (value) {
              ref.read(settingsServiceProvider.notifier).updatePartial(
                    (s) => s.copyWith(dataCollectionConsent: value),
                  );
            },
          ),
        ),

        const Divider(height: 1),

        SettingTile(
          title: 'Usage statistics',
          subtitle: 'Send anonymous app usage stats',
          trailing: Switch(
            value: settings.anonymousUsageStats,
            onChanged: (value) {
              ref.read(settingsServiceProvider.notifier).updatePartial(
                    (s) => s.copyWith(anonymousUsageStats: value),
                  );
            },
          ),
        ),

        const Divider(height: 1),

        SettingTile(
          title: 'Privacy policy',
          subtitle: 'View our privacy policy',
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () {
            // TODO: Navigate to privacy policy or open URL
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Privacy policy coming soon'),
              ),
            );
          },
        ),
      ],
    );
  }
}
