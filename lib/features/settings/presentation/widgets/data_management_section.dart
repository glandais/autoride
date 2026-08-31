import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/models/user_settings.dart';
import '../../data/services/settings_service.dart';
import '../../../trip_history/data/repositories/trip_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/error_handler.dart';
import 'setting_section.dart';
import 'setting_tile.dart';

part 'data_management_section.g.dart';

/// Version string shown in the About row.
///
/// Read from the installed package rather than hardcoded: `publish_beta.sh`
/// bumps the build number on every upload, so a literal goes stale from the
/// first release — exactly when tester bug reports start arriving.
@riverpod
Future<String> appVersionLabel(Ref ref) async {
  final info = await PackageInfo.fromPlatform();
  return 'AutoRide v${info.version} (build ${info.buildNumber})';
}

/// Data management and app information section
class DataManagementSection extends ConsumerWidget {
  const DataManagementSection({
    required this.settings,
    super.key,
  });

  final UserSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingSection(
      title: 'Data Management',
      children: [
        // Clear all trips
        SettingTile(
          title: 'Clear all trips',
          subtitle: 'Delete all recorded trip data',
          trailing: const Icon(Icons.delete_outline, color: AppColors.error),
          onTap: () async {
            final confirmed = await _showConfirmDialog(
              context,
              title: 'Clear all trips?',
              message:
                  'This will permanently delete all trip data. This action cannot be undone.',
              confirmText: 'Delete',
              isDestructive: true,
            );

            if (confirmed && context.mounted) {
              try {
                final repository = await ref.read(tripRepositoryProvider.future);
                await repository.deleteAllTrips();

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('All trips deleted'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Failed to delete trips: ${ErrorHandler.getErrorMessage(e)}',
                      ),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            }
          },
        ),

        const Divider(height: 1),

        // Reset settings
        SettingTile(
          title: 'Reset settings',
          subtitle: 'Restore all settings to defaults',
          trailing: const Icon(Icons.restore, color: AppColors.warning),
          onTap: () async {
            final confirmed = await _showConfirmDialog(
              context,
              title: 'Reset all settings?',
              message:
                  'This will restore all settings to their default values.',
              confirmText: 'Reset',
            );

            if (confirmed && context.mounted) {
              try {
                await ref.read(settingsServiceProvider.notifier).resetToDefaults();

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Settings reset to defaults'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Failed to reset settings: ${ErrorHandler.getErrorMessage(e)}',
                      ),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            }
          },
        ),

        const Divider(height: 1),

        // App version
        SettingTile(
          title: 'App version',
          subtitle: ref.watch(appVersionLabelProvider).when(
                data: (label) => label,
                loading: () => 'AutoRide',
                error: (_, _) => 'AutoRide',
              ),
          trailing: const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// Show confirmation dialog for destructive actions
  Future<bool> _showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmText,
    bool isDestructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: isDestructive
                    ? ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                      )
                    : null,
                child: Text(confirmText),
              ),
            ],
          ),
        ) ??
        false;
  }
}
