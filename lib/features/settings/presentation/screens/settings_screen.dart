import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/settings_service.dart';
import '../widgets/detection_settings_section.dart';
import '../widgets/battery_settings_section.dart';
import '../widgets/location_settings_section.dart';
import '../widgets/notification_settings_section.dart';
import '../widgets/privacy_settings_section.dart';
import '../widgets/display_settings_section.dart';
import '../widgets/data_management_section.dart';
import '../widgets/developer_settings_section.dart';
import '../../../diagnostics/presentation/widgets/audit_log_section.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../../../shared/widgets/loading_view.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/error_handler.dart';

/// Main settings screen for configuring all app preferences
///
/// Organized into sections:
/// - Detection settings (auto-start, sensitivity, thresholds)
/// - Battery optimization (power modes)
/// - Location settings (accuracy, distance filter, background)
/// - Notifications (trip events, sounds)
/// - Privacy (data collection consent)
/// - Display (units, theme)
/// - Data management (clear trips, reset settings)
/// - Developer settings (debug mode only)
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          // Reset to defaults button
          IconButton(
            icon: const Icon(Icons.restore),
            onPressed: () => _handleResetSettings(context, ref),
            tooltip: 'Reset to defaults',
          ),
        ],
      ),
      body: settingsAsync.when(
        data: (settings) => SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Detection Settings
              DetectionSettingsSection(settings: settings),
              const SizedBox(height: AppSpacing.md),

              // Battery Settings
              BatterySettingsSection(settings: settings),
              const SizedBox(height: AppSpacing.md),

              // Location Settings
              LocationSettingsSection(settings: settings),
              const SizedBox(height: AppSpacing.md),

              // Notification Settings
              NotificationSettingsSection(settings: settings),
              const SizedBox(height: AppSpacing.md),

              // Privacy Settings
              const PrivacySettingsSection(),
              const SizedBox(height: AppSpacing.md),

              // Display Settings
              DisplaySettingsSection(settings: settings),
              const SizedBox(height: AppSpacing.md),

              // Data Management
              DataManagementSection(settings: settings),
              const SizedBox(height: AppSpacing.md),

              // Diagnostic log — visible in release builds, unlike the
              // developer section below: a tester on a TestFlight or Play
              // build is exactly who needs to turn it on.
              AuditLogSection(settings: settings),

              // Developer Settings (only in debug builds)
              DeveloperSettingsSection(settings: settings),

              // Bottom safe area spacing
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
        loading: () =>
            const LoadingView.fullScreen(message: 'Loading settings...'),
        error: (error, stack) => ErrorView.generic(
          message: ErrorHandler.getErrorMessage(error),
          onRetry: () => ref.refresh(settingsServiceProvider),
        ),
      ),
    );
  }

  /// Handle reset settings action from app bar
  Future<void> _handleResetSettings(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset all settings?'),
        content: const Text(
          'This will restore all settings to their default values.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref.read(settingsServiceProvider.notifier).resetToDefaults();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings reset to defaults')),
        );
      }
    }
  }
}
