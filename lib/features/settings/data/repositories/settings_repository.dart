import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/user_settings.dart';

/// Repository for managing user settings persistence with SharedPreferences
class SettingsRepository {
  SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String _settingsKey = 'user_settings';

  /// Load settings from SharedPreferences
  /// Returns default settings if none exist or if parsing fails
  Future<UserSettings> loadSettings() async {
    final jsonString = _prefs.getString(_settingsKey);

    if (jsonString == null) {
      // Return default settings on first launch
      return const UserSettings();
    }

    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return UserSettings.fromJson(json);
    } catch (e) {
      // If parsing fails (corrupted data), return defaults
      // Log error in debug mode but don't crash
      return const UserSettings();
    }
  }

  /// Save settings to SharedPreferences
  /// Automatically updates lastModified timestamp
  Future<void> saveSettings(UserSettings settings) async {
    // Update lastModified timestamp before saving
    final updatedSettings = settings.copyWith(lastModified: DateTime.now());

    final json = updatedSettings.toJson();
    final jsonString = jsonEncode(json);

    await _prefs.setString(_settingsKey, jsonString);
  }

  /// Clear all settings (reset to defaults)
  Future<void> clearSettings() async {
    await _prefs.remove(_settingsKey);
  }

  /// Check if settings exist in storage
  bool hasSettings() {
    return _prefs.containsKey(_settingsKey);
  }
}
