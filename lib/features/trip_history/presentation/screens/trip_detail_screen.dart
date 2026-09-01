import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:autoride/features/trip_history/presentation/providers/trip_detail_provider.dart';
import 'package:autoride/features/trip_history/presentation/providers/trip_history_provider.dart';
import 'package:autoride/features/trip_history/presentation/widgets/trip_detail_card.dart';
import 'package:autoride/features/trip_history/presentation/widgets/trip_route_map.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_export/data/services/trip_export_service.dart';
import 'package:autoride/shared/widgets/error_view.dart';
import 'package:autoride/shared/widgets/loading_view.dart';
import 'package:autoride/core/theme/app_spacing.dart';
import 'package:autoride/core/theme/app_colors.dart';
import 'package:autoride/core/utils/error_handler.dart';

/// Trip detail screen showing comprehensive trip statistics and route map
///
/// Features:
/// - Detailed trip statistics
/// - Route map visualization
/// - Confirm/Delete actions
/// - Export as a Garmin FIT activity file
class TripDetailScreen extends ConsumerStatefulWidget {
  const TripDetailScreen({required this.tripId, super.key});

  final int tripId;

  @override
  ConsumerState<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends ConsumerState<TripDetailScreen> {
  /// True while a `.fit` export is being encoded and handed to the share sheet.
  ///
  /// Guards against a second tap queueing another encode on top of the first.
  bool _isExporting = false;

  /// Anchors the iPad share popover to the export button rather than to the
  /// whole screen.
  final GlobalKey _exportButtonKey = GlobalKey();

  int get tripId => widget.tripId;

  @override
  Widget build(BuildContext context) {
    final tripAsync = ref.watch(tripDetailProvider(tripId));
    final trip = tripAsync.asData?.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Details'),
        actions: [
          // Export as FIT
          IconButton(
            key: _exportButtonKey,
            icon: _isExporting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share),
            tooltip: 'Export as FIT',
            // Greyed out until the trip (and its route points) have loaded.
            onPressed: _isExporting || trip == null
                ? null
                : () => _handleExport(trip),
          ),
          // Delete button
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: AppColors.error,
            onPressed: () => _handleDelete(),
          ),
        ],
      ),
      body: tripAsync.when(
        data: (trip) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Route map
                if (trip.routePoints.isNotEmpty) ...[
                  TripRouteMap(routePoints: trip.routePoints, height: 300),
                ] else ...[
                  Container(
                    height: 300,
                    color: Colors.grey[200],
                    child: const Center(
                      child: Text('Route data not available'),
                    ),
                  ),
                ],

                // Trip statistics card
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TripDetailCard(trip: trip),

                      const SizedBox(height: AppSpacing.lg),

                      // Metadata section
                      _MetadataSection(trip: trip),

                      const SizedBox(height: AppSpacing.lg),

                      // Confirm button (if not confirmed)
                      if (!trip.userConfirmed)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _handleConfirm(),
                            icon: const Icon(Icons.check_circle),
                            label: const Text('Confirm Trip'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.md,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
        loading: () =>
            const LoadingView.fullScreen(message: 'Loading trip details...'),
        error: (error, stack) {
          // Handle trip not found error
          if (error is TripNotFoundException) {
            return ErrorView.notFound(
              title: 'Trip Not Found',
              message: error.message,
              onRetry: () => Navigator.of(context).pop(),
            );
          }

          // Generic error with retry
          return ErrorView.generic(
            message: ErrorHandler.getErrorMessage(error),
            onRetry: () => ref.refresh(tripDetailProvider(tripId)),
          );
        },
      ),
    );
  }

  /// Encode the trip as a Garmin FIT activity and open the OS share sheet.
  ///
  /// [trip] is null while the detail is still loading or has failed, in which
  /// case there is nothing to export yet.
  Future<void> _handleExport(Trip? trip) async {
    if (trip == null || _isExporting) return;

    // iPads anchor the share popover to a rect in screen coordinates; taking it
    // from the button's own box puts the arrow where the user tapped.
    final box =
        _exportButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;

    setState(() => _isExporting = true);
    try {
      await ref
          .read(tripExportServiceProvider)
          .shareAsFit(trip, sharePosition: origin);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to export trip: ${ErrorHandler.getErrorMessage(e)}',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// Handle trip confirmation
  Future<void> _handleConfirm() async {
    try {
      await ref.read(tripHistoryProvider.notifier).confirmTrip(tripId);

      // Refresh trip detail
      ref.invalidate(tripDetailProvider(tripId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trip confirmed'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to confirm trip: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Handle trip deletion
  Future<void> _handleDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Trip'),
        content: const Text(
          'Are you sure you want to delete this trip? This action cannot be undone.',
        ),
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

    if (confirmed == true && mounted) {
      try {
        await ref.read(tripHistoryProvider.notifier).deleteTrip(tripId);

        if (mounted) {
          Navigator.pop(context); // Go back to history screen
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Trip deleted')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete trip: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }
}

/// Metadata section showing trip details
class _MetadataSection extends StatelessWidget {
  const _MetadataSection({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Trip Details',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _MetadataRow(
          label: 'Start Time',
          value: _formatDateTime(trip.startTime),
        ),
        _MetadataRow(label: 'End Time', value: _formatDateTime(trip.endTime)),
        _MetadataRow(
          label: 'Detection Confidence',
          value: '${(trip.confidenceScore * 100).toStringAsFixed(0)}%',
          valueColor: _getConfidenceColor(trip.confidenceScore),
        ),
        _MetadataRow(
          label: 'Status',
          value: trip.userConfirmed ? 'Confirmed' : 'Unconfirmed',
          valueColor: trip.userConfirmed
              ? AppColors.success
              : AppColors.warning,
        ),
      ],
    );
  }

  /// Format DateTime for display
  String _formatDateTime(DateTime dateTime) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final month = months[dateTime.month];
    final day = dateTime.day;
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');

    return '$month $day, $hour:$minute';
  }

  /// Get color based on confidence score
  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return AppColors.success;
    if (confidence >= 0.6) return AppColors.warning;
    return AppColors.error;
  }
}

/// Metadata row widget
class _MetadataRow extends StatelessWidget {
  const _MetadataRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
