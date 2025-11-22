import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/models/onboarding_state.dart';
import '../../data/services/onboarding_service.dart';
import '../../../trip_detection/data/services/location_permission_service.dart';

part 'onboarding_provider.g.dart';

@riverpod
class Onboarding extends _$Onboarding {
  PageController? _pageController;

  @override
  OnboardingState build() {
    _pageController = PageController();
    return OnboardingState.initial();
  }

  PageController get pageController => _pageController!;

  void dispose() {
    _pageController?.dispose();
  }

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
    final service = ref.read(locationPermissionServiceProvider.notifier);
    final status = await service.requestPermission();

    final granted = status == LocationPermissionStatus.granted;
    state = state.copyWith(locationPermissionGranted: granted);

    if (granted) {
      await nextPage();
    }
  }

  /// Request background location permission
  Future<void> requestBackgroundPermission() async {
    final service = ref.read(locationPermissionServiceProvider.notifier);
    final status = await service.requestBackgroundPermission();

    final granted = status == LocationPermissionStatus.granted;
    state = state.copyWith(backgroundPermissionGranted: granted);

    // Can proceed even if denied (background is optional for manual trips)
    await nextPage();
  }

  /// Complete onboarding flow
  Future<void> completeOnboarding() async {
    state = state.copyWith(isComplete: true);
    await ref.read(onboardingServiceProvider.notifier).completeOnboarding();
  }

  /// Update current page (for PageView listener)
  void updatePage(int page) {
    state = state.copyWith(currentPage: page);
  }
}
