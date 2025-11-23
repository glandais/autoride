import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/user_settings.dart';
import '../../data/services/settings_service.dart';
import '../../../trip_history/data/repositories/trip_repository.dart';
import '../../../../core/theme/app_colors.dart';
import 'setting_section.dart';
import 'setting_tile.dart';

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
              final repository = await ref.read(tripRepositoryProvider.future);
              await repository.deleteAllTrips();

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All trips deleted')),
                );
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
              await ref.read(settingsServiceProvider.notifier).resetToDefaults();

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Settings reset to defaults')),
                );
              }
            }
          },
        ),

        const Divider(height: 1),

        // App version
        const SettingTile(
          title: 'App version',
          subtitle: 'AutoRide v1.0.0 (build 1)',
          trailing: SizedBox.shrink(),
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
