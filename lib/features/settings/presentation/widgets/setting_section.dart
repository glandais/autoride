import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// Container widget for grouping related settings with a title
///
/// Provides consistent styling and spacing for settings sections.
/// Can optionally use a Card background for visual grouping.
class SettingSection extends StatelessWidget {
  const SettingSection({
    required this.title,
    required this.children,
    super.key,
    this.subtitle,
    this.useCard = true,
  });

  /// Section title displayed at the top
  final String title;

  /// Optional subtitle/description below the title
  final String? subtitle;

  /// List of setting widgets to display in this section
  final List<Widget> children;

  /// Whether to wrap content in a Card (default: true)
  final bool useCard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section title
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.md,
            right: AppSpacing.md,
            top: AppSpacing.md,
            bottom: AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withValues(
                      alpha: 0.7,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // Section content
        ...children,

        // Bottom padding
        const SizedBox(height: AppSpacing.sm),
      ],
    );

    if (useCard) {
      return Card(margin: EdgeInsets.zero, child: content);
    }

    return content;
  }
}
