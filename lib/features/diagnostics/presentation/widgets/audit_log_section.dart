import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:autoride/core/audit/audit_level.dart';
import 'package:autoride/core/theme/app_colors.dart';
import 'package:autoride/core/utils/error_handler.dart';
import 'package:autoride/features/diagnostics/data/services/audit_export_service.dart';
import 'package:autoride/features/diagnostics/data/services/audit_log_controller.dart';
import 'package:autoride/features/diagnostics/domain/models/audit_log_stats.dart';
import 'package:autoride/features/diagnostics/presentation/widgets/audit_privacy_dialog.dart';
import 'package:autoride/features/settings/data/services/settings_service.dart';
import 'package:autoride/features/settings/domain/models/user_settings.dart';
import 'package:autoride/features/settings/presentation/widgets/setting_radio_group.dart';
import 'package:autoride/features/settings/presentation/widgets/setting_section.dart';
import 'package:autoride/features/settings/presentation/widgets/setting_tile.dart';

part 'audit_log_section.g.dart';

/// Counts, span and size of the recorded log.
///
/// Declared here rather than in the service layer for the same reason as
/// `appVersionLabel` in `data_management_section.dart`: it exists for this one
/// row and has no other consumer.
@riverpod
Future<AuditLogStats> auditLogStats(Ref ref) {
  // Rebuilds with the level, so flipping the switch refreshes the row.
  ref.watch(auditLogControllerProvider);
  return ref.read(auditLogControllerProvider.notifier).stats();
}

/// Diagnostic log settings.
///
/// Deliberately **not** gated on `kDebugMode`, unlike
/// `DeveloperSettingsSection`. The whole point is that someone running a
/// release build from TestFlight or Play can turn this on, ride, and send back
/// what the detection pipeline actually did — the checklist in
/// `tasks/T041-device-validation.md` has several items that cannot be settled
/// any other way.
class AuditLogSection extends ConsumerStatefulWidget {
  const AuditLogSection({required this.settings, super.key});

  final UserSettings settings;

  @override
  ConsumerState<AuditLogSection> createState() => _AuditLogSectionState();
}

class _AuditLogSectionState extends ConsumerState<AuditLogSection> {
  /// Anchors the share sheet's popover on iPad, where it needs a source rect.
  final GlobalKey _exportButtonKey = GlobalKey();

  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final enabled = settings.auditLogEnabled;

    return SettingSection(
      title: 'Diagnostic log',
      children: [
        SettingTile(
          title: 'Record a diagnostic log',
          subtitle:
              'Records what trip detection does on this device, including '
              'your precise GPS positions. Nothing is sent anywhere '
              'automatically. Entries older than 7 days are deleted, and you '
              'can clear the log at any time.',
          trailing: Switch(
            value: enabled,
            onChanged: (value) {
              ref
                  .read(settingsServiceProvider.notifier)
                  .updatePartial((s) => s.copyWith(auditLogEnabled: value));
            },
          ),
        ),

        if (enabled) ...[
          const Divider(height: 1),
          SettingRadioGroup<AuditLogLevel>(
            title: 'Detail level',
            value: settings.auditLogLevel,
            options: const [
              RadioOption(
                value: AuditLogLevel.normal,
                label: 'Normal',
                description:
                    'Decisions, GPS fixes, battery. ~1.5 MB per hour of '
                    'riding. Use this level when measuring battery drain.',
              ),
              RadioOption(
                value: AuditLogLevel.verbose,
                label: 'Verbose',
                description:
                    'Adds sensor summaries and rejected points, which is what '
                    'explains an unexpected pause. ~2 MB per hour.',
              ),
            ],
            onChanged: (value) {
              ref
                  .read(settingsServiceProvider.notifier)
                  .updatePartial((s) => s.copyWith(auditLogLevel: value));
            },
          ),

          const Divider(height: 1),
          _StatsTile(),

          const Divider(height: 1),
          SettingTile(
            key: _exportButtonKey,
            title: 'Export log…',
            subtitle: 'Save or send the recorded log',
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
            title: 'Clear log',
            subtitle: 'Delete everything recorded so far',
            trailing: const Icon(Icons.delete_outline, color: AppColors.error),
            onTap: _clear,
          ),
        ],
      ],
    );
  }

  Future<void> _export() async {
    // The file carries precise positions, so the user is told what leaves the
    // device before the share sheet — not after.
    if (!await AuditPrivacyDialog.show(context)) return;
    if (!mounted) return;

    setState(() => _isExporting = true);
    try {
      await ref
          .read(auditExportServiceProvider)
          .shareLog(sharePosition: _shareOrigin());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to export the log: ${ErrorHandler.getErrorMessage(e)}',
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
        title: const Text('Clear diagnostic log?'),
        content: const Text(
          'This permanently deletes every recorded event. This cannot be '
          'undone.',
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

    await ref.read(auditLogControllerProvider.notifier).clear();
    // Leaving the settings screen mid-delete disposes this element, and both
    // `ref` and `context` are dead after the await.
    if (!mounted) return;
    ref.invalidate(auditLogStatsProvider);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Diagnostic log cleared'),
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

/// How much has been recorded, and how far back it actually reaches.
class _StatsTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(auditLogStatsProvider);

    return SettingTile(
      title: 'Recorded',
      subtitle: stats.when(
        data: _describe,
        loading: () => 'Reading…',
        error: (_, _) => 'Could not read the log',
      ),
      trailing: const SizedBox.shrink(),
    );
  }

  static String _describe(AuditLogStats stats) {
    if (stats.isEmpty) return 'Nothing recorded yet';

    final size = stats.sizeBytes < 1024 * 1024
        ? '${(stats.sizeBytes / 1024).round()} KB'
        : '${(stats.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';

    // The covered span, not "7 days": at verbose level the size and row bounds
    // bite long before the age one does, so a full log reaches back hours, not
    // days. Saying so is the honest version of the retention promise.
    final oldest = stats.oldestAt;
    final since = oldest == null ? '' : ' · since ${_formatDate(oldest)}';

    return '${stats.eventCount} events · $size$since';
  }

  static String _formatDate(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(at.day)}/${two(at.month)} ${two(at.hour)}:${two(at.minute)}';
  }
}
