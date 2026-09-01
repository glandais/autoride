import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/legal_links.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_action_button.dart';

class BackgroundPermissionScreen extends ConsumerWidget {
  const BackgroundPermissionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(onboardingProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.lg),

          // Icon
          Icon(
            Icons.auto_awesome,
            size: 80,
            color: theme.colorScheme.secondary,
          ),
          const SizedBox(height: AppSpacing.lg),

          // Title
          Text(
            'Automatic Tracking',
            style: theme.textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),

          // Rationale
          Text(
            'Enable background location to automatically detect and record trips even when the app is closed.',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),

          // Benefits Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Benefits:', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.md),
                  const _BenefitItem(
                    icon: Icons.auto_mode,
                    text:
                        'Completely automatic - no need to start/stop manually',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const _BenefitItem(
                    icon: Icons.battery_charging_full,
                    text: 'Battery optimized - only uses GPS when cycling',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const _BenefitItem(
                    icon: Icons.check_circle,
                    text: 'Never miss a trip - records every ride',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Optional Note
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'This is optional. You can still record trips manually if you prefer.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Prominent disclosure (Play policy requirement).
          //
          // Google Play requires a disclosure that names the app, states that location is
          // collected in the background, and states the purpose — shown BEFORE the permission
          // request and not only in the privacy policy. Keep it immediately above the button
          // that triggers the request, and keep the wording in sync with
          // store-metadata/data-safety.md §6.2 (the screencast filed with the declaration
          // shows this block).
          const _BackgroundLocationDisclosure(),
          const SizedBox(height: AppSpacing.xl),

          // Allow Background Button
          OnboardingActionButton(
            label: state.backgroundPermissionGranted
                ? 'Background Enabled ✓'
                : 'Enable Automatic Tracking',
            onPressed: state.backgroundPermissionGranted
                ? () => ref
                      .read(onboardingProvider.notifier)
                      .skipBackgroundPermission()
                : () => ref
                      .read(onboardingProvider.notifier)
                      .requestBackgroundPermission(),
            icon: state.backgroundPermissionGranted
                ? Icons.check
                : Icons.auto_awesome,
          ),
          const SizedBox(height: AppSpacing.sm),

          // Skip Button
          if (!state.backgroundPermissionGranted)
            TextButton(
              onPressed: () {
                ref
                    .read(onboardingProvider.notifier)
                    .skipBackgroundPermission();
              },
              child: const Text('Skip for Now'),
            ),
        ],
      ),
    );
  }
}

/// Google Play's required prominent disclosure for background location access.
///
/// Wording is mandated by policy, not chosen for tone: it must name the app, say that location
/// is collected in the background, and say what for. See `store-metadata/data-safety.md` §6.2.
class _BackgroundLocationDisclosure extends StatelessWidget {
  const _BackgroundLocationDisclosure();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.my_location,
                size: AppSpacing.iconMd,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'AutoRide collects location data to detect and record your bike trips, '
                  'even when the app is closed or not in use.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your trips are stored only on this device. AutoRide has no account and no '
            'server — your routes are never uploaded.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  openLegalUrl(context, AppConstants.privacyPolicyUrl),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Privacy Policy'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitItem extends StatelessWidget {
  const _BenefitItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: AppSpacing.iconMd, color: theme.colorScheme.secondary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
