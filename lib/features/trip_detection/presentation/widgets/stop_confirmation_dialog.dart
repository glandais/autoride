import 'package:flutter/material.dart';
import 'package:autoride/features/trip_detection/data/services/trip_recorder_service.dart';
import 'package:autoride/core/theme/app_spacing.dart';

/// Confirmation dialog for stopping a trip
///
/// Displays trip summary and requires user confirmation before
/// stopping the trip recording.
///
/// Returns:
/// - `true` if user confirms stop
/// - `false` if user cancels
/// - `null` if dialog is dismissed
class StopConfirmationDialog extends StatelessWidget {
  const StopConfirmationDialog({
    required this.metrics,
    super.key,
  });

  /// Current trip metrics to display in summary
  final TripMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Stop Trip?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Are you sure you want to stop this trip?',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Trip summary
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trip Summary',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildSummaryRow(
                  context,
                  icon: Icons.route,
                  label: 'Distance',
                  value: metrics.formattedDistance,
                ),
                const SizedBox(height: AppSpacing.xs),
                _buildSummaryRow(
                  context,
                  icon: Icons.timer,
                  label: 'Duration',
                  value: metrics.formattedDuration,
                ),
                if (metrics.avgSpeedKmh != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _buildSummaryRow(
                    context,
                    icon: Icons.speed,
                    label: 'Avg Speed',
                    value: '${metrics.avgSpeedKmh!.toStringAsFixed(1)} km/h',
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),
          Text(
            'This trip will be saved to your history.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
      actions: [
        // Cancel button
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),

        // Confirm button (destructive style)
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          child: const Text('Stop Trip'),
        ),
      ],
    );
  }

  /// Helper to build a summary row with icon, label, and value
  Widget _buildSummaryRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          '$label:',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// Helper function to show the stop confirmation dialog
///
/// Returns a Future that resolves to:
/// - `true` if user confirms
/// - `false` if user cancels
/// - `null` if dialog is dismissed
Future<bool?> showStopConfirmationDialog(
  BuildContext context,
  TripMetrics metrics,
) {
  return showDialog<bool>(
    context: context,
    builder: (context) => StopConfirmationDialog(metrics: metrics),
  );
}
