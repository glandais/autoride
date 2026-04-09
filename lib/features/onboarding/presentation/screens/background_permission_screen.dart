import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
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
                  Text(
                    'Benefits:',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const _BenefitItem(
                    icon: Icons.auto_mode,
                    text: 'Completely automatic - no need to start/stop manually',
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
                Icon(
                  Icons.info_outline,
                  color: theme.colorScheme.primary,
                ),
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
          const SizedBox(height: AppSpacing.xl),

          // Allow Background Button
          OnboardingActionButton(
            label: state.backgroundPermissionGranted
                ? 'Background Enabled ✓'
                : 'Enable Automatic Tracking',
            onPressed: state.backgroundPermissionGranted
                ? () => ref.read(onboardingProvider.notifier).nextPage()
                : () => ref.read(onboardingProvider.notifier).requestBackgroundPermission(),
            icon: state.backgroundPermissionGranted ? Icons.check : Icons.auto_awesome,
          ),
          const SizedBox(height: AppSpacing.sm),

          // Skip Button
          if (!state.backgroundPermissionGranted)
            TextButton(
              onPressed: () {
                ref.read(onboardingProvider.notifier).nextPage();
              },
              child: const Text('Skip for Now'),
            ),
        ],
      ),
    );
  }
}

class _BenefitItem extends StatelessWidget {
  const _BenefitItem({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          icon,
          size: AppSpacing.iconMd,
          color: theme.colorScheme.secondary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
