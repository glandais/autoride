import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// Slider widget with label and value display for settings
///
/// Displays a titled slider with current value, min/max labels,
/// and optional unit suffix for numeric settings.
class SettingSlider extends StatelessWidget {
  const SettingSlider({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    super.key,
    this.unit,
    this.divisions,
    this.valueFormatter,
  });

  /// Slider title
  final String title;

  /// Current value
  final double value;

  /// Minimum value
  final double min;

  /// Maximum value
  final double max;

  /// Optional unit suffix (e.g., 's', 'm', 'km')
  final String? unit;

  /// Number of discrete divisions (optional)
  final int? divisions;

  /// Callback when value changes
  final ValueChanged<double> onChanged;

  /// Optional custom value formatter
  final String Function(double)? valueFormatter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final displayValue =
        valueFormatter?.call(value) ?? '${value.toInt()}${unit ?? ''}';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title and current value
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: theme.textTheme.bodyLarge),
              Text(
                displayValue,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xs),

          // Slider
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),

          // Min and max labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${min.toInt()}${unit ?? ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color?.withValues(
                    alpha: 0.6,
                  ),
                ),
              ),
              Text(
                '${max.toInt()}${unit ?? ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color?.withValues(
                    alpha: 0.6,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
