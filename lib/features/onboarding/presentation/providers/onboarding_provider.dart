import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/onboarding_state.dart';
import '../../data/services/onboarding_service.dart';
import '../../../../core/permissions/providers/background_location_status.dart';
import '../../../../core/permissions/services/permission_handler_service.dart';
import '../../../../core/permissions/exceptions/permission_exceptions.dart';
import '../../../../core/utils/logger.dart';

part 'onboarding_provider.g.dart';

@riverpod
class Onboarding extends _$Onboarding {
  PageController? _pageController;

  @override
  OnboardingState build() {
    _pageController = PageController();

    // Clean up PageController when provider is disposed
    ref.onDispose(() {
      _pageController?.dispose();
    });

    return OnboardingState.initial();
  }

  PageController get pageController => _pageController!;

  /// Navigate to next page
  Future<void> nextPage() async {
    if (state.isLastPage) {
      await completeOnboarding();
      return;
    }

    final nextPage = state.currentPage + 1;
    await _pageController?.animateToPage(
      nextPage,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    state = state.copyWith(currentPage: nextPage);
  }

  /// Navigate to previous page
  Future<void> previousPage() async {
    if (state.currentPage == 0) return;

    final previousPage = state.currentPage - 1;
    await _pageController?.animateToPage(
      previousPage,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    state = state.copyWith(currentPage: previousPage);
  }

  /// Skip to final page
  Future<void> skip() async {
    await _pageController?.animateToPage(
      4, // Final page
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    state = state.copyWith(currentPage: 4);
  }

  /// Request foreground location permission
  Future<void> requestLocationPermission() async {
    _log.info('Requesting foreground location permission (locationWhenInUse)');
    try {
      final permissionHandler = ref.read(
        permissionHandlerServiceProvider.notifier,
      );
      final status = await permissionHandler.requestPermission(
        AppPermission.locationWhenInUse,
      );

      // Check if still mounted after async operation
      if (!ref.mounted) return;

      _log.info('Foreground permission result: granted=${status.isGranted}');
      state = state.copyWith(locationPermissionGranted: status.isGranted);

      if (status.isGranted) {
        await nextPage();
      }
    } on PermissionPermanentlyDeniedException {
      _log.warning(
        'Foreground permission permanently denied, opening settings',
      );
      if (!ref.mounted) return;
      await ref
          .read(permissionHandlerServiceProvider.notifier)
          .openAppSettings();
      state = state.copyWith(locationPermissionGranted: false);
    } catch (e) {
      _log.error('Foreground permission request failed', e);
      if (!ref.mounted) return;
      state = state.copyWith(locationPermissionGranted: false);
    }
  }

  static const _log = Logger('Onboarding');

  /// Request background location permission
  Future<void> requestBackgroundPermission() async {
    _log.info('Requesting background location permission (locationAlways)');
    try {
      final permissionHandler = ref.read(
        permissionHandlerServiceProvider.notifier,
      );

      // Ensure foreground permission is granted first (required for background)
      final foregroundStatus = await permissionHandler.checkPermission(
        AppPermission.locationWhenInUse,
      );
      if (!foregroundStatus.isGranted) {
        _log.info('Foreground permission not granted, requesting it first');
        try {
          final requested = await permissionHandler.requestPermission(
            AppPermission.locationWhenInUse,
          );
          if (!ref.mounted) return;
          if (!requested.isGranted) {
            _log.warning(
              'Foreground permission denied, skipping background request',
            );
            state = state.copyWith(backgroundPermissionGranted: false);
            await nextPage();
            return;
          }
        } on PermissionPermanentlyDeniedException {
          _log.warning(
            'Foreground permission permanently denied, opening settings',
          );
          if (!ref.mounted) return;
          await permissionHandler.openAppSettings();
          state = state.copyWith(backgroundPermissionGranted: false);
          await nextPage();
          return;
        }
      }

      final status = await permissionHandler.requestPermission(
        AppPermission.locationAlways,
      );

      // Check if still mounted after async operation
      if (!ref.mounted) return;

      _log.info('Background permission result: granted=${status.isGranted}');
      state = state.copyWith(backgroundPermissionGranted: status.isGranted);
    } on PermissionPermanentlyDeniedException {
      _log.warning(
        'Background permission permanently denied, opening settings',
      );
      if (!ref.mounted) return;
      await ref
          .read(permissionHandlerServiceProvider.notifier)
          .openAppSettings();
      state = state.copyWith(backgroundPermissionGranted: false);
    } catch (e) {
      _log.error('Background permission request failed', e);
      // Permission denied or other error - continue anyway
      if (!ref.mounted) return;
      state = state.copyWith(backgroundPermissionGranted: false);
    } finally {
      // Whatever the OS answered, the cached status is now stale - and the
      // permanently-denied path even sent the user to app settings.
      if (ref.mounted) {
        ref.read(backgroundLocationStatusProvider.notifier).refresh();
      }
    }

    // Can proceed even if denied (background is optional for manual trips)
    await _finishPermissionStep();
  }

  /// Leave the background-permission step without requesting it.
  Future<void> skipBackgroundPermission() async {
    await _finishPermissionStep();
  }

  /// Request POST_NOTIFICATIONS (Android 13+) / the iOS notification prompt,
  /// then advance.
  ///
  /// The whole background design depends on notifications (foreground-service
  /// notification, trip start/stop alerts). The permission is declared in the
  /// manifest but Android 13+ also requires a runtime grant, so without this
  /// every notification the app posts is silently suppressed.
  Future<void> _finishPermissionStep() async {
    await requestNotificationPermission();
    if (!ref.mounted) return;
    await nextPage();
  }

  /// Request notification permission (no-op grant on Android < 13).
  Future<void> requestNotificationPermission() async {
    _log.info('Requesting notification permission');
    try {
      final permissionHandler = ref.read(
        permissionHandlerServiceProvider.notifier,
      );
      final status = await permissionHandler.requestPermission(
        AppPermission.notification,
      );

      if (!ref.mounted) return;

      _log.info('Notification permission result: granted=${status.isGranted}');
      state = state.copyWith(notificationPermissionGranted: status.isGranted);
    } catch (e) {
      // Notifications are not required to record trips - never block onboarding.
      _log.warning('Notification permission request failed: $e');
      if (!ref.mounted) return;
      state = state.copyWith(notificationPermissionGranted: false);
    }
  }

  /// Re-read every permission status from the OS.
  ///
  /// Android 11+ cannot request "Allow all the time" from a dialog: the user is
  /// sent to app settings, and the status we hold is the one from *before* that
  /// detour. Called when the app returns to the foreground so a user who did
  /// grant it is not treated as having refused.
  Future<void> refreshPermissionStatuses() async {
    try {
      final permissionHandler = ref.read(
        permissionHandlerServiceProvider.notifier,
      );

      final foreground = await permissionHandler.checkPermission(
        AppPermission.locationWhenInUse,
      );
      final background = await permissionHandler.checkPermission(
        AppPermission.locationAlways,
      );
      final notification = await permissionHandler.checkPermission(
        AppPermission.notification,
      );

      if (!ref.mounted) return;

      state = state.copyWith(
        locationPermissionGranted: foreground.isGranted,
        backgroundPermissionGranted: background.isGranted,
        notificationPermissionGranted: notification.isGranted,
      );
    } catch (e) {
      _log.warning('Permission status refresh failed: $e');
    }
  }

  /// Complete onboarding flow
  Future<void> completeOnboarding() async {
    if (!ref.mounted) return;
    state = state.copyWith(isComplete: true);
    await ref.read(onboardingServiceProvider.notifier).completeOnboarding();
  }

  /// Update current page (for PageView listener)
  void updatePage(int page) {
    state = state.copyWith(currentPage: page);
  }
}
