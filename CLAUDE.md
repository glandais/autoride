# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick Start

**Essential Commands**:
```bash
# Code generation (MUST run during development)
dart run build_runner watch

# Quality gates (run in order)
flutter analyze                  # MUST pass before testing
flutter test                     # All tests must pass
flutter test test/path/to/specific_test.dart  # Run single test
flutter run --release            # Test on physical device (sensors/GPS)
```

**Critical Rules**:
- **NEVER commit autonomously** - Only commit when user executes `/commit` command
- Always use `sealed class` with freezed models (see `location_data.dart`)
- Stream providers use `Ref ref`, not specific ref types
- Run `flutter analyze` BEFORE `flutter test`
- Test sensor/location features on **physical devices only** (not emulators)
- Check `AppConstants` for all thresholds before implementation
- Follow existing patterns in the codebase

**Main Branch**: `develop` (use for PRs)
**Task Tracker**: `tasks/TASKS.md` (authoritative progress and current phase)

---

## Key Files Reference

| Purpose | Location |
|---------|----------|
| **All Constants/Thresholds** | `lib/core/constants/app_constants.dart` |
| **Task Tracker** | `tasks/TASKS.md` (authoritative progress) |
| **Freezed Pattern Example** | `lib/features/trip_detection/domain/models/location_data.dart` |
| **Stream Provider Pattern** | `lib/features/trip_detection/data/services/location_service.dart:85-105` |
| **Cycling Detection Logic** | `lib/features/trip_detection/data/services/cycling_pattern_detector.dart` |
| **GPS Motion-Gating** | `lib/features/trip_detection/data/services/trip_detection_coordinator.dart` |
| **Auto-Detection Lifecycle** | `lib/features/trip_detection/presentation/providers/auto_detection_controller.dart` |
| **Battery Optimization** | `lib/features/trip_detection/data/services/battery_optimizer.dart` |
| **Platform Info Service** | `lib/core/platform/services/platform_info_service.dart` |
| **Android Permissions** | `android/app/src/main/AndroidManifest.xml` |
| **iOS Permissions** | `ios/Runner/Info.plist` |
| **iOS Privacy Manifest** | `ios/Runner/PrivacyInfo.xcprivacy` |

---

## Task Workflow

**Task System**: This project uses a structured task tracking system in `tasks/TASKS.md`.

**Progress**: tracked in `tasks/TASKS.md` — check it for the current phase and task count.

**Quick Flow**:
1. Check `tasks/TASKS.md` for next pending (☐) task
2. Request detailed guide: "Create detailed task for T009"
3. Update status: ☐ → ⏳ → ✅
4. Implement following quality gates below
5. Commit with the task ID inside a conventional-commit subject (see **Commit Format** below)
6. Update progress summary in `tasks/TASKS.md`

**Quality Gates** (run in this order):
1. Code generation: `dart run build_runner build`
2. Static analysis: `flutter analyze` (MUST pass)
3. Unit tests: `flutter test`
4. Physical device test (for sensor/location tasks)
5. Wait for user to run `/commit` (NEVER commit autonomously)

**Task Dependencies**: Never start a task before its dependencies are complete. See `tasks/TASKS.md` for dependency tree.

**Commit Format**: gitmoji + conventional commit, with the task ID inside the subject. This is
what the repository's history actually uses (`🚀 feat(release): T038 Android release signing…`),
and what the README asks contributors for.

```
<emoji> <type>(<scope>): T### Brief description

- Detailed change 1
- Detailed change 2
- Testing notes
```

The emoji is optional for non-feature work; dependency and docs commits in this repo use a bare
conventional subject (`deps(pub): …`, `docs(tasks): …`). Do not use the bare `T###:` prefix — no
commit in the repository's history uses it.

---

## Architecture Overview

**Project**: AutoRide - Automatic bike trip detection using motion sensors and ML

**Core Tech Stack**:
- **Flutter**: 3.47.2+ (Dart 3.13+)
- **State Management**: Riverpod with code generation (`@riverpod` annotation)
- **Data Models**: Freezed with `sealed class` pattern
- **Location**: Geolocator (GPS with background support)
- **Sensors**: sensors_plus (accelerometer, gyroscope)
- **ML**: TensorFlow Lite for activity recognition (future)
- **Database**: sqflite (local SQLite)
- **Persistence**: shared_preferences (settings)

**Project Structure** (Feature-First):
```
lib/
├── core/
│   ├── constants/        # AppConstants - all thresholds
│   ├── extensions/
│   ├── permissions/      # Permission models, rationales, handler service, widgets
│   ├── platform/         # PlatformInfo model + PlatformInfoService
│   ├── theme/
│   └── utils/
├── features/
│   ├── trip_detection/   # Core trip tracking
│   │   ├── data/         # Services, repositories
│   │   ├── domain/       # Models (freezed)
│   │   ├── presentation/ # Providers, screens, widgets
│   │   └── services/     # Background service
│   ├── trip_history/     # data/repositories + presentation
│   ├── settings/         # data/{repositories,services} + domain + presentation
│   └── onboarding/       # data/services + domain + presentation
├── shared/
│   └── widgets/          # Reusable UI (empty_state, error_view, stat_card, …)
└── main.dart
```

`lib/shared/models/` and `lib/shared/providers/` exist as placeholders and currently hold no
code — shared models live in their owning feature's `domain/`.

**Key Architecture Decisions**:
- **Battery-First Design**: Motion-gated GPS (sensors trigger location, not continuous)
- **Separation of Concerns**: Data → Domain → Presentation
- **Feature Isolation**: Each feature is self-contained
- **Background Tracking**: Foreground service with notification (required for reliability)

---

## Critical Patterns

### Freezed Models

**Pattern** (use `sealed class` with extensions):
```dart
@freezed
sealed class ModelName with _$ModelName {
  const ModelName._();  // ✅ Private constructor BEFORE factory

  const factory ModelName({
    required Type field1,
    required Type field2,
  }) = _ModelName;

  factory ModelName.fromSomething(Something obj) {
    return ModelName(field1: obj.x, field2: obj.y);
  }
}

// ✅ Methods in extensions OUTSIDE the class
extension ModelNameExtensions on ModelName {
  double get calculatedValue => field1 * field2;
  bool isValid() => field1 > 0;
}
```

**Reference**: See `lib/features/trip_detection/domain/models/location_data.dart`

### Riverpod Providers

**Stream Providers**:
```dart
@riverpod
Stream<Data> dataStream(
  Ref ref,  // ✅ Use plain 'Ref', NOT DataStreamRef
) async* {
  // ✅ Call provider function directly (no .stream property)
  final otherStream = otherStreamProvider(ref);

  await for (final data in otherStream) {
    yield processedData;
  }
}
```

**Class Providers** (Notifiers):
```dart
@riverpod
class MyService extends _$MyService {
  @override
  State build() {
    // Initialize
    return State.initial();
  }

  void doSomething() {
    state = state.copyWith(updated: true);
  }
}
```

**Reference**: See `lib/features/trip_detection/data/services/location_service.dart:85-105`

### Code Generation

**Required for**: Riverpod providers, Freezed models

**Workflow**:
```bash
# Watch mode (auto-regenerate on file changes)
dart run build_runner watch

# One-time generation
dart run build_runner build --delete-conflicting-outputs

# Clean and rebuild
dart run build_runner clean
dart run build_runner build --delete-conflicting-outputs
```

**Required directives**:
```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'filename.g.dart';  // ✅ Must match filename

@riverpod
class MyProvider extends _$MyProvider { /* ... */ }
```

---

## Lessons Learned & Common Mistakes

Five concrete mistakes from development (freezed class structure, Riverpod stream
providers, unused imports, test data vs thresholds, constructor ordering) are documented
with wrong/correct examples in the **`freezed-riverpod-patterns`** skill, along with the
full reference examples for models, providers, and tests. It loads automatically when you
work on models, providers, or code generation.

---

## Battery Optimization Strategy

**Core Principle**: Motion-gated GPS (don't run GPS continuously)

**Implementation**:
1. **Sensors first**: Use accelerometer to detect movement
2. **GPS on demand**: Only activate GPS when motion detected
3. **Adaptive accuracy**: Adjust based on battery level and activity
4. **Distance filtering**: Update every 15m for cycling (not every meter)
5. **Foreground service**: Required for reliable background tracking

**Battery States** (see `AppConstants`):
- **Normal** (>50%): 50Hz sensors, 30s location updates, 15m distance filter (`distanceFilterCycling`)
- **Medium** (20-50%): 40Hz sensors, 40s updates, 20m filter (`distanceFilterMoving`)
- **Low** (10-20%): 25Hz sensors, 60s updates, 30m filter (`distanceFilterMoving + 10`)
- **Critical** (<10%): 20Hz sensors, 90s updates, 50m filter (`distanceFilterStationary ~/ 2`)

The two derived filters are now named constants (`AppConstants.distanceFilterLowPower`,
`distanceFilterCriticalPower`), consumed by `PowerModeConfig`.

**Target**: <5% battery drain per hour of active tracking.
**Status**: power modes drive the location settings and sensor sampling rates since T041 part 2
(`529db42`); GPS is motion-gated by the coordinator. The drain target itself is unmeasured —
see `tasks/T041-device-validation.md`.

**Key Files**:
- `lib/features/trip_detection/data/services/battery_optimizer.dart`
- `lib/features/trip_detection/data/services/trip_detection_coordinator.dart` (owns the GPS gate)
- `lib/features/trip_detection/data/services/adaptive_location_settings.dart`

---

## Cycling Detection Logic

> ⚠️ **This algorithm is implemented but not wired up.** `CyclingPatternDetector` has zero
> references anywhere in `lib/`, and the test file named after it never imports it. What actually
> decides a trip start today is `TripStartDetector`: an instantaneous single-sample accel+gyro fit
> with no frequency analysis and no speed layer. The three-layer design below is the intended
> target, not current behaviour — see `tasks/LEDGER.md` L-011 and task **T041**. Its layer-3
> `currentLocation` is never assigned, so `speedScore` is a hardcoded 0.5.

**Multi-Layer Approach**:

1. **Motion Pattern Analysis** (Layer 1)
   - Acceleration range: 10-20 m/s² (cycling range)
   - Rotation range: 0.5-3.0 rad/s (pedaling motion)
   - Score: 0-1 based on how well values fit cycling profile

2. **Pedaling Frequency Analysis** (Layer 2)
   - Detect peaks in acceleration (pedaling cycles)
   - Expected frequency: 0.5-2.0 Hz (30-120 RPM)
   - Typical: 1.2 Hz (72 RPM)

3. **GPS Speed Validation** (Layer 3 - when available)
   - Cycling speed range: 8-40 km/h
   - Typical: 18 km/h
   - Too slow (<8): likely walking
   - Too fast (>40): likely driving

**Final Confidence Score**:
- Motion score: 40% weight
- Speed score: 35% weight
- Frequency score: 25% weight
- Threshold: 0.6 minimum for detection

**All thresholds defined in**: `lib/core/constants/app_constants.dart`

**Implementation**: `lib/features/trip_detection/data/services/cycling_pattern_detector.dart`

---

## Testing Strategy

**Order matters**: `flutter analyze` MUST pass before `flutter test`.

**Critical**: Sensor and location features MUST be tested on **physical devices** —
emulators do not produce usable sensor data.

Test layout, provider mocking with `ProviderContainer` overrides, and the physical-device
scenario checklist are in the **`autoride-testing`** skill.

---

## Common Issues Quick Reference

| Issue | Quick Fix | Reference |
|-------|-----------|-----------|
| `Undefined class XxxRef` | Use `Ref ref`, not specific types | Mistake #2 |
| Freezed compilation errors | Check `sealed class`, constructor order | Mistake #1 |
| Tests fail unexpectedly | Verify test data meets thresholds | Mistake #4 |
| Unused import/variable warnings | Run `flutter analyze`, remove them | Mistake #3 |
| `sort_constructors_first` warning | Move all constructors before fields | Mistake #5 |
| Code generation not working | Check `part 'file.g.dart';` directive | - |
| Build runner conflicts | Run with `--delete-conflicting-outputs` | - |
| Sensor data in emulator | Use physical device, emulators don't work | - |

---

## Development Workflow

### Daily Pattern

```bash
# Terminal 1: Code generation watcher
dart run build_runner watch

# Terminal 2: Run app on physical device
flutter run --release  # Test battery in release mode

# Check logs
flutter logs --verbose

# Profile battery (critical!)
# Android: Android Studio → Profiler → Energy
# iOS: Xcode → Debug Navigator → Energy Impact
```

### Before Committing

**IMPORTANT**: Never create commits autonomously. Only commit when user executes `/commit` command.

```bash
flutter analyze          # Must pass
flutter test            # All tests must pass
git status              # Check what's staged
git diff               # Review changes

# Wait for user to run /commit - DO NOT run git commit yourself
```

### Creating New Features

```bash
mkdir -p lib/features/feature_name/{data,domain,presentation,services}
```

---

## Platform-Specific Notes

### Android Permissions

Required permissions configured in `android/app/src/main/AndroidManifest.xml`:
- `ACCESS_FINE_LOCATION`
- `ACCESS_BACKGROUND_LOCATION` (Android 10+)
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_LOCATION` (Android 9+)
- `WAKE_LOCK`

**Background service**:
```xml
<service
    android:name="id.flutter.flutter_background_service.BackgroundService"
    android:foregroundServiceType="location"
    android:exported="false" />
```

### iOS Permissions

Configure in `ios/Runner/Info.plist`:
- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`
- `UIBackgroundModes` (location)

### Permission Strategy

**Progressive approach**:
1. Request basic location on first launch (with rationale)
2. Request background location when user starts first trip
3. Handle denials gracefully (allow manual tracking)

**Platform differences**:
- Android 10+: Two-step (foreground → background)
- Android 11+: User must select "Allow all the time" in settings
- iOS 14+: "Allow Once" vs "While Using" vs "Always"

---

## Platform Configuration Reference

Runtime detection of Android API levels and iOS versions via `PlatformInfoService`,
per-version permission strategy, and the iOS privacy manifest are documented in the
**`platform-config`** skill. Key files: `lib/core/platform/models/platform_info.dart`,
`lib/core/platform/services/platform_info_service.dart`.

---

## Reference Examples

Complete freezed model, stream provider, and test examples live in the
**`freezed-riverpod-patterns`** skill.

## Resources

Official docs (Flutter, Riverpod, Freezed, Geolocator, Sensors Plus) and battery/background
-location guides are listed at the end of the **`freezed-riverpod-patterns`** skill.

---

**Flutter Version**: 3.47.2+ (Dart 3.13+)
**Target SDK**: iOS 13+, Android 8+ (API 26+)
**Project Status**: see `tasks/TASKS.md` (authoritative progress and current phase)
