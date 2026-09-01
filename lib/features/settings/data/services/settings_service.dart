import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/user_settings.dart';
import '../repositories/settings_repository.dart';

part 'settings_service.g.dart';

/// Provider for SharedPreferences instance
@riverpod
Future<SharedPreferences> sharedPreferences(Ref ref) async {
  return await SharedPreferences.getInstance();
}

/// Provider for SettingsRepository
@riverpod
Future<SettingsRepository> settingsRepository(Ref ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return SettingsRepository(prefs);
}

/// Settings service - manages user settings with Riverpod
/// Automatically loads settings on initialization
@riverpod
class SettingsService extends _$SettingsService {
  @override
  Future<UserSettings> build() async {
    // Load settings from repository
    final repository = await ref.watch(settingsRepositoryProvider.future);
    return await repository.loadSettings();
  }

  /// Update settings with a complete UserSettings object
  Future<void> updateSettings(UserSettings settings) async {
    final repository = await ref.read(settingsRepositoryProvider.future);

    // Save to SharedPreferences
    await repository.saveSettings(settings);

    // Update state
    state = AsyncValue.data(settings);
  }

  /// Update settings using a partial update function
  /// Convenience method for updating specific fields
  Future<void> updatePartial(
    UserSettings Function(UserSettings) updater,
  ) async {
    final currentSettings = state.value;
    if (currentSettings == null) return;

    final updatedSettings = updater(currentSettings);
    await updateSettings(updatedSettings);
  }

  /// Reset settings to defaults
  Future<void> resetToDefaults() async {
    final repository = await ref.read(settingsRepositoryProvider.future);
    await repository.clearSettings();

    // Update state with defaults
    state = const AsyncValue.data(UserSettings());
  }

  // Convenience getters
  /// Get current settings value (may be null if loading/error)
  UserSettings? get current => state.value;

  /// Check if settings are loading
  bool get isLoading => state.isLoading;

  /// Check if settings load failed
  bool get hasError => state.hasError;
}

/// Provider for easy access to current settings
/// Returns default settings during loading or error states
@riverpod
UserSettings currentSettings(Ref ref) {
  final settingsAsync = ref.watch(settingsServiceProvider);
  return settingsAsync.when(
    data: (settings) => settings,
    loading: () => const UserSettings(),
    error: (_, _) => const UserSettings(),
  );
}
