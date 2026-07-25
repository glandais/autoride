import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/legal_links.dart';
import 'setting_section.dart';
import 'setting_tile.dart';

/// Privacy information and links to the hosted legal documents.
///
/// This section deliberately contains no data-sharing switches. It used to offer "Data
/// collection" and "Usage statistics" toggles, but the app has no code path that transmits
/// sensor data or usage statistics — its only network request is for map tiles. A switch that
/// persists a preference nothing acts on tells the user their data is being sent when it is not,
/// and contradicts the declarations in `store-metadata/data-safety.md`.
///
/// `dataCollectionConsent` remains on `UserSettings`; T034 should reintroduce a toggle here
/// alongside the code that actually honours it.
class PrivacySettingsSection extends StatelessWidget {
  const PrivacySettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
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
