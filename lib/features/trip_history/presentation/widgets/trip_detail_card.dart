import 'package:flutter/material.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/shared/widgets/stat_card.dart';
import 'package:autoride/core/theme/app_spacing.dart';

/// Trip detail card displaying comprehensive trip statistics
class TripDetailCard extends StatelessWidget {
  const TripDetailCard({required this.trip, super.key});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Statistics',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.md),

        // Main stats grid (2 columns)
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          childAspectRatio: 1.3,
          children: [
            StatCard(
              label: 'Distance',
              value: trip.formattedDistance,
              icon: Icons.straighten,
            ),
            StatCard(
              label: 'Duration',
              value: _formatDuration(trip.duration),
              icon: Icons.access_time,
            ),
            StatCard(
              label: 'Avg Speed',
              value: trip.avgSpeed != null
                  ? '${trip.avgSpeed!.toStringAsFixed(1)} km/h'
                  : 'N/A',
              icon: Icons.speed,
            ),
            StatCard(
              label: 'Max Speed',
              value: trip.maxSpeed != null
                  ? '${trip.maxSpeed!.toStringAsFixed(1)} km/h'
                  : 'N/A',
              icon: Icons.trending_up,
            ),
          ],
        ),
      ],
    );
  }

  /// Format duration for display
  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    if (minutes > 0) {
      return '${minutes}m ${secs}s';
    }
    return '${secs}s';
  }
}
