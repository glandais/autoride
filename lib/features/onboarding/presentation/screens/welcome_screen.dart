import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_action_button.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // App Icon/Logo
          Icon(
            Icons.directions_bike,
            size: 120,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.xl),

          // App Name
          Text(
            'AutoRide',
            style: theme.textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Tagline
          Text(
            'Automatic Trip Detection for Cyclists',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),

          // Value Proposition
          const _FeatureHighlight(
            icon: Icons.auto_awesome,
            title: 'Automatic Detection',
            description: 'Detects when you start cycling automatically',
          ),
          const SizedBox(height: AppSpacing.lg),
          const _FeatureHighlight(
            icon: Icons.battery_charging_full,
            title: 'Battery Optimized',
            description: 'Smart GPS usage saves your battery',
          ),
          const SizedBox(height: AppSpacing.lg),
          const _FeatureHighlight(
            icon: Icons.route,
            title: 'Track Your Routes',
            description: 'Keep a history of all your cycling trips',
          ),

          const Spacer(),

          // Get Started Button
          OnboardingActionButton(
            label: 'Get Started',
            onPressed: () {
              ref.read(onboardingProvider.notifier).nextPage();
            },
          ),
        ],
      ),
    );
  }
}

class _FeatureHighlight extends StatelessWidget {
  const _FeatureHighlight({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          icon,
          size: AppSpacing.iconLg,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium,
              ),
              Text(
                description,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
