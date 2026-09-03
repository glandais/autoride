import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/legal_links.dart';
import '../../data/services/settings_service.dart';
import '../../domain/models/user_settings.dart';
import 'setting_section.dart';
import 'setting_tile.dart';

/// Privacy information and links to the hosted legal documents.
///
/// This section still contains no data-*sharing* switch, and the "Usage statistics" toggle T037
/// removed is not coming back: the app has no code path that transmits anything, and a switch
/// that persists a preference nothing acts on tells the user their data is being sent when it is
/// not.
///
/// `dataCollectionConsent` is different, and T034 is the code that made it different. It now
/// gates a real behaviour — the on-device training capture — and the copy below says exactly
/// what that behaviour is, including that nothing leaves the phone. That is the condition on
/// which a re-added toggle is honest rather than decorative.
class PrivacySettingsSection extends ConsumerWidget {
  const PrivacySettingsSection({required this.settings, super.key});

  final UserSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return SettingSection(
      title: 'Data & Privacy',
      subtitle: 'Where your trip data lives',
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.phonelink_lock_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Your trips and routes are stored only on this device. AutoRide has no '
                  'account and no server, so they are never uploaded. Opening a map requests '
                  'map images from OpenStreetMap, which reveals your IP address and the area '
                  'you are viewing to them.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        SettingTile(
          title: 'Record training data',
          subtitle:
              'Lets you record raw motion-sensor data from this device, '
              'labelled with what you were doing, to improve automatic '
              'detection. Recording only happens while you start it yourself '
              'from the Training data section. The data — and your precise '
              'positions, if the diagnostic log is also on — is kept on this '
              'device until you delete or export it, and is never sent '
              'anywhere.',
          trailing: Switch(
            value: settings.dataCollectionConsent,
            onChanged: (value) {
              ref
                  .read(settingsServiceProvider.notifier)
                  .updatePartial(
                    (s) => s.copyWith(dataCollectionConsent: value),
                  );
            },
          ),
        ),

        const Divider(height: 1),

        SettingTile(
          title: 'Privacy policy',
          subtitle: 'What is stored, what leaves your device',
          trailing: const Icon(Icons.open_in_new, size: 16),
          onTap: () => openLegalUrl(context, AppConstants.privacyPolicyUrl),
        ),

        const Divider(height: 1),

        SettingTile(
          title: 'Terms of use',
          subtitle: 'Licence, safety, and measurement accuracy',
          trailing: const Icon(Icons.open_in_new, size: 16),
          onTap: () => openLegalUrl(context, AppConstants.termsOfUseUrl),
        ),
      ],
    );
  }
}
