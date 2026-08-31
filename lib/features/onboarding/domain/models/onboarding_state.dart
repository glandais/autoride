import 'package:freezed_annotation/freezed_annotation.dart';

part 'onboarding_state.freezed.dart';

@freezed
sealed class OnboardingState with _$OnboardingState {
  const OnboardingState._();

  const factory OnboardingState({
    @Default(0) int currentPage,
    @Default(false) bool locationPermissionGranted,
    @Default(false) bool backgroundPermissionGranted,
    @Default(false) bool notificationPermissionGranted,
    @Default(false) bool isComplete,
  }) = _OnboardingState;

  factory OnboardingState.initial() => const OnboardingState();
}

extension OnboardingStateExtensions on OnboardingState {
  bool get canProceedToNext {
    // Can always proceed from welcome and features
    if (currentPage < 2) return true;

    // Must have location permission to proceed from location screen
    if (currentPage == 2) return locationPermissionGranted;

    // Can proceed from background screen even if denied (optional)
    if (currentPage == 3) return true;

    return false;
  }

  bool get isLastPage => currentPage == 4;

  int get totalPages => 5;

  double get progress => (currentPage + 1) / totalPages;
}

enum OnboardingStep {
  welcome(0, 'Welcome'),
  features(1, 'Features'),
  locationPermission(2, 'Location'),
  backgroundPermission(3, 'Background'),
  complete(4, 'Complete');

  const OnboardingStep(this.pageIndex, this.label);
  final int pageIndex;
  final String label;
}
