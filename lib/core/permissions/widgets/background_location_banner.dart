import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/models/platform_info.dart';
import '../../platform/services/platform_info_service.dart';
import '../../theme/app_spacing.dart';
import '../../../features/settings/data/services/settings_service.dart';
import '../models/background_location_state.dart';
import '../providers/background_location_status.dart';
import '../services/permission_handler_service.dart';

/// Tells the user that automatic detection cannot run in the background.
///
/// The stored `backgroundLocationEnabled` setting says nothing about what the
/// OS actually granted: on iOS the user can pick "While Using" (and iOS offers
/// the upgrade prompt only once per install), and on Android 11+ "Allow all the
/// time" can only be chosen in system settings. Automatic detection then
/// silently never starts a trip with the app closed — this banner is the only
/// place the app says so.
///
/// The same is true of a granted-but-approximate location: "Precise Location"
/// off (iOS 14+) or coarse-only (Android 12+) leaves detection running while
/// every point it records is kilometres off, so that case gets its own wording.
///
/// Shown only when automatic detection is enabled AND the OS reports an issue;
/// anything else (loading, error, ready, detection off) renders nothing.
class BackgroundLocationBanner extends ConsumerWidget {
  const BackgroundLocationBanner({super.key});

  /// The copy for one issue, on one platform.
  static ({IconData icon, String title, String body}) _wording(
    BackgroundLocationIssue issue, {
    required bool isIos,
  }) => switch (issue) {
    BackgroundLocationIssue.alwaysMissing => (
      icon: Icons.location_off,
      title: 'Automatic detection needs background location',
      body: isIos
          ? 'Set Location to "Always" in Settings so trips can start while '
                'the app is closed.'
          : 'Choose "Allow all the time" in Settings so trips can start '
                'while the app is closed.',
    ),
    BackgroundLocationIssue.preciseMissing => (
      icon: Icons.location_searching,
      title: 'Automatic detection needs precise location',
      body: isIos
          ? 'Turn on "Precise Location" for AutoRide in Settings so trips '
                'are recorded accurately.'
          : 'Choose "Precise" location for AutoRide in Settings so trips '
                'are recorded accurately.',
    ),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsServiceProvider).value;
    if (settings == null || !settings.detection.automaticDetectionEnabled) {
      return const SizedBox.shrink();
    }

    final issue = ref.watch(backgroundLocationStatusProvider).value?.issue;
    if (issue == null) {
      return const SizedBox.shrink();
    }

    // While the platform is unknown, the Android wording is the safer default:
    // it names a system-settings choice, which is true on both platforms.
    final isIos =
        ref.watch(platformInfoServiceProvider).value?.type == PlatformType.ios;
    final wording = _wording(issue, isIos: isIos);

    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    // The banner sits directly on top of the navigation bar, so the top hairline
    // is what separates it from the tab content scrolling behind it. No
    // SafeArea: NavigationBar below already absorbs the bottom inset.
    return Material(
      color: colors.tertiaryContainer,
      shape: Border(top: BorderSide(color: theme.dividerColor)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              wording.icon,
              color: colors.onTertiaryContainer,
              size: AppSpacing.iconMd,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    wording.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    wording.body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onTertiaryContainer,
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      key: const Key('background-location-open-settings'),
                      onPressed: () => ref
                          .read(permissionHandlerServiceProvider.notifier)
                          .openAppSettings(),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.onTertiaryContainer,
                      ),
                      child: const Text('Open Settings'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
