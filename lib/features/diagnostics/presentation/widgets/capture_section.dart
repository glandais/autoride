import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:autoride/core/theme/app_colors.dart';
import 'package:autoride/core/theme/app_spacing.dart';
import 'package:autoride/core/utils/error_handler.dart';
import 'package:autoride/features/diagnostics/data/services/audit_export_service.dart';
import 'package:autoride/features/diagnostics/data/services/audit_log_controller.dart';
import 'package:autoride/features/diagnostics/data/services/capture_controller.dart';
import 'package:autoride/features/diagnostics/domain/models/capture_session.dart';
import 'package:autoride/features/diagnostics/presentation/widgets/audit_privacy_dialog.dart';
import 'package:autoride/features/settings/domain/models/user_settings.dart';
import 'package:autoride/features/settings/presentation/widgets/setting_section.dart';
import 'package:autoride/features/settings/presentation/widgets/setting_tile.dart';

part 'capture_section.g.dart';

/// Counts, span and size of the captured corpus.
///
/// Rebuilt whenever a session starts or stops, so the row settles as soon as
/// the user stops recording rather than on the next visit to the screen.
@riverpod
Future<CaptureStats> captureStats(Ref ref) {
  ref.watch(captureControllerProvider);
  return ref.read(auditLogControllerProvider.notifier).captureStats();
}

/// Training-data capture (T034): the labelling control and what it has stored.
///
/// Gated on [UserSettings.dataCollectionConsent] rather than on `kDebugMode`,
/// for the same reason as the diagnostic log: the sessions worth having are
/// real rides on a real device, and a debug-only control cannot record them.
/// The section stays visible without consent, showing why it is unavailable —
/// a control that simply is not there reads as a missing feature.
class CaptureSection extends ConsumerStatefulWidget {
  const CaptureSection({required this.settings, super.key});

  final UserSettings settings;

  @override
  ConsumerState<CaptureSection> createState() => _CaptureSectionState();
}

class _CaptureSectionState extends ConsumerState<CaptureSection> {
  /// Anchors the share sheet's popover on iPad, where it needs a source rect.
  final GlobalKey _exportButtonKey = GlobalKey();

  /// The label the next session will start with. Held in the widget, not in the
  /// controller: it is a choice being made, and only becomes ground truth when
  /// the user actually starts recording.
  CaptureActivity _activity = CaptureActivity.bike;

  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final consented = widget.settings.dataCollectionConsent;
    final session = ref.watch(captureControllerProvider);
    final recording = session != null;

    return SettingSection(
      title: 'Training data',
      subtitle: 'Record labelled sensor data for activity recognition',
      children: [
        if (!consented)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              'Turn on "Record training data" under Data & Privacy to use '
              'this.',
              style: theme.textTheme.bodySmall,
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              0,
            ),
            child: Text(
              recording
                  ? 'Recording as ${session.activity.displayName}. Keep the '
                        'phone where you would normally carry it.'
                  : 'Pick what you are about to do, then start. The label is '
                        'the ground truth the model is trained against, so a '
                        'wrong one is worse than no recording at all.',
              style: theme.textTheme.bodySmall,
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final activity in CaptureActivity.values)
                  ChoiceChip(
                    label: Text(activity.displayName),
                    selected: (session?.activity ?? _activity) == activity,
                    // Locked while recording: relabelling mid-session would
                    // apply the new label to data already written under the
                    // old one.
                    onSelected: recording
                        ? null
                        : (_) => setState(() => _activity = activity),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: SizedBox(
              width: double.infinity,
              child: recording
                  ? ElevatedButton.icon(
                      onPressed: _stop,
                      icon: const Icon(Icons.stop),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                      ),
                      label: const Text('Stop recording'),
                    )
                  : ElevatedButton.icon(
                      onPressed: _start,
                      icon: const Icon(Icons.fiber_manual_record),
                      label: Text('Record ${_activity.displayName}'),
                    ),
            ),
          ),

          const Divider(height: 1),
          _CaptureStatsTile(),

          const Divider(height: 1),
          SettingTile(
            key: _exportButtonKey,
            title: 'Export training data…',
            subtitle: 'Save or send everything captured so far',
            trailing: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share),
            onTap: _isExporting ? null : _export,
          ),

          const Divider(height: 1),
          SettingTile(
            title: 'Delete training data',
            subtitle: 'Keeps the diagnostic log',
            trailing: const Icon(Icons.delete_outline, color: AppColors.error),
            onTap: _clear,
          ),
        ],
      ],
    );
  }

  Future<void> _start() async {
    await ref.read(captureControllerProvider.notifier).start(_activity);
    if (mounted) ref.invalidate(captureStatsProvider);
  }

  Future<void> _stop() async {
    await ref.read(captureControllerProvider.notifier).stop();
    if (mounted) ref.invalidate(captureStatsProvider);
  }

  Future<void> _export() async {
    if (!await AuditPrivacyDialog.show(context, capture: true)) return;
    if (!mounted) return;

    setState(() => _isExporting = true);
    try {
      await ref
          .read(auditExportServiceProvider)
          .shareCapture(sharePosition: _shareOrigin());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to export the training data: '
              '${ErrorHandler.getErrorMessage(e)}',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete captured training data?'),
        content: const Text(
          'This permanently deletes every recorded sample and label. Anything '
          'you have not exported is gone. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Ends the session first: deleting the rows of a recording session would
    // leave a `lbl start` with no data and no stop.
    await ref.read(captureControllerProvider.notifier).stop();
    await ref.read(auditLogControllerProvider.notifier).clearCapture();
    if (!mounted) return;
    ref.invalidate(captureStatsProvider);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Training data deleted'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  /// Source rect for the iPad share popover.
  Rect? _shareOrigin() {
    final box = _exportButtonKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}

/// How much has been captured, and how much of it has never left the device.
class _CaptureStatsTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(captureStatsProvider);

    return SettingTile(
      title: 'Captured',
      subtitle: stats.when(
        data: _describe,
        loading: () => 'Reading…',
        error: (_, _) => 'Could not read the captured data',
      ),
      trailing: const SizedBox.shrink(),
    );
  }

  static String _describe(CaptureStats stats) {
    if (stats.isEmpty) return 'Nothing captured yet';

    final size = stats.sizeBytes < 1024 * 1024
        ? '${(stats.sizeBytes / 1024).round()} KB'
        : '${(stats.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';

    // One row is one second, so the row count is the recorded duration — a
    // more useful figure here than the span between first and last row, which
    // would count the days between two sessions as recorded time.
    final minutes = (stats.rowCount / 60).round();
    final sessions = stats.sessionCount == 1
        ? '1 session'
        : '${stats.sessionCount} sessions';

    // Named because it is what capture retention deletes last, and what the
    // user loses if they let it: everything else exists in an exported file.
    final pending = stats.unexportedSessionCount == 0
        ? ''
        : ' · ${stats.unexportedSessionCount} not exported';

    return '$sessions · ~$minutes min · $size$pending';
  }
}
