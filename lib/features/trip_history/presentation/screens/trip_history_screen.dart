import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:autoride/features/trip_history/presentation/providers/trip_history_provider.dart';
import 'package:autoride/features/trip_history/presentation/widgets/trip_list_item.dart';
import 'package:autoride/features/trip_history/presentation/screens/trip_detail_screen.dart';
import 'package:autoride/shared/widgets/empty_state.dart';
import 'package:autoride/shared/widgets/error_view.dart';
import 'package:autoride/core/theme/app_spacing.dart';
import 'package:autoride/core/utils/error_handler.dart';

/// Trip history screen showing list of all recorded trips
///
/// Features:
/// - Pull-to-refresh
/// - Date grouping (Today, Yesterday, This Week, etc.)
/// - Navigate to trip detail
/// - Empty state when no trips
class TripHistoryScreen extends ConsumerWidget {
  const TripHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(tripHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip History'),
        actions: [
          // Optional: Add filter button
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              // TODO: Implement filter dialog
            },
          ),
        ],
      ),
      body: tripsAsync.when(
        data: (trips) {
          // Show empty state if no trips
          if (trips.isEmpty) {
            return EmptyState(
              icon: Icons.history,
              title: 'No Trips Yet',
              subtitle: 'Start tracking your first bike trip!',
              action: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.directions_bike),
                label: const Text('Start Tracking'),
              ),
            );
          }

          // Show list of trips
          return RefreshIndicator(
            onRefresh: () async {
              await ref.read(tripHistoryProvider.notifier).refresh();
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: trips.length,
              itemBuilder: (context, index) {
                final trip = trips[index];

                // Show date header if this is the first trip of a new date
                final showDateHeader = index == 0 ||
                    _getDateLabel(trip.startTime) !=
                        _getDateLabel(trips[index - 1].startTime);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showDateHeader) ...[
                      Padding(
                        padding: const EdgeInsets.only(
                          top: AppSpacing.md,
                          bottom: AppSpacing.sm,
                          left: AppSpacing.sm,
                        ),
                        child: Text(
                          _getDateLabel(trip.startTime),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                    ],
                    TripListItem(
                      trip: trip,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => TripDetailScreen(tripId: trip.id!),
                          ),
                        );
                      },
                      onDelete: () async {
                        final confirmed = await _showDeleteConfirmation(context);
                        if (confirmed == true) {
                          await ref
                              .read(tripHistoryProvider.notifier)
                              .deleteTrip(trip.id!);

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Trip deleted')),
                            );
                          }
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorView.generic(
          message: ErrorHandler.getErrorMessage(error),
          onRetry: () => ref.read(tripHistoryProvider.notifier).refresh(),
        ),
      ),
    );
  }

  /// Helper function to generate date labels for grouping
  String _getDateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final tripDate = DateTime(date.year, date.month, date.day);

    if (tripDate == today) {
      return 'Today';
    }
    if (tripDate == yesterday) {
      return 'Yesterday';
    }
    if (tripDate.isAfter(today.subtract(const Duration(days: 7)))) {
      return 'This Week';
    }

    // Format: "January 15, 2024"
    const months = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${months[date.month]} ${date.day}, ${date.year}';
  }

  /// Show delete confirmation dialog
  Future<bool?> _showDeleteConfirmation(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Trip'),
        content: const Text('Are you sure you want to delete this trip? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
