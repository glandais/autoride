import 'package:flutter/material.dart';
import 'package:autoride/core/theme/app_spacing.dart';

/// Control buttons for trip recording (pause/resume/stop)
///
/// Displays state-aware buttons:
/// - Primary button: Pause (when active) or Resume (when paused)
/// - Secondary button: Stop Trip (always visible, triggers confirmation)
class TripControlButtons extends StatelessWidget {
  const TripControlButtons({
    required this.isPaused,
    required this.onPauseResume,
    required this.onStop,
    super.key,
  });

  /// Whether the trip is currently paused
  final bool isPaused;

  /// Callback for pause/resume button press
  final VoidCallback onPauseResume;

  /// Callback for stop button press
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Primary button: Pause/Resume
        ElevatedButton.icon(
          onPressed: onPauseResume,
          icon: Icon(
            isPaused ? Icons.play_circle_outline : Icons.pause_circle_outline,
            size: 24,
          ),
          label: Text(
            isPaused ? 'Resume Trip' : 'Pause Trip',
            style: const TextStyle(fontSize: 16),
          ),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md,
              horizontal: AppSpacing.lg,
            ),
            backgroundColor: isPaused
                ? theme.colorScheme.secondary
                : theme.colorScheme.primary,
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // Secondary button: Stop Trip
        OutlinedButton.icon(
          onPressed: onStop,
          icon: const Icon(
            Icons.stop_circle,
            size: 24,
          ),
          label: const Text(
            'Stop Trip',
            style: TextStyle(fontSize: 16),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md,
              horizontal: AppSpacing.lg,
            ),
            foregroundColor: theme.colorScheme.error,
            side: BorderSide(
              color: theme.colorScheme.error,
              width: 2,
            ),
          ),
        ),
      ],
    );
  }
}
