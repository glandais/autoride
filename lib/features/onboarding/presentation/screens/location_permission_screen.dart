import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_action_button.dart';

class LocationPermissionScreen extends ConsumerWidget {
  const LocationPermissionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(onboardingProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.xxl),

          // Icon
          Icon(
            Icons.location_on,
            size: 100,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.xl),

          // Title
          Text(
            'Location Permission',
            style: theme.textTheme.displaySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),

          // Rationale
          Text(
            'AutoRide needs access to your location to track your cycling routes and calculate trip statistics.',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),

          // Why we need it
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Why we need this:',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const _ReasonItem(
                    icon: Icons.route,
                    text: 'Record your cycling routes on a map',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const _ReasonItem(
                    icon: Icons.speed,
                    text: 'Calculate distance, speed, and duration',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const _ReasonItem(
                    icon: Icons.pin_drop,
                    text: 'Mark trip start and end locations',
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // Privacy Note
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.privacy_tip,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Your location data stays on your device. We never share or upload it.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Allow Location Button
          OnboardingActionButton(
            label: state.locationPermissionGranted
                ? 'Location Enabled ✓'
                : 'Allow Location Access',
            onPressed: state.locationPermissionGranted
                ? () => ref.read(onboardingProvider.notifier).nextPage()
                : () => ref.read(onboardingProvider.notifier).requestLocationPermission(),
            icon: state.locationPermissionGranted ? Icons.check : Icons.location_on,
          ),
        ],
      ),
    );
  }
}

class _ReasonItem extends StatelessWidget {
  const _ReasonItem({
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
          color: theme.colorScheme.primary,
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
