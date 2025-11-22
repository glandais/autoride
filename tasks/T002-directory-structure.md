# T002: Feature-First Directory Structure

## Overview
Establish the feature-first directory structure for AutoRide, organizing code by features rather than file types. This creates a scalable, maintainable architecture that separates concerns and allows features to be self-contained modules.

## Prerequisites
- ✅ T001: Project Setup & Dependencies completed
- Flutter project with basic `lib/` directory
- Understanding of feature-based architecture pattern

## Implementation Steps

### 1. Create Core Directory Structure

The `core/` directory contains app-wide utilities, constants, and theme configuration.

```bash
mkdir -p lib/core/constants
mkdir -p lib/core/utils
mkdir -p lib/core/theme
```

**Create initial files:**

**`lib/core/constants/app_constants.dart`**:
```dart
/// App-wide constants for AutoRide
class AppConstants {
  // Detection thresholds
  static const double cyclingSpeedMin = 8.0; // km/h
  static const double cyclingSpeedMax = 40.0; // km/h
  static const double movementThreshold = 1.5; // m/s² acceleration

  // Location settings
  static const double distanceFilter = 15.0; // meters
  static const int locationTimeLimit = 30; // seconds

  // ML settings
  static const int sensorSamplingRate = 50; // Hz
  static const int mlInferenceInterval = 10; // seconds
  static const double confidenceThreshold = 0.85;

  // Battery optimization
  static const int lowBatteryThreshold = 20; // percent
  static const int sensorBufferSize = 3000; // samples (60s at 50Hz)

  // Database
  static const String databaseName = 'autoride.db';
  static const int databaseVersion = 1;

  // Prevent instantiation
  AppConstants._();
}
```

**`lib/core/utils/logger.dart`**:
```dart
import 'package:flutter/foundation.dart';

/// Simple logging utility for AutoRide
class Logger {
  final String tag;

  const Logger(this.tag);

  void debug(String message) {
    if (kDebugMode) {
      debugPrint('[$tag] DEBUG: $message');
    }
  }

  void info(String message) {
    if (kDebugMode) {
      debugPrint('[$tag] INFO: $message');
    }
  }

  void warning(String message) {
    if (kDebugMode) {
      debugPrint('[$tag] WARNING: $message');
    }
  }

  void error(String message, [Object? error, StackTrace? stackTrace]) {
    debugPrint('[$tag] ERROR: $message');
    if (error != null) {
      debugPrint('Error: $error');
    }
    if (stackTrace != null) {
      debugPrint('StackTrace: $stackTrace');
    }
  }
}
```

**`lib/core/theme/app_theme.dart`**:
```dart
import 'package:flutter/material.dart';

/// App theme configuration for AutoRide
class AppTheme {
  // Color palette
  static const Color primaryColor = Color(0xFF2196F3); // Blue
  static const Color secondaryColor = Color(0xFF4CAF50); // Green
  static const Color errorColor = Color(0xFFE53935); // Red
  static const Color backgroundColor = Color(0xFFFAFAFA);
  static const Color surfaceColor = Colors.white;

  // Text theme
  static const TextTheme textTheme = TextTheme(
    displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
    displayMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
    bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.normal),
    bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  );

  // Light theme
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.light,
        secondary: secondaryColor,
        error: errorColor,
      ),
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardTheme(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  // Dark theme (for future implementation)
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.dark,
        secondary: secondaryColor,
        error: errorColor,
      ),
      textTheme: textTheme,
    );
  }

  // Prevent instantiation
  AppTheme._();
}
```

### 2. Create Features Directory Structure

Each feature follows the data-domain-presentation pattern:

```bash
# Trip Detection feature
mkdir -p lib/features/trip_detection/data
mkdir -p lib/features/trip_detection/domain
mkdir -p lib/features/trip_detection/presentation
mkdir -p lib/features/trip_detection/services

# Trip History feature
mkdir -p lib/features/trip_history/data
mkdir -p lib/features/trip_history/domain
mkdir -p lib/features/trip_history/presentation

# Settings feature
mkdir -p lib/features/settings/data
mkdir -p lib/features/settings/domain
mkdir -p lib/features/settings/presentation

# Onboarding feature
mkdir -p lib/features/onboarding/presentation
```

**Create placeholder README files:**

**`lib/features/trip_detection/README.md`**:
```markdown
# Trip Detection Feature

Core automatic trip detection logic using motion sensors and GPS.

## Structure
- **data/**: Repository implementations, data sources
- **domain/**: Models, entities, business logic
- **presentation/**: UI components, providers
- **services/**: Background service, ML classifier
```

**`lib/features/trip_history/README.md`**:
```markdown
# Trip History Feature

View and manage past trip records.

## Structure
- **data/**: Repository for historical trips
- **domain/**: Trip models and queries
- **presentation/**: History list, trip details UI
```

**`lib/features/settings/README.md`**:
```markdown
# Settings Feature

User preferences and app configuration.

## Structure
- **data/**: SharedPreferences repository
- **domain/**: Settings models
- **presentation/**: Settings UI
```

**`lib/features/onboarding/README.md`**:
```markdown
# Onboarding Feature

First-run experience and permission setup.

## Structure
- **presentation/**: Welcome screens, permission flow
```

### 3. Create Shared Directory Structure

Shared resources used across multiple features:

```bash
mkdir -p lib/shared/models
mkdir -p lib/shared/providers
mkdir -p lib/shared/widgets
```

**Create initial shared files:**

**`lib/shared/models/.gitkeep`**:
```
# Placeholder for shared models
# Models used across multiple features will be placed here
```

**`lib/shared/providers/.gitkeep`**:
```
# Placeholder for shared providers
# Global providers (e.g., permission, battery) will be placed here
```

**`lib/shared/widgets/.gitkeep`**:
```
# Placeholder for shared widgets
# Reusable UI components will be placed here
```

### 4. Update main.dart

Update the main entry point to use the new theme:

**`lib/main.dart`**:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';

void main() {
  runApp(
    const ProviderScope(
      child: AutoRideApp(),
    ),
  );
}

class AutoRideApp extends StatelessWidget {
  const AutoRideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AutoRide',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: const Scaffold(
        body: Center(
          child: Text(
            'AutoRide - Trip Detection',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
```

### 5. Verify Directory Structure

Run this command to verify the structure:

```bash
tree lib -L 4 -I '*.g.dart'
```

Expected output:
```
lib/
├── core/
│   ├── constants/
│   │   └── app_constants.dart
│   ├── theme/
│   │   └── app_theme.dart
│   └── utils/
│       └── logger.dart
├── features/
│   ├── onboarding/
│   │   ├── presentation/
│   │   └── README.md
│   ├── settings/
│   │   ├── data/
│   │   ├── domain/
│   │   ├── presentation/
│   │   └── README.md
│   ├── trip_detection/
│   │   ├── data/
│   │   ├── domain/
│   │   ├── presentation/
│   │   ├── services/
│   │   └── README.md
│   └── trip_history/
│       ├── data/
│       ├── domain/
│       ├── presentation/
│       └── README.md
├── shared/
│   ├── models/
│   │   └── .gitkeep
│   ├── providers/
│   │   └── .gitkeep
│   └── widgets/
│       └── .gitkeep
└── main.dart
```

## Acceptance Criteria

- [ ] All core directories created (constants, utils, theme)
- [ ] All feature directories created with proper structure
- [ ] Shared directories created with placeholder files
- [ ] `app_constants.dart` contains essential constants
- [ ] `logger.dart` provides basic logging utility
- [ ] `app_theme.dart` defines Material 3 theme
- [ ] `main.dart` updated to use new theme and ProviderScope
- [ ] README files created for each feature
- [ ] Directory structure verified with `tree` command
- [ ] `flutter analyze` shows no errors
- [ ] App runs successfully showing "AutoRide - Trip Detection"

## Testing Checklist

After completing this task, verify:

- [ ] Run `flutter analyze` - no errors related to new files
- [ ] Run `flutter run` - app launches successfully
- [ ] Check app displays theme correctly (blue/green colors)
- [ ] Verify all directories exist with `ls -R lib/`
- [ ] Ensure git status shows all new files
- [ ] Check that imports work correctly in main.dart

## Common Pitfalls

### 1. Directory Creation on Windows
**Problem**: `mkdir -p` doesn't work on Windows CMD.

**Solution**:
```bash
# Use PowerShell or Git Bash
# Or create directories manually in file explorer
# Or use IDE's "New Directory" feature
```

### 2. Import Path Issues
**Problem**: Cannot find imported files (theme, constants).

**Solution**:
- Ensure import paths use relative paths or package imports
- Example: `import 'core/theme/app_theme.dart';`
- Not: `import '../core/theme/app_theme.dart';` (when in main.dart)

### 3. Empty Directories Not Tracked by Git
**Problem**: Git doesn't track empty directories.

**Solution**: `.gitkeep` files are already included in shared/ directories to ensure they're tracked.

### 4. Theme Not Applied
**Problem**: App doesn't show the custom theme.

**Solution**: Ensure `MaterialApp` uses `theme: AppTheme.lightTheme` in main.dart.

## Resources

### Architecture Patterns
- [Feature-First Architecture](https://codewithandrea.com/articles/flutter-project-structure/) - Code with Andrea
- [Domain-Driven Design in Flutter](https://medium.com/flutter-community/clean-architecture-with-flutter-d7aa5f0e3ce1)
- [Riverpod Architecture](https://riverpod.dev/docs/concepts/about_code_generation)

### Related CLAUDE.md Sections
- **Project Structure**: Feature-first organization pattern
- **Riverpod State Management**: Provider organization
- **Code Organization**: Naming conventions and hierarchy

### Related Tasks
- **Previous**: T001 - Project Setup & Dependencies
- **Next**: T003 - Riverpod Code Generation Setup
- **Related**: T020 - App Theme & Design System (will expand on theme)

## Notes

- This structure follows the "feature-first" pattern recommended in CLAUDE.md
- Each feature is self-contained with its own data, domain, and presentation layers
- Shared resources go in `shared/` to avoid circular dependencies
- Core utilities are app-wide and can be used anywhere
- `.gitkeep` files ensure empty directories are tracked in version control
- README files in features serve as documentation and navigation aids
- This structure scales well as the app grows in complexity

## Estimated Time
**30 minutes** (directory creation and basic file setup)

---

**Created**: 2025-11-22
**Status**: Ready for implementation
**Dependencies**: T001 (Complete)
**Blocks**: T003, T004, T007, T009, T020
