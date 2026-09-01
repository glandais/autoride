import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// Radio button group for enum selections in settings
///
/// Displays a group of radio options with labels, descriptions, and icons.
/// Supports generic types for type-safe enum handling.
class SettingRadioGroup<T> extends StatelessWidget {
  const SettingRadioGroup({
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
  });

  /// Group title
  final String title;

  /// Currently selected value
  final T value;

  /// List of available options
  final List<RadioOption<T>> options;

  /// Callback when selection changes
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group title
          Text(
            title,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: AppSpacing.sm),

          // Radio options wrapped in RadioGroup
          RadioGroup<T>(
            groupValue: value,
            onChanged: (newValue) {
              if (newValue != null) {
                onChanged(newValue);
              }
            },
            child: Column(
              children: options
                  .map((option) => _buildRadioOption(context, option))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadioOption(BuildContext context, RadioOption<T> option) {
    final theme = Theme.of(context);
    final isSelected = value == option.value;

    return InkWell(
      onTap: () => onChanged(option.value),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            // Radio button (managed by RadioGroup ancestor)
            Radio<T>(value: option.value),

            // Icon (optional)
            if (option.icon != null) ...[
              Icon(
                option.icon,
                size: AppSpacing.iconMd,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.iconTheme.color?.withValues(alpha: 0.6),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],

            // Label and description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isSelected ? theme.colorScheme.primary : null,
                    ),
                  ),
                  if (option.description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      option.description!,
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
          ],
        ),
      ),
    );
  }
}

/// Radio option data class
///
/// Represents a single option in a radio group with label,
/// optional description, and optional icon.
class RadioOption<T> {
  const RadioOption({
    required this.value,
    required this.label,
    this.description,
    this.icon,
  });

  /// The value of this option
  final T value;

  /// Display label for this option
  final String label;

  /// Optional description text
  final String? description;

  /// Optional icon
  final IconData? icon;
}
