# T001: Project Setup & Dependencies

## Overview
Configure the Flutter project with all required dependencies for AutoRide's automatic bike trip detection functionality. This task establishes the foundation for state management, location tracking, sensors, background services, ML integration, and data persistence.

## Prerequisites
- Flutter SDK 3.10.1+ installed
- Android Studio / VS Code with Flutter plugins
- Git repository initialized
- Basic Flutter project created

## Implementation Steps

### 1. Update pubspec.yaml Dependencies

Add the following dependencies to `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter

  # State Management - Riverpod with code generation
  flutter_riverpod: ^2.4.0
  riverpod_annotation: ^2.3.0

  # Location & Sensors
  geolocator: ^11.0.0            # GPS location tracking
  sensors_plus: ^4.0.0           # Accelerometer & gyroscope

  # Background Services
  flutter_background_service: ^5.0.0  # Background task execution
  wakelock_plus: ^1.1.0              # Keep device awake during tracking

  # Machine Learning
  tflite_flutter: ^0.10.0        # TensorFlow Lite for activity recognition

  # Data Persistence
  sqflite: ^2.3.0                # SQLite database for trips
  shared_preferences: ^2.2.0     # User settings storage

  # Permissions
  permission_handler: ^11.0.0    # Runtime permission handling

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

  # Code Generation
  build_runner: ^2.4.0           # Code generation tool
  riverpod_generator: ^2.3.0     # Riverpod code generation

  # Assets
  flutter_launcher_icons: ^0.13.0  # App icon generation

flutter:
  uses-material-design: true
```

### 2. Update analysis_options.yaml

Replace the content with strict linting configuration:

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "build/**"

  errors:
    invalid_annotation_target: ignore

  strong-mode:
    implicit-casts: false
    implicit-dynamic: false

linter:
  rules:
    # Errors
    avoid_empty_else: true
    avoid_slow_async_io: true
    cancel_subscriptions: true
    close_sinks: true
    valid_regexps: true

    # Style
    always_declare_return_types: true
    always_put_required_named_parameters_first: true
    avoid_init_to_null: true
    avoid_return_types_on_setters: true
    prefer_final_fields: true
    prefer_final_locals: true
    prefer_const_constructors: true
    prefer_const_declarations: true
    sort_constructors_first: true

    # Pub
    sort_pub_dependencies: true
```

### 3. Validate Setup

Run the following commands to ensure everything is configured correctly:

```bash
# Fetch all dependencies
flutter pub get

# Run static analysis
flutter analyze

# Check Flutter installation
flutter doctor -v
```

Expected output:
- `flutter pub get`: Should complete without errors
- `flutter analyze`: No issues found (or only minor warnings)
- `flutter doctor`: All checkmarks for target platforms

### 4. Verify Dependencies

Check that key dependencies are properly resolved:

```bash
# List all dependencies
flutter pub deps

# Verify specific critical packages
grep -E "(flutter_riverpod|geolocator|sensors_plus)" pubspec.lock
```

## Acceptance Criteria

- [x] All dependencies added to `pubspec.yaml`
- [x] Version constraints follow CLAUDE.md specifications
- [x] `analysis_options.yaml` configured with strict linting
- [x] `flutter pub get` runs successfully
- [x] `flutter analyze` shows no critical errors
- [x] Flutter doctor reports healthy setup for target platforms
- [x] Project compiles without errors (`flutter build apk --debug` or equivalent)

## Common Pitfalls

### 1. Dependency Version Conflicts
**Problem**: Conflicting dependency versions cause resolution failures.

**Solution**:
```bash
# Clear cache and retry
flutter clean
flutter pub cache repair
flutter pub get
```

### 2. TensorFlow Lite Platform Issues
**Problem**: `tflite_flutter` may have platform-specific setup requirements.

**Solution**:
- Android: Requires `minSdkVersion 21` in `android/app/build.gradle`
- iOS: May need additional frameworks - will be configured in T028

### 3. Permission Handler Setup
**Problem**: `permission_handler` requires platform configuration.

**Solution**: Platform-specific setup will be handled in T027 and T028. For now, just add the dependency.

### 4. Code Generation Not Running
**Problem**: Riverpod generators not creating `.g.dart` files.

**Solution**: Will be addressed in T003 (Riverpod Code Generation Setup). For now, just ensure `build_runner` and `riverpod_generator` are in dev dependencies.

## Testing Checklist

After completing this task, verify:

- [ ] Run `flutter pub get` - completes without errors
- [ ] Run `flutter analyze` - no critical issues
- [ ] Run `flutter doctor` - all platforms healthy
- [ ] Check `pubspec.lock` exists and contains all dependencies
- [ ] Verify project structure is intact (lib/, android/, ios/)
- [ ] Ensure git status shows only expected changes (pubspec.yaml, pubspec.lock, analysis_options.yaml)

## Resources

### Official Documentation
- [Flutter Riverpod](https://riverpod.dev) - State management guide
- [Geolocator](https://pub.dev/packages/geolocator) - Location tracking setup
- [Flutter Background Service](https://pub.dev/packages/flutter_background_service) - Background task configuration
- [TensorFlow Lite Flutter](https://pub.dev/packages/tflite_flutter) - ML integration

### Related Tasks
- **Next Task**: T002 - Feature-First Directory Structure
- **Related**: T003 - Riverpod Code Generation Setup
- **Related**: T027 - Permission Handler Implementation

## Notes

- This task focuses purely on dependency configuration
- Platform-specific setup (AndroidManifest.xml, Info.plist) will be handled in T028
- Code generation will be configured in T003
- All dependencies follow the versions specified in CLAUDE.md
- Keep `pubspec.yaml` organized with comments for clarity

## Estimated Time
**30-45 minutes** (straightforward dependency addition and validation)

---

**Created**: 2025-11-22
**Status**: Ready for implementation
**Dependencies**: None
**Blocks**: T002, T003, T004
