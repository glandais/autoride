import 'package:freezed_annotation/freezed_annotation.dart';

part 'auto_detection_state.freezed.dart';

/// Inputs that decide whether automatic trip detection is running.
///
/// Exposed by `AutoDetectionController` so the UI can explain *why* detection
/// is (not) running instead of just showing a dead toggle.
@freezed
sealed class AutoDetectionState with _$AutoDetectionState {
  const AutoDetectionState._();

  const factory AutoDetectionState({
    /// The persisted "Automatic detection" setting.
    @Default(false) bool enabled,

    /// Location permission is granted (foreground at least).
    @Default(false) bool permissionGranted,

    /// Onboarding has been completed at least once.
    @Default(false) bool onboardingComplete,
  }) = _AutoDetectionState;
}

extension AutoDetectionStateExtensions on AutoDetectionState {
  /// True when the coordinator should be listening for trips.
  bool get shouldListen => enabled && permissionGranted && onboardingComplete;

  /// Short reason detection is idle, or null when it is running.
  String? get blockedReason {
    if (shouldListen) return null;
    if (!onboardingComplete) return 'Finish setup to enable detection';
    if (!permissionGranted) return 'Location permission required';
    return 'Automatic detection is off';
  }
}
