import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_action_button.dart';

class SetupCompleteScreen extends ConsumerWidget {
  const SetupCompleteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(onboardingProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Success Icon
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: const BoxDecoration(
              color: Color.fromRGBO(76, 175, 80, 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle,
              size: 100,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),

          // Title
          Text(
            'You\'re All Set!',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),

          // Description
          Text(
            state.backgroundPermissionGranted
                ? 'AutoRide will automatically detect when you start cycling. Just hop on your bike and ride!'
                : 'AutoRide is ready! Tap the record button when you start riding to track your trips.',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),

          // Setup Summary
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  _SetupItem(
                    icon: Icons.location_on,
                    label: 'Location Access',
                    enabled: state.locationPermissionGranted,
                  ),
                  const Divider(),
                  _SetupItem(
                    icon: Icons.auto_awesome,
                    label: 'Automatic Tracking',
                    enabled: state.backgroundPermissionGranted,
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // Start Riding Button
          OnboardingActionButton(
            label: 'Start Riding',
            onPressed: () {
              ref.read(onboardingProvider.notifier).completeOnboarding();
            },
            icon: Icons.directions_bike,
          ),
        ],
      ),
    );
  }
}

class _SetupItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;

  const _SetupItem({
    required this.icon,
    required this.label,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(
            icon,
            color: enabled ? Colors.green : theme.colorScheme.outline,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge,
            ),
          ),
          Icon(
            enabled ? Icons.check_circle : Icons.cancel,
            color: enabled ? Colors.green : theme.colorScheme.outline,
          ),
        ],
      ),
    );
  }
}
