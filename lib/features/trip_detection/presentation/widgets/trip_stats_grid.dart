import 'package:flutter/material.dart';
import 'package:autoride/features/trip_detection/data/services/trip_recorder_service.dart';
import 'package:autoride/shared/widgets/stat_card.dart';
import 'package:autoride/core/theme/app_spacing.dart';

/// Grid display of trip statistics (distance, duration, speeds)
///
/// Displays a 2x2 grid of StatCards showing:
/// - Distance traveled
/// - Trip duration
/// - Average speed
/// - Maximum speed
class TripStatsGrid extends StatelessWidget {
  const TripStatsGrid({
    required this.metrics,
    super.key,
  });

  /// Trip metrics to display
  final TripMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.md,
      crossAxisSpacing: AppSpacing.md,
      childAspectRatio: 1.3, // Slightly wider than tall for better fit
      children: [
        // Distance
        StatCard(
          label: 'Distance',
          value: metrics.formattedDistance,
          icon: Icons.route,
          iconColor: theme.colorScheme.primary,
        ),

        // Duration
        StatCard(
          label: 'Duration',
          value: metrics.formattedDuration,
          icon: Icons.timer,
          iconColor: theme.colorScheme.secondary,
        ),

        // Average Speed
        StatCard(
          label: 'Avg Speed',
          value: metrics.avgSpeedKmh != null
              ? '${metrics.avgSpeedKmh!.toStringAsFixed(1)} km/h'
              : '--',
          icon: Icons.speed,
          iconColor: theme.colorScheme.primary,
        ),

        // Maximum Speed
        StatCard(
          label: 'Max Speed',
          value: metrics.maxSpeedKmh != null
              ? '${metrics.maxSpeedKmh!.toStringAsFixed(1)} km/h'
              : '--',
          icon: Icons.trending_up,
          iconColor: theme.colorScheme.secondary,
        ),
      ],
    );
  }
}
