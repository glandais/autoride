import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_action_button.dart';

class FeaturesScreen extends ConsumerWidget {
  const FeaturesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.xxl),

          // Title
          Text(
            'How It Works',
            style: theme.textTheme.displaySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),

          // Description
          Text(
            'AutoRide uses motion sensors and GPS to automatically detect when you start cycling',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),

          // Feature Cards
          Expanded(
            child: ListView(
              children: [
                _FeatureCard(
                  icon: Icons.sensors,
                  title: 'Motion Detection',
                  description: 'Detects cycling motion using accelerometer and gyroscope',
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: AppSpacing.md),
                _FeatureCard(
                  icon: Icons.location_on,
                  title: 'Smart GPS',
                  description: 'GPS activates only when motion is detected to save battery',
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(height: AppSpacing.md),
                _FeatureCard(
                  icon: Icons.history,
                  title: 'Trip History',
                  description: 'Automatic recording and storage of your cycling routes',
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(height: AppSpacing.md),
                const _FeatureCard(
                  icon: Icons.battery_std,
                  title: 'Battery Friendly',
                  description: 'Adaptive tracking adjusts based on battery level',
                  color: Colors.green,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // Continue Button
          OnboardingActionButton(
            label: 'Continue',
            onPressed: () {
              ref.read(onboardingProvider.notifier).nextPage();
            },
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Color.fromRGBO(color.red, color.green, color.blue, 0.1),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Icon(
                icon,
                size: AppSpacing.iconLg,
                color: color,
              ),
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
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
