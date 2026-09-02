import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:autoride/core/audit/audit_event.dart';
import 'package:autoride/core/audit/audit_log.dart';

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

    if (AuditLog.enabled) {
      final previous = state.value;
      // Only the settings that change what the pipeline does. A log that
      // cannot tell "detection was off the whole time" from "detection was on
      // and never fired" answers the wrong question.
      _auditSettingChange(
        'automaticDetection',
        previous?.detection.automaticDetectionEnabled,
        settings.detection.automaticDetectionEnabled,
      );
      _auditSettingChange(
        'batteryMode',
        previous?.batteryMode.name,
        settings.batteryMode.name,
      );
      _auditSettingChange(
        'backgroundLocation',
        previous?.backgroundLocationEnabled,
        settings.backgroundLocationEnabled,
      );
      // Declared here so the log ends with a line saying it was turned off:
      // the sink is still installed at this point, so the emit lands. Without
      // it the journal simply stops, which is indistinguishable from a kill.
      _auditSettingChange(
        'auditLog',
        previous?.auditLogEnabled,
        settings.auditLogEnabled,
      );
      _auditSettingChange(
        'auditLogLevel',
        previous?.auditLogLevel.name,
        settings.auditLogLevel.name,
      );
    }

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

  void _auditSettingChange(String key, Object? from, Object? to) {
    if (from == to) return;
    AuditLog.emit(
      AuditEvent.setting,
      () => <String, Object?>{'k': key, 'o': from, 'n': to},
      critical: true,
    );
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
