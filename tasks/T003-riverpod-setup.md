# T003: Riverpod Code Generation Setup

## Overview
Configure Riverpod's code generation workflow using build_runner and riverpod_generator. Create example providers to demonstrate the state management pattern that will be used throughout the project. This establishes the foundation for type-safe, compile-time verified state management.

## Prerequisites
- ✅ T001: Project Setup & Dependencies completed
- Riverpod dependencies installed (flutter_riverpod, riverpod_annotation, build_runner, riverpod_generator)
- Understanding of Riverpod's code generation pattern
- Basic familiarity with Dart code generation

## Implementation Steps

### 1. Create Build Configuration

Create `build.yaml` in the project root to configure code generation:

**`build.yaml`**:
```yaml
targets:
  $default:
    builders:
      riverpod_generator:
        options:
          # Generate riverpod code with explicit JSON serialization support
          explicit_to_json: true
```

### 2. Update .gitignore

Ensure generated files are excluded from version control:

**Add to `.gitignore`**:
```
# Riverpod generated files
*.g.dart
*.freezed.dart

# Build runner cache
.dart_tool/build/
```

### 3. Create Example Provider (Simple Counter)

Demonstrate basic Riverpod code generation with a simple counter:

**`lib/shared/providers/example_provider.dart`**:
```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'example_provider.g.dart';

/// Simple counter provider example
/// Demonstrates basic @riverpod annotation usage
@riverpod
class Counter extends _$Counter {
  @override
  int build() => 0;

  void increment() => state++;
  void decrement() => state--;
  void reset() => state = 0;
}

/// Simple value provider example
/// Auto-disposed when no longer used
@riverpod
String welcomeMessage(WelcomeMessageRef ref) {
  return 'Welcome to AutoRide!';
}

/// Provider with parameters (family pattern)
/// Auto-disposed by default
@riverpod
int multiply(MultiplyRef ref, int value, int multiplier) {
  return value * multiplier;
}
```

### 4. Create App State Provider (Real-World Example)

Create a practical provider for app lifecycle state:

**`lib/shared/providers/app_state_provider.dart`**:
```dart
import 'package:flutter/widgets.dart';
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
    // Listen to app lifecycle changes
    final lifecycleBinding = WidgetsBinding.instance;

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
```

### 5. Run Code Generation

Execute build_runner to generate provider code:

```bash
# One-time generation (recommended for initial setup)
flutter pub run build_runner build --delete-conflicting-outputs

# Watch mode (for development - runs automatically on file changes)
flutter pub run build_runner watch --delete-conflicting-outputs
```

Expected output:
```
[INFO] Generating build script completed, took 412ms
[INFO] Creating build script snapshot... completed, took 8.2s
[INFO] Building new asset graph completed, took 1.1s
[INFO] Checking for unexpected pre-existing outputs completed, took 1ms
[INFO] Running build completed, took 5.3s
[INFO] Caching finalized dependency graph completed, took 85ms
[INFO] Succeeded after 5.4s with 2 outputs
```

Verify generated files:
- `lib/shared/providers/example_provider.g.dart`
- `lib/shared/providers/app_state_provider.g.dart`

### 6. Update main.dart with Provider Examples

Demonstrate provider usage in the app:

**`lib/main.dart`**:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'shared/providers/example_provider.dart';
import 'shared/providers/app_state_provider.dart';

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
      home: const HomePage(),
    );
  }
}

/// Home page demonstrating Riverpod usage
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch providers - rebuilds when state changes
    final counter = ref.watch(counterProvider);
    final welcomeMsg = ref.watch(welcomeMessageProvider);
    final appState = ref.watch(appStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AutoRide - Riverpod Demo'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Welcome message
            Text(
              welcomeMsg,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 32),

            // Counter display
            Text(
              'Counter: $counter',
              style: Theme.of(context).textTheme.displayMedium,
            ),
            const SizedBox(height: 16),

            // Counter controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () => ref.read(counterProvider.notifier).decrement(),
                  child: const Icon(Icons.remove),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () => ref.read(counterProvider.notifier).reset(),
                  child: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () => ref.read(counterProvider.notifier).increment(),
                  child: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // App state display
            Text(
              'App State: ${appState.name}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),

            // Example of family provider
            Text(
              '5 × 3 = ${ref.watch(multiplyProvider(5, 3))}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
```

### 7. Create Provider Documentation

**`lib/shared/providers/README.md`**:
```markdown
# Shared Providers

Global providers used across multiple features.

## Provider Patterns

### Simple Value Provider
Use `@riverpod` for functions that return a value:

\`\`\`dart
@riverpod
String myValue(MyValueRef ref) {
  return 'Hello';
}
\`\`\`

Usage: `ref.watch(myValueProvider)`

### Class-Based Provider (Notifier)
Use `@riverpod` with a class for stateful logic:

\`\`\`dart
@riverpod
class Counter extends _$Counter {
  @override
  int build() => 0;

  void increment() => state++;
}
\`\`\`

Usage:
- Watch state: `ref.watch(counterProvider)`
- Call methods: `ref.read(counterProvider.notifier).increment()`

### Family Provider (with parameters)
Use parameters for computed providers:

\`\`\`dart
@riverpod
int multiply(MultiplyRef ref, int a, int b) {
  return a * b;
}
\`\`\`

Usage: `ref.watch(multiplyProvider(5, 3))`

### AutoDispose vs KeepAlive

**AutoDispose (default)**: Provider is disposed when no longer watched
\`\`\`dart
@riverpod
class MyProvider extends _$MyProvider {
  // Auto-disposed by default
}
\`\`\`

**KeepAlive**: Provider stays in memory
\`\`\`dart
@Riverpod(keepAlive: true)
class MyProvider extends _$MyProvider {
  // Never disposed
}
\`\`\`

## Code Generation Workflow

### Initial Generation
\`\`\`bash
flutter pub run build_runner build --delete-conflicting-outputs
\`\`\`

### Watch Mode (Development)
\`\`\`bash
flutter pub run build_runner watch --delete-conflicting-outputs
\`\`\`

### Clean Generated Files
\`\`\`bash
flutter pub run build_runner clean
\`\`\`

## Best Practices

1. **Always use `part` directive**: Include `part 'filename.g.dart';`
2. **Run generation after changes**: Code won't compile without generated files
3. **Use watch mode during development**: Automatic regeneration on save
4. **AutoDispose for UI state**: Prevents memory leaks
5. **KeepAlive for persistent data**: Settings, authentication, active trip
6. **Top-level providers only**: Never create providers inside widgets
7. **Use ref.watch in build()**: For reactive updates
8. **Use ref.read for callbacks**: For one-time reads in event handlers

## Common Issues

### "part 'file.g.dart' not found"
**Solution**: Run `flutter pub run build_runner build --delete-conflicting-outputs`

### "The class '_$MyProvider' can't be found"
**Solution**: Ensure you've run code generation and the `.g.dart` file exists

### Generated file is outdated
**Solution**: Use `--delete-conflicting-outputs` flag or run `build_runner clean` first

### Changes not reflected
**Solution**: Stop watch mode, run clean, then run build again
```

## Acceptance Criteria

- [ ] `build.yaml` created with Riverpod configuration
- [ ] `.gitignore` updated to exclude `*.g.dart` files
- [ ] `example_provider.dart` created with counter, value, and family examples
- [ ] `app_state_provider.dart` created with lifecycle state management
- [ ] Code generation runs successfully without errors
- [ ] Generated `.g.dart` files created for both providers
- [ ] `main.dart` updated to demonstrate provider usage with ConsumerWidget
- [ ] Provider documentation created in `README.md`
- [ ] `flutter analyze` shows no errors
- [ ] App runs successfully showing counter and app state
- [ ] Watch mode works correctly (optional verification)

## Testing Checklist

After completing this task, verify:

- [ ] Run `flutter pub run build_runner build --delete-conflicting-outputs` - completes successfully
- [ ] Check `.dart_tool/build/` exists with generated files
- [ ] Verify `*.g.dart` files are NOT committed to git
- [ ] Run `flutter analyze` - no errors
- [ ] Run `flutter run` - app launches successfully
- [ ] Test counter increment/decrement buttons work
- [ ] Verify app state displays correctly
- [ ] Test hot reload works with providers
- [ ] Confirm watch mode auto-regenerates on file save (optional)

## Common Pitfalls

### 1. Forgetting `part` Directive
**Problem**: Build fails with "Undefined name '_$MyProvider'"

**Solution**:
```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'my_provider.g.dart'; // Must include this!

@riverpod
class MyProvider extends _$MyProvider { ... }
```

### 2. Generated Files Committed
**Problem**: `.g.dart` files tracked by git, causing merge conflicts

**Solution**: Add to `.gitignore`:
```
*.g.dart
*.freezed.dart
```

### 3. Outdated Generated Files
**Problem**: Changes to provider don't reflect in app

**Solution**:
```bash
flutter pub run build_runner clean
flutter pub run build_runner build --delete-conflicting-outputs
```

### 4. Build Runner Conflicts
**Problem**: "Conflicting outputs" error

**Solution**: Always use `--delete-conflicting-outputs` flag

### 5. Provider Not Updating UI
**Problem**: Changing state doesn't rebuild widget

**Solution**: Use `ref.watch()` in build method, not `ref.read()`:
```dart
// ✅ Correct - rebuilds on change
final counter = ref.watch(counterProvider);

// ❌ Wrong - doesn't rebuild
final counter = ref.read(counterProvider);
```

## Resources

### Official Documentation
- [Riverpod Code Generation](https://riverpod.dev/docs/concepts/about_code_generation) - Official guide
- [Riverpod Providers](https://riverpod.dev/docs/providers/provider) - Provider types
- [Build Runner](https://pub.dev/packages/build_runner) - Code generation tool

### Related CLAUDE.md Sections
- **Riverpod State Management**: Code generation pattern and core rules
- **Development Workflow**: Code generation workflow section

### Related Tasks
- **Previous**: T002 - Feature-First Directory Structure
- **Next**: T004 - Basic Location Service (will use providers)
- **Related**: All future tasks will use Riverpod providers

## Notes

- This task establishes the state management foundation for the entire project
- All future features will use the Riverpod code generation pattern demonstrated here
- Keep `build_runner watch` running during active development for automatic code generation
- The example counter provider is for demonstration - can be removed later
- The app_state_provider is production code and will be used for lifecycle management
- Generated files (*.g.dart) should NEVER be committed to version control
- Always run code generation before committing provider changes

## Estimated Time
**1 hour** (configuration, provider creation, code generation, testing)

---

**Created**: 2025-11-22
**Status**: Ready for implementation
**Dependencies**: T001 (Complete)
**Blocks**: T004, T007, T009, T010, T011 (all require providers)
