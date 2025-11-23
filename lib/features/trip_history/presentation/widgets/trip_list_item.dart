import 'package:flutter/material.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';
import 'package:autoride/shared/widgets/status_badge.dart';
import 'package:autoride/core/theme/app_spacing.dart';
import 'package:autoride/core/theme/app_colors.dart';

/// Trip list item widget for displaying trip preview in list
class TripListItem extends StatelessWidget {
  const TripListItem({
    required this.trip,
    required this.onTap,
    super.key,
    this.onDelete,
  });

  final Trip trip;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: Activity badge and time
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  StatusBadge(
                    label: _getActivityLabel(trip.detectedActivity),
                    color: _getActivityColor(trip.detectedActivity),
                    icon: _getActivityIcon(trip.detectedActivity),
                  ),
                  Text(
                    _formatTime(trip.startTime),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Stats row: Distance and Duration
              Row(
                children: [
                  Expanded(
                    child: _StatDisplay(
                      icon: Icons.straighten,
                      label: 'Distance',
                      value: trip.formattedDistance,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _StatDisplay(
                      icon: Icons.access_time,
                      label: 'Duration',
                      value: _formatDuration(trip.duration),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              // Footer row: Confidence and confirmation status
              Row(
                children: [
                  if (trip.confidenceScore < 0.6) ...[
                    const Icon(
                      Icons.warning_amber,
                      size: AppSpacing.iconSm,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Low confidence',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (trip.userConfirmed) ...[
                    const Icon(
                      Icons.check_circle,
                      size: AppSpacing.iconSm,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Confirmed',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.success,
                      ),
                    ),
                  ],
                  if (onDelete != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      color: AppColors.error,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: onDelete,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Get activity label for display
  String _getActivityLabel(ActivityType activity) {
    switch (activity) {
      case ActivityType.cycling:
        return 'Cycling';
      case ActivityType.walking:
        return 'Walking';
      case ActivityType.running:
        return 'Running';
      case ActivityType.driving:
        return 'Driving';
      case ActivityType.stationary:
        return 'Stationary';
      case ActivityType.unknown:
        return 'Unknown';
    }
  }

  /// Get activity icon
  IconData _getActivityIcon(ActivityType activity) {
    switch (activity) {
      case ActivityType.cycling:
        return Icons.directions_bike;
      case ActivityType.walking:
        return Icons.directions_walk;
      case ActivityType.running:
        return Icons.directions_run;
      case ActivityType.driving:
        return Icons.directions_car;
      case ActivityType.stationary:
        return Icons.place;
      case ActivityType.unknown:
        return Icons.help_outline;
    }
  }

  /// Get activity color
  Color _getActivityColor(ActivityType activity) {
    switch (activity) {
      case ActivityType.cycling:
        return AppColors.success;
      case ActivityType.walking:
        return AppColors.info;
      case ActivityType.running:
        return AppColors.warning;
      case ActivityType.driving:
        return AppColors.error;
      case ActivityType.stationary:
        return Colors.grey;
      case ActivityType.unknown:
        return Colors.grey;
    }
  }

  /// Format time as HH:MM
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  /// Format duration as HH:MM or MM:SS
  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}

/// Internal widget for displaying stat with icon
class _StatDisplay extends StatelessWidget {
  const _StatDisplay({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: AppSpacing.iconMd, color: theme.colorScheme.primary),
        const SizedBox(width: AppSpacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
