import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_state_provider.g.dart';

/// App lifecycle state
enum AppLifecycleState {
  foreground,
  background,
  inactive,
  paused,
}

/// App state provider
/// Tracks app lifecycle and foreground/background state
@riverpod
class AppState extends _$AppState {
  @override
  AppLifecycleState build() {
    // Auto-dispose when widget is disposed
    ref.onDispose(() {
      // Cleanup if needed
    });

    return AppLifecycleState.foreground;
  }

  void updateLifecycle(AppLifecycleState newState) {
    state = newState;
  }

  void enterForeground() {
    state = AppLifecycleState.foreground;
  }

  void enterBackground() {
    state = AppLifecycleState.background;
  }

  bool get isForeground => state == AppLifecycleState.foreground;
  bool get isBackground => state == AppLifecycleState.background;
}
