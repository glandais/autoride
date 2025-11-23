import 'package:flutter/material.dart';
import '../../../../core/theme/app_spacing.dart';

/// Individual setting row with label and control widget
///
/// Similar to ListTile but with consistent styling for settings screens.
/// Displays a title, optional subtitle, and a trailing widget (Switch, Radio, etc.).
class SettingTile extends StatelessWidget {
  const SettingTile({
    required this.title,
    required this.trailing,
    super.key,
    this.subtitle,
    this.leadingIcon,
    this.onTap,
  });

  /// Setting title
  final String title;

  /// Optional subtitle/description
  final String? subtitle;

  /// Trailing widget (Switch, Radio, Icon, etc.)
  final Widget trailing;

  /// Optional tap callback
  final VoidCallback? onTap;

  /// Optional leading icon
  final IconData? leadingIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            // Leading icon (optional)
            if (leadingIcon != null) ...[
              Icon(
                leadingIcon,
                size: AppSpacing.iconMd,
                color: theme.iconTheme.color,
              ),
              const SizedBox(width: AppSpacing.md),
            ],

            // Title and subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Spacing between title and trailing
            const SizedBox(width: AppSpacing.md),

            // Trailing widget
            trailing,
          ],
        ),
      ),
    );
  }
}
