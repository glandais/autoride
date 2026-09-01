import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// Reusable card widget for displaying trip statistics
class StatCard extends StatelessWidget {
  const StatCard({
    required this.label,
    required this.value,
    required this.icon,
    super.key,
    this.iconColor,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: AppSpacing.iconLg,
                color: iconColor ?? theme.colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(value, style: theme.textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
