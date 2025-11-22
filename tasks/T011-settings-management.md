# T011: Settings & Preferences

**Status**: ⏳ In Progress
**Phase**: 3 - Data Management
**Dependencies**: T003 (Riverpod Code Generation Setup)
**Estimated Time**: 2-3 hours
**Started**: 2025-11-22

---

## 📋 Task Overview

Implement a comprehensive settings management system for AutoRide using SharedPreferences for persistence, Riverpod for state management, and Freezed for immutable models. The system will provide user-configurable preferences across detection, battery, location, notifications, display, and privacy settings.

---

## 🎯 Objectives

1. Create type-safe settings models with Freezed (sealed classes with extensions)
2. Implement persistent storage using SharedPreferences
3. Provide Riverpod providers for reactive settings updates
4. Add JSON serialization/deserialization for settings persistence
5. Create specialized UI providers for common setting updates
6. Write comprehensive tests for models and repository
7. Integrate settings with existing services (battery optimizer, location, detection)

---

## 📦 Deliverables

### Models
- `lib/features/settings/domain/models/user_settings.dart` - Main settings model
- `lib/features/settings/domain/models/detection_settings.dart` - Detection-specific settings

### Repository
- `lib/features/settings/data/repositories/settings_repository.dart` - SharedPreferences integration

### Services
- `lib/features/settings/data/services/settings_service.dart` - Riverpod service with providers

### Presentation
- `lib/features/settings/presentation/providers/settings_provider.dart` - UI-facing notifiers

### Tests
- `test/features/settings/domain/models/user_settings_test.dart` - Model tests
- `test/features/settings/data/repositories/settings_repository_test.dart` - Repository tests

---

## 🏗️ Architecture

### Settings Categories

**1. Detection Settings** (`DetectionSettings`)
- `autoStartEnabled: bool` - Enable automatic trip detection (default: true)
- `sensitivity: CyclingSensitivity` - Detection sensitivity (Low/Medium/High, default: Medium)
- `minimumTripDurationSeconds: int` - Minimum trip duration (default: 120s)
- `stationaryTimeoutSeconds: int` - Stationary timeout for trip end (default: 300s)

**2. Battery Optimization**
- `batteryMode: BatteryOptimizationMode` - Aggressive/Balanced/Performance (default: Balanced)

**3. Location Settings**
- `locationAccuracy: LocationAccuracyPreference` - Low/Medium/High (default: Medium)
- `distanceFilterMeters: int` - Distance filter for location updates (default: 15m)
- `backgroundLocationEnabled: bool` - Allow background tracking (default: true)

**4. Notification Settings**
- `tripNotificationsEnabled: bool` - Show trip start/stop notifications (default: true)
- `showOngoingNotification: bool` - Show foreground service notification (default: true)
- `soundOnTripStartStop: bool` - Play sound on trip events (default: false)

**5. Data & Privacy**
- `dataCollectionConsent: bool` - Allow data collection for ML (default: false)
- `anonymousUsageStats: bool` - Send anonymous usage stats (default: false)

**6. Display Settings**
- `distanceUnit: DistanceUnit` - Metric/Imperial (default: Metric)
- `speedUnit: SpeedUnit` - KmH/MpH/MS (default: KmH)
- `themeMode: ThemeMode` - Light/Dark/System (default: System)

**7. Developer Settings** (debug builds only)
- `debugLoggingEnabled: bool` - Enable debug logs (default: false)
- `showSensorOverlay: bool` - Show sensor data overlay (default: false)

### Enums

```dart
enum CyclingSensitivity { low, medium, high }
enum BatteryOptimizationMode { aggressive, balanced, performance }
enum LocationAccuracyPreference { low, medium, high }
enum DistanceUnit { metric, imperial }
enum SpeedUnit { kmh, mph, ms }
enum ThemeMode { light, dark, system }
```

---

## 📝 Implementation Steps

### Step 1: Create Directory Structure (2 min)

```bash
mkdir -p lib/features/settings/domain/models
mkdir -p lib/features/settings/data/repositories
mkdir -p lib/features/settings/data/services
mkdir -p lib/features/settings/presentation/providers
mkdir -p test/features/settings/domain/models
mkdir -p test/features/settings/data/repositories
```

### Step 2: Create Detection Settings Model (10 min)

**File**: `lib/features/settings/domain/models/detection_settings.dart`

**Key Points**:
- Use `sealed class` with Freezed
- Private constructor `const DetectionSettings._();` BEFORE factory
- Add `fromJson` factory for JSON deserialization
- Extensions in separate `extension` block OUTSIDE the class
- Include `sensitivityMultiplier` getter for threshold adjustments

**Pattern Reference**: `lib/features/trip_detection/domain/models/location_data.dart`

### Step 3: Create Main Settings Model (20 min)

**File**: `lib/features/settings/domain/models/user_settings.dart`

**Key Points**:
- Import detection_settings.dart
- All fields with `@Default()` annotations
- Nested `DetectionSettings` with default value
- Metadata fields: `version: int`, `lastModified: DateTime?`
- Extensions for:
  - `convertDistance(double meters)` - Convert to user's preferred unit
  - `convertSpeed(double metersPerSecond)` - Convert to user's speed unit
  - `geolocatorAccuracy` - Map to geolocator's LocationAccuracy enum

**Part Directives**:
```dart
part 'user_settings.freezed.dart';
part 'user_settings.g.dart';
```

### Step 4: Run Build Runner (2 min)

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

**Verify**: `.freezed.dart` and `.g.dart` files generated for both models

### Step 5: Create Settings Repository (15 min)

**File**: `lib/features/settings/data/repositories/settings_repository.dart`

**Methods**:
- `loadSettings()` - Load from SharedPreferences, return defaults if none exist
- `saveSettings(UserSettings)` - Save to SharedPreferences with updated timestamp
- `clearSettings()` - Reset to defaults by removing stored data
- `hasSettings()` - Check if settings exist

**Key Constant**:
```dart
static const String _settingsKey = 'user_settings';
```

**Error Handling**:
- Catch JSON parsing errors, return default settings
- Handle missing SharedPreferences gracefully

### Step 6: Create Settings Service (25 min)

**File**: `lib/features/settings/data/services/settings_service.dart`

**Providers to Create**:

1. **sharedPreferencesProvider** (`@riverpod Future<SharedPreferences>`)
   - Initialize SharedPreferences instance

2. **settingsRepositoryProvider** (`@riverpod SettingsRepository`)
   - Create repository with SharedPreferences
   - Use `ref.watch(sharedPreferencesProvider).requireValue`

3. **settingsServiceProvider** (`@riverpod class SettingsService`)
   - AsyncNotifier that loads settings on build
   - Methods:
     - `updateSettings(UserSettings)` - Full update
     - `updatePartial(UserSettings Function(UserSettings))` - Partial update helper
     - `resetToDefaults()` - Clear and reset
   - Getters:
     - `current` - Get current settings value
     - `isLoading` - Check loading state
     - `hasError` - Check error state

4. **currentSettingsProvider** (`@riverpod UserSettings`)
   - Convenience provider that returns current settings or defaults
   - Use `.when()` to handle loading/error states

**Pattern Reference**: `lib/features/trip_detection/data/services/location_service.dart`

### Step 7: Run Build Runner Again (2 min)

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

**Verify**: `settings_service.g.dart` generated

### Step 8: Create UI Providers (15 min)

**File**: `lib/features/settings/presentation/providers/settings_provider.dart`

**Notifiers to Create**:

1. **DetectionSettingsNotifier** (`@riverpod class`)
   - Build returns current detection settings
   - Methods:
     - `updateAutoStart(bool)`
     - `updateSensitivity(CyclingSensitivity)`
     - `updateMinimumDuration(int)`
     - `updateStationaryTimeout(int)`

2. **DisplaySettingsNotifier** (`@riverpod class`)
   - Build returns current user settings
   - Methods:
     - `updateDistanceUnit(DistanceUnit)`
     - `updateSpeedUnit(SpeedUnit)`
     - `updateThemeMode(ThemeMode)`

**Pattern**: Use `ref.read(settingsServiceProvider.notifier).updatePartial(...)` for updates

### Step 9: Run Build Runner Final Time (2 min)

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

**Verify**: `settings_provider.g.dart` generated

### Step 10: Write Model Tests (20 min)

**File**: `test/features/settings/domain/models/user_settings_test.dart`

**Test Cases**:
1. Create default settings
2. Serialize to JSON
3. Deserialize from JSON
4. Convert distance (metric vs imperial)
5. Convert speed (kmh, mph, m/s)
6. Map LocationAccuracyPreference to geolocator's LocationAccuracy
7. Detection sensitivity multiplier (0.8 for low, 1.0 for medium, 1.2 for high)

**Pattern Reference**: `test/features/trip_detection/data/services/location_service_test.dart`

### Step 11: Write Repository Tests (20 min)

**File**: `test/features/settings/data/repositories/settings_repository_test.dart`

**Setup**:
```dart
setUp(() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  repository = SettingsRepository(prefs);
});
```

**Test Cases**:
1. Return default settings when no data exists
2. Save and load settings
3. Update lastModified timestamp when saving
4. Clear settings
5. Check if settings exist
6. Handle corrupted JSON data gracefully

### Step 12: Run Quality Gates (10 min)

```bash
# Static analysis
flutter analyze

# Run all tests
flutter test

# Run specific test file
flutter test test/features/settings/domain/models/user_settings_test.dart
flutter test test/features/settings/data/repositories/settings_repository_test.dart
```

**Requirements**:
- ✅ `flutter analyze` must pass with no issues
- ✅ All tests must pass
- ✅ No unused imports or variables

### Step 13: Integration with Existing Services (15 min)

#### Battery Optimizer Integration

**File**: `lib/features/trip_detection/data/services/battery_optimizer.dart`

**Update** `_getPowerModeForBatteryLevel` method:

```dart
PowerModeConfig _getPowerModeForBatteryLevel(int batteryLevel) {
  final settings = ref.read(currentSettingsProvider);

  // Respect user's battery optimization mode
  if (settings.batteryMode == BatteryOptimizationMode.performance) {
    return PowerModeConfig.normal; // Always use performance mode
  }

  if (settings.batteryMode == BatteryOptimizationMode.aggressive) {
    if (batteryLevel < 50) return PowerModeConfig.low;
    if (batteryLevel < 70) return PowerModeConfig.medium;
    return PowerModeConfig.normal;
  }

  // Balanced mode (default)
  if (batteryLevel < 10) return PowerModeConfig.critical;
  if (batteryLevel < 20) return PowerModeConfig.low;
  if (batteryLevel < 50) return PowerModeConfig.medium;
  return PowerModeConfig.normal;
}
```

**Import** needed:
```dart
import '../../../settings/data/services/settings_service.dart';
```

#### Location Service Integration (Optional - for future UI)

When creating location settings UI, services can read from:
```dart
final settings = ref.read(currentSettingsProvider);
final accuracy = settings.geolocatorAccuracy;
final distanceFilter = settings.distanceFilterMeters;
```

#### Cycling Detector Integration (Optional - for future)

When implementing sensitivity settings:
```dart
final settings = ref.read(currentSettingsProvider);
final adjustedThreshold = AppConstants.minConfidenceForDetection *
                          settings.detection.sensitivityMultiplier;
```

---

## 🧪 Testing Strategy

### Unit Tests

**Models**:
- Default values initialization
- JSON serialization/deserialization
- Extension methods (conversions, mappings)
- Freezed copyWith functionality

**Repository**:
- Load/save/clear operations
- Error handling (corrupted data, missing keys)
- Default fallback behavior
- Timestamp updates

### Integration Testing (Manual)

1. **First Launch**:
   - App should use default settings
   - No errors from missing SharedPreferences data

2. **Settings Persistence**:
   - Change a setting
   - Close app completely
   - Reopen app
   - Verify setting persists

3. **Reset to Defaults**:
   - Modify multiple settings
   - Call `resetToDefaults()`
   - Verify all settings return to defaults

4. **Battery Integration**:
   - Change battery mode to "Performance"
   - Verify battery optimizer respects preference
   - Check power mode doesn't change with battery level

---

## ✅ Acceptance Criteria

1. ✅ All settings persist across app restarts
2. ✅ Default settings work without user configuration
3. ✅ Settings can be reset to defaults
4. ✅ JSON serialization/deserialization works correctly
5. ✅ Unit tests achieve >90% coverage for settings code
6. ✅ `flutter analyze` passes with no issues
7. ✅ `flutter test` passes all tests
8. ✅ Integration with battery_optimizer works correctly
9. ✅ All Freezed models use `sealed class` pattern
10. ✅ All Riverpod providers use correct ref types (`Ref ref`)
11. ✅ Extension methods are outside class definitions
12. ✅ No unused imports or variables

---

## 🚨 Common Mistakes to Avoid

### Mistake 1: Incorrect Freezed Structure
❌ **Wrong**: Using `class` instead of `sealed class`
✅ **Right**: Use `sealed class` and private constructor before factory

### Mistake 2: Extension Methods Location
❌ **Wrong**: Methods inside Freezed class body
✅ **Right**: Extensions in separate `extension` block outside class

### Mistake 3: Riverpod Ref Types
❌ **Wrong**: Using specific ref types like `SettingsServiceRef`
✅ **Right**: Use plain `Ref ref` in provider parameters

### Mistake 4: SharedPreferences Testing
❌ **Wrong**: Not mocking SharedPreferences in tests
✅ **Right**: Use `SharedPreferences.setMockInitialValues({})` in setUp

### Mistake 5: JSON Parsing Errors
❌ **Wrong**: Letting app crash on corrupted settings data
✅ **Right**: Catch errors and return default settings

---

## 📚 Reference Examples

### Complete Freezed Model Pattern
See: `lib/features/trip_detection/domain/models/location_data.dart`

### Complete Riverpod Service Pattern
See: `lib/features/trip_detection/data/services/location_service.dart`

### Complete Repository Pattern
See: `lib/features/trip_detection/data/repositories/trip_repository.dart`

### Complete Test Pattern
See: `test/features/trip_detection/data/services/location_service_test.dart`

---

## 🔗 Dependencies

**Required Packages** (already in pubspec.yaml):
- `shared_preferences: ^2.3.4` ✅
- `freezed_annotation: ^2.4.4` ✅
- `riverpod_annotation: ^2.6.1` ✅

**Dev Dependencies**:
- `build_runner: ^2.4.14` ✅
- `freezed: ^2.5.7` ✅
- `riverpod_generator: ^2.6.2` ✅

---

## 📊 Progress Tracking

### Checklist

**Phase 1: Models** (~30 min)
- [ ] Create directory structure
- [ ] Create `detection_settings.dart` with Freezed model
- [ ] Create `user_settings.dart` with all settings
- [ ] Add JSON serialization
- [ ] Add extension methods
- [ ] Run build_runner

**Phase 2: Repository** (~15 min)
- [ ] Create `settings_repository.dart`
- [ ] Implement load/save/clear methods
- [ ] Add error handling

**Phase 3: Service** (~25 min)
- [ ] Create `settings_service.dart`
- [ ] Create sharedPreferences provider
- [ ] Create settingsRepository provider
- [ ] Create SettingsService notifier
- [ ] Create currentSettings convenience provider
- [ ] Run build_runner

**Phase 4: UI Providers** (~15 min)
- [ ] Create `settings_provider.dart`
- [ ] Create DetectionSettingsNotifier
- [ ] Create DisplaySettingsNotifier
- [ ] Run build_runner

**Phase 5: Testing** (~40 min)
- [ ] Write model tests
- [ ] Write repository tests
- [ ] Run `flutter analyze`
- [ ] Run `flutter test`
- [ ] Fix any issues

**Phase 6: Integration** (~15 min)
- [ ] Update battery_optimizer.dart
- [ ] Test integration manually
- [ ] Verify existing tests still pass

**Phase 7: Documentation** (~5 min)
- [ ] Update TASKS.md status (☐ → ✅)
- [ ] Update progress summary (10/40 complete)
- [ ] Commit with message: `T011: Settings & Preferences implementation`

---

## 🎯 Success Criteria Summary

**Code Quality**:
- All code follows existing patterns
- No `flutter analyze` warnings
- All tests pass
- >90% test coverage for new code

**Functionality**:
- Settings persist across app restarts
- Default values work correctly
- Reset to defaults works
- Integration with battery optimizer works

**Architecture**:
- Clean separation of concerns (models/repository/service/presentation)
- Follows Riverpod best practices
- Uses Freezed for immutable models
- Proper error handling

---

## 📝 Notes

- This task focuses on the **data layer** for settings. The UI screens (Settings Screen) will be implemented in T024.
- Integration with other services (location, detection) is minimal for now. Full integration will happen when those features need user configuration.
- Developer settings should be wrapped in `kDebugMode` checks when used in the app.
- The settings system is designed to be extensible - new settings can be added by updating the model and re-running build_runner.

---

**Task Created**: 2025-11-22
**Estimated Completion**: 2-3 hours
**Actual Completion**: TBD
**Dependencies**: T003 ✅
**Blocks**: T024 (Settings Screen UI)
