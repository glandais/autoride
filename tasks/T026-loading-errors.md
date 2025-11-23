# T026 - Loading States & Error Handling

**Status**: ⏳ In Progress
**Estimated Time**: 2 hours
**Dependencies**: T020 (App Theme & Design System)
**Phase**: 6 - User Interface (UI Polish)

---

## Overview

Create reusable loading and error handling components to standardize UI feedback across the AutoRide app. This task eliminates code duplication, fixes gaps in error handling, and provides a consistent user experience when dealing with async operations, loading states, and errors.

---

## Current State Analysis

### ✅ What Exists and Works Well

1. **Consistent AsyncValue Usage**
   - All major screens use `AsyncValue.when()` pattern
   - Providers use `AsyncValue.guard()` for safe async operations
   - Proper error boundaries (UI vs logic separation)
   - context.mounted checks in place

2. **Existing Error Handling Patterns**
   - Try-catch blocks for user actions
   - ScaffoldMessenger for success/error feedback
   - Colored snackbars (AppColors.error, AppColors.success)
   - Confirmation dialogs for destructive actions

3. **Custom Exceptions**
   - `TripNotFoundException` with message property
   - Good foundation for error type classification

4. **Existing Reusable Widgets**
   - `EmptyState` widget for empty lists
   - Good pattern to follow for ErrorView

### ❌ What's Missing (Gaps to Address)

1. **Code Duplication**
   - Error UI repeated across screens (same Column/Icon/Text pattern)
   - Loading state is just `CircularProgressIndicator()` everywhere
   - No centralized error display widget

2. **Inconsistent Patterns**
   - Different retry mechanisms:
     - `ref.read(provider.notifier).refresh()` (Trip History)
     - `ref.refresh(provider)` (Trip Detail)
     - `ref.invalidate(provider)` (Settings)
   - No standardized approach

3. **Missing Error Handling**
   - `data_management_section.dart` lines 40-41: No error handling for `deleteAllTrips()`
   - `data_management_section.dart` line 69: No error handling for `resetToDefaults()`
   - User gets no feedback if these operations fail

4. **No Error Classification**
   - No systematic error categorization (network, database, permission, etc.)
   - Limited custom exception usage
   - Generic error messages

5. **No Timeout Handling**
   - No visible timeout logic for async operations
   - Could lead to indefinite loading states

6. **Basic Loading States**
   - No context about what's loading
   - No loading state preservation during refresh
   - No skeleton loaders or progressive disclosure

---

## Implementation Steps

### Phase 1: Create Reusable Widgets (45 min)

#### 1.1 ErrorView Widget

**File**: `lib/shared/widgets/error_view.dart`

**Purpose**: Centralized, reusable error display widget

**Key Features**:
- Different error types (not found, network, permission, generic)
- Icon, title, message display
- Optional retry button
- Theme-aware styling
- Follows EmptyState pattern

**Implementation**:

```dart
import 'package:flutter/material.dart';
import 'package:autoride/core/theme/app_colors.dart';
import 'package:autoride/core/theme/app_spacing.dart';

enum ErrorType {
  notFound,
  network,
  permission,
  database,
  unknown,
}

class ErrorView extends StatelessWidget {
  final ErrorType type;
  final String? title;
  final String? message;
  final VoidCallback? onRetry;
  final String? retryLabel;

  const ErrorView({
    super.key,
    this.type = ErrorType.unknown,
    this.title,
    this.message,
    this.onRetry,
    this.retryLabel,
  });

  factory ErrorView.notFound({
    String? title,
    String? message,
    VoidCallback? onRetry,
  }) {
    return ErrorView(
      type: ErrorType.notFound,
      title: title ?? 'Not Found',
      message: message ?? 'The requested item could not be found.',
      onRetry: onRetry,
    );
  }

  factory ErrorView.network({
    String? title,
    String? message,
    VoidCallback? onRetry,
  }) {
    return ErrorView(
      type: ErrorType.network,
      title: title ?? 'Connection Error',
      message: message ?? 'Please check your internet connection and try again.',
      onRetry: onRetry,
      retryLabel: 'Retry',
    );
  }

  factory ErrorView.permission({
    String? title,
    String? message,
    VoidCallback? onRetry,
  }) {
    return ErrorView(
      type: ErrorType.permission,
      title: title ?? 'Permission Required',
      message: message ?? 'This feature requires additional permissions.',
      onRetry: onRetry,
      retryLabel: 'Grant Permission',
    );
  }

  factory ErrorView.database({
    String? title,
    String? message,
    VoidCallback? onRetry,
  }) {
    return ErrorView(
      type: ErrorType.database,
      title: title ?? 'Database Error',
      message: message ?? 'Failed to access local data. Please try again.',
      onRetry: onRetry,
      retryLabel: 'Retry',
    );
  }

  factory ErrorView.generic({
    required String message,
    VoidCallback? onRetry,
  }) {
    return ErrorView(
      type: ErrorType.unknown,
      title: 'Error',
      message: message,
      onRetry: onRetry,
      retryLabel: 'Retry',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              _getIcon(),
              size: 64,
              color: AppColors.error,
            ),
            const SizedBox(height: AppSpacing.md),
            if (title != null)
              Text(
                title!,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.error,
                    ),
                textAlign: TextAlign.center,
              ),
            if (title != null) const SizedBox(height: AppSpacing.sm),
            if (message != null)
              Text(
                message!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(retryLabel ?? 'Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getIcon() {
    switch (type) {
      case ErrorType.notFound:
        return Icons.search_off;
      case ErrorType.network:
        return Icons.wifi_off;
      case ErrorType.permission:
        return Icons.lock_outline;
      case ErrorType.database:
        return Icons.storage;
      case ErrorType.unknown:
        return Icons.error_outline;
    }
  }
}
```

**Usage Examples**:
```dart
// Generic error with retry
ErrorView.generic(
  message: 'Failed to load trips',
  onRetry: () => ref.refresh(tripsProvider),
)

// Not found error
ErrorView.notFound(
  title: 'Trip Not Found',
  message: 'This trip may have been deleted.',
)

// Network error with retry
ErrorView.network(
  onRetry: () => ref.read(tripsProvider.notifier).refresh(),
)
```

#### 1.2 LoadingView Widget

**File**: `lib/shared/widgets/loading_view.dart`

**Purpose**: Branded, consistent loading indicator

**Key Features**:
- Optional loading message
- Inline vs full-screen variants
- Consistent styling
- Theme-aware

**Implementation**:

```dart
import 'package:flutter/material.dart';
import 'package:autoride/core/theme/app_colors.dart';
import 'package:autoride/core/theme/app_spacing.dart';

class LoadingView extends StatelessWidget {
  final String? message;
  final bool inline;

  const LoadingView({
    super.key,
    this.message,
    this.inline = false,
  });

  const LoadingView.inline({
    super.key,
    this.message,
  }) : inline = true;

  const LoadingView.fullScreen({
    super.key,
    this.message,
  }) : inline = false;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: inline ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        if (message != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            message!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );

    if (inline) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: content,
      );
    }

    return Center(child: content);
  }
}
```

**Usage Examples**:
```dart
// Full-screen loading
LoadingView.fullScreen(message: 'Loading trips...')

// Inline loading (within a section)
LoadingView.inline(message: 'Saving...')

// Simple loading (no message)
const LoadingView()
```

---

### Phase 2: Error Handling Utilities (30 min)

#### 2.1 Error Handler Utility

**File**: `lib/core/utils/error_handler.dart`

**Purpose**: Centralized error type classification and message extraction

**Implementation**:

```dart
import 'package:sqflite/sqflite.dart';
import 'package:geolocator/geolocator.dart';
import 'package:autoride/features/trip_history/domain/exceptions/trip_not_found_exception.dart';

enum AppErrorType {
  notFound,
  network,
  permission,
  database,
  timeout,
  unknown,
}

class ErrorHandler {
  /// Classify error type based on exception
  static AppErrorType classifyError(Object error) {
    if (error is TripNotFoundException) {
      return AppErrorType.notFound;
    }

    if (error is LocationServiceDisabledException ||
        error is PermissionDeniedException) {
      return AppErrorType.permission;
    }

    if (error is DatabaseException ||
        error.toString().contains('database') ||
        error.toString().contains('sqlite')) {
      return AppErrorType.database;
    }

    if (error.toString().contains('network') ||
        error.toString().contains('connection') ||
        error.toString().contains('timeout')) {
      return AppErrorType.network;
    }

    if (error is TimeoutException) {
      return AppErrorType.timeout;
    }

    return AppErrorType.unknown;
  }

  /// Extract user-friendly error message
  static String getErrorMessage(Object error) {
    // Custom exceptions with message property
    if (error is TripNotFoundException) {
      return error.message;
    }

    // Location service exceptions
    if (error is LocationServiceDisabledException) {
      return 'Location services are disabled. Please enable them in settings.';
    }

    if (error is PermissionDeniedException) {
      return 'Location permission denied. Please grant permission in settings.';
    }

    if (error is PermissionRequestInProgressException) {
      return 'Permission request is already in progress.';
    }

    // Database exceptions
    if (error is DatabaseException) {
      return 'Database error: ${error.toString()}';
    }

    // Generic error message
    final errorStr = error.toString();

    // Remove "Exception: " prefix if present
    if (errorStr.startsWith('Exception: ')) {
      return errorStr.substring('Exception: '.length);
    }

    return errorStr;
  }

  /// Get user-friendly title for error type
  static String getErrorTitle(AppErrorType type) {
    switch (type) {
      case AppErrorType.notFound:
        return 'Not Found';
      case AppErrorType.network:
        return 'Connection Error';
      case AppErrorType.permission:
        return 'Permission Required';
      case AppErrorType.database:
        return 'Database Error';
      case AppErrorType.timeout:
        return 'Request Timeout';
      case AppErrorType.unknown:
        return 'Error';
    }
  }

  /// Convert error to ErrorView type
  static ErrorType toErrorViewType(AppErrorType type) {
    switch (type) {
      case AppErrorType.notFound:
        return ErrorType.notFound;
      case AppErrorType.network:
      case AppErrorType.timeout:
        return ErrorType.network;
      case AppErrorType.permission:
        return ErrorType.permission;
      case AppErrorType.database:
        return ErrorType.database;
      case AppErrorType.unknown:
        return ErrorType.unknown;
    }
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => message;
}
```

**Usage**:
```dart
try {
  await someOperation();
} catch (e) {
  final errorType = ErrorHandler.classifyError(e);
  final message = ErrorHandler.getErrorMessage(e);
  final title = ErrorHandler.getErrorTitle(errorType);

  // Show error to user
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}
```

#### 2.2 AsyncValue Extensions

**File**: `lib/core/extensions/async_value_extensions.dart`

**Purpose**: Helper methods for common AsyncValue patterns

**Implementation**:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:autoride/core/utils/error_handler.dart';
import 'package:autoride/shared/widgets/error_view.dart';

extension AsyncValueExtensions<T> on AsyncValue<T> {
  /// Get user-friendly error message
  String? get errorMessage {
    return whenOrNull(
      error: (error, stackTrace) => ErrorHandler.getErrorMessage(error),
    );
  }

  /// Get error type
  AppErrorType? get errorType {
    return whenOrNull(
      error: (error, stackTrace) => ErrorHandler.classifyError(error),
    );
  }

  /// Get ErrorView type
  ErrorType? get errorViewType {
    final type = errorType;
    if (type == null) return null;
    return ErrorHandler.toErrorViewType(type);
  }

  /// Check if has data (even if loading or error)
  bool get hasData => hasValue && value != null;

  /// Get data or null (even if error/loading)
  T? get dataOrNull => hasValue ? value : null;

  /// Build ErrorView for this AsyncValue
  ErrorView? buildErrorView({VoidCallback? onRetry}) {
    return whenOrNull(
      error: (error, stackTrace) {
        final type = ErrorHandler.classifyError(error);
        final message = ErrorHandler.getErrorMessage(error);
        final title = ErrorHandler.getErrorTitle(type);
        final errorViewType = ErrorHandler.toErrorViewType(type);

        return ErrorView(
          type: errorViewType,
          title: title,
          message: message,
          onRetry: onRetry,
        );
      },
    );
  }
}
```

**Usage**:
```dart
// In a widget
final tripsAsync = ref.watch(tripsProvider);

// Simple error message extraction
if (tripsAsync.hasError) {
  print('Error: ${tripsAsync.errorMessage}');
}

// Build ErrorView directly from AsyncValue
return tripsAsync.when(
  data: (trips) => TripsList(trips: trips),
  loading: () => const LoadingView(),
  error: (error, stack) => tripsAsync.buildErrorView(
    onRetry: () => ref.refresh(tripsProvider),
  )!,
);

// Or use simplified pattern
return tripsAsync.buildErrorView(
  onRetry: () => ref.refresh(tripsProvider),
) ?? (tripsAsync.isLoading
    ? const LoadingView()
    : TripsList(trips: tripsAsync.value!));
```

---

### Phase 3: Fix Existing Gaps (20 min)

#### 3.1 Fix Data Management Section Error Handling

**File**: `lib/features/settings/presentation/widgets/data_management_section.dart`

**Current Issues**:
- Line 40-41: `deleteAllTrips()` has no error handling
- Line 69: `resetToDefaults()` has no error handling

**Changes Required**:

**Before (Line 40-41)**:
```dart
final repository = await ref.read(tripRepositoryProvider.future);
await repository.deleteAllTrips();
```

**After**:
```dart
try {
  final repository = await ref.read(tripRepositoryProvider.future);
  await repository.deleteAllTrips();

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All trips deleted'),
        backgroundColor: AppColors.success,
      ),
    );
  }
} catch (e) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Failed to delete trips: ${ErrorHandler.getErrorMessage(e)}'),
        backgroundColor: AppColors.error,
      ),
    );
  }
}
```

**Before (Line 69)**:
```dart
await ref.read(settingsServiceProvider.notifier).resetToDefaults();
```

**After**:
```dart
try {
  await ref.read(settingsServiceProvider.notifier).resetToDefaults();

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Settings reset to defaults'),
        backgroundColor: AppColors.success,
      ),
    );
  }
} catch (e) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Failed to reset settings: ${ErrorHandler.getErrorMessage(e)}'),
        backgroundColor: AppColors.error,
      ),
    );
  }
}
```

**Additional Import Required**:
```dart
import 'package:autoride/core/utils/error_handler.dart';
```

#### 3.2 Standardize Retry Patterns

**Document Standard Approach** in CLAUDE.md (lessons learned section):

```markdown
### Best Practice: Standardized Retry Patterns

**Problem**: Inconsistent retry mechanisms across providers caused confusion.

**Solutions**:
- **For screens**: Use `ref.refresh(provider)` for simple data refresh
- **For providers with custom refresh**: Use `ref.read(provider.notifier).refresh()`
- **For invalidation**: Use `ref.invalidate(provider)` only when you want to reset state completely

**Standard Pattern**:
```dart
// In widgets - simple refresh
ErrorView(
  message: 'Failed to load data',
  onRetry: () => ref.refresh(dataProvider),
)

// In widgets - provider with custom refresh method
ErrorView(
  message: 'Failed to load data',
  onRetry: () => ref.read(dataProvider.notifier).refresh(),
)
```

**Key Rule**: Use `ref.refresh()` by default unless the provider has a custom `refresh()` method.
```

---

### Phase 4: Refactor Existing Screens (25 min)

#### 4.1 Trip History Screen

**File**: `lib/features/trip_history/presentation/screens/trip_history_screen.dart`

**Current Error UI (Lines 48-68)** - REPLACE:
```dart
error: (error, stackTrace) => Center(
  child: Padding(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.error_outline,
          size: 64,
          color: AppColors.error,
        ),
        // ... more duplicated code
      ],
    ),
  ),
),
```

**With**:
```dart
error: (error, stackTrace) => ErrorView.generic(
  message: ErrorHandler.getErrorMessage(error),
  onRetry: () => ref.read(tripHistoryProvider.notifier).refresh(),
),
```

**Current Loading UI (Line 47)** - KEEP AS IS:
```dart
loading: () => const Center(child: CircularProgressIndicator()),
```

**Optional Enhancement** - could change to:
```dart
loading: () => const LoadingView.fullScreen(message: 'Loading trips...'),
```

**Add Import**:
```dart
import 'package:autoride/shared/widgets/error_view.dart';
import 'package:autoride/shared/widgets/loading_view.dart';
import 'package:autoride/core/utils/error_handler.dart';
```

#### 4.2 Trip Detail Screen

**File**: `lib/features/trip_history/presentation/screens/trip_detail_screen.dart`

**Current Error UI (Lines 51-95)** - REPLACE with custom handling for TripNotFoundException:

```dart
error: (error, stackTrace) {
  // Special handling for TripNotFoundException
  if (error is TripNotFoundException) {
    return ErrorView.notFound(
      title: 'Trip Not Found',
      message: error.message,
      onRetry: () => Navigator.of(context).pop(),
    );
  }

  // Generic error with retry
  return ErrorView.generic(
    message: ErrorHandler.getErrorMessage(error),
    onRetry: () => ref.refresh(tripDetailProvider(tripId)),
  );
},
```

**Current Loading UI (Line 50)** - REPLACE:
```dart
loading: () => const Center(child: CircularProgressIndicator()),
```

**With**:
```dart
loading: () => const LoadingView.fullScreen(message: 'Loading trip details...'),
```

**Add Imports**:
```dart
import 'package:autoride/shared/widgets/error_view.dart';
import 'package:autoride/shared/widgets/loading_view.dart';
import 'package:autoride/core/utils/error_handler.dart';
import 'package:autoride/features/trip_history/domain/exceptions/trip_not_found_exception.dart';
```

#### 4.3 Settings Screen

**File**: `lib/features/settings/presentation/screens/settings_screen.dart`

**Current Loading/Error (Lines 48-55)** - REPLACE:

```dart
body: settingsAsync.when(
  data: (settings) => _buildSettingsBody(context, ref, settings),
  loading: () => Center(child: CircularProgressIndicator()),
  error: (error, stack) => Center(
    child: Text('Failed to load settings: $error'),
  ),
),
```

**With**:
```dart
body: settingsAsync.when(
  data: (settings) => _buildSettingsBody(context, ref, settings),
  loading: () => const LoadingView.fullScreen(message: 'Loading settings...'),
  error: (error, stack) => ErrorView.generic(
    message: ErrorHandler.getErrorMessage(error),
    onRetry: () => ref.refresh(settingsServiceProvider),
  ),
),
```

**Add Imports**:
```dart
import 'package:autoride/shared/widgets/error_view.dart';
import 'package:autoride/shared/widgets/loading_view.dart';
import 'package:autoride/core/utils/error_handler.dart';
```

#### 4.4 Trip Tracking Screen

**File**: `lib/features/trip_detection/presentation/screens/trip_tracking_screen.dart`

**Map Loading State (Line 184)** - REPLACE:
```dart
loading: () => const Center(child: CircularProgressIndicator()),
```

**With**:
```dart
loading: () => const LoadingView.inline(message: 'Loading map...'),
```

**Map Error State (Lines 185-187)** - REPLACE:
```dart
error: (error, stack) => Center(
  child: Text('Map error: $error'),
),
```

**With**:
```dart
error: (error, stack) => ErrorView.generic(
  message: 'Failed to load map: ${ErrorHandler.getErrorMessage(error)}',
),
```

**Metrics Loading State (Line 227)** - REPLACE:
```dart
loading: () => const Center(child: CircularProgressIndicator()),
```

**With**:
```dart
loading: () => const LoadingView.inline(message: 'Loading metrics...'),
```

**Metrics Error State (Lines 228-230)** - REPLACE:
```dart
error: (error, stack) => Center(
  child: Text('Error: $error'),
),
```

**With**:
```dart
error: (error, stack) => Padding(
  padding: const EdgeInsets.all(AppSpacing.md),
  child: ErrorView.generic(
    message: ErrorHandler.getErrorMessage(error),
    onRetry: () => ref.refresh(tripRecorderServiceProvider),
  ),
),
```

**Add Imports**:
```dart
import 'package:autoride/shared/widgets/error_view.dart';
import 'package:autoride/shared/widgets/loading_view.dart';
import 'package:autoride/core/utils/error_handler.dart';
```

---

## Testing Requirements

### Quality Gates

Run these in order:

```bash
# 1. Code generation (if needed)
flutter pub run build_runner build --delete-conflicting-outputs

# 2. Static analysis (MUST pass)
flutter analyze

# 3. Run on physical device
flutter run --release
```

### Manual Testing Checklist

**ErrorView Widget**:
- [ ] Generic error displays correctly
- [ ] Not found error displays correctly
- [ ] Network error displays correctly
- [ ] Permission error displays correctly
- [ ] Database error displays correctly
- [ ] Retry button works when provided
- [ ] Retry button hidden when not provided
- [ ] Error displays correctly in light theme
- [ ] Error displays correctly in dark theme

**LoadingView Widget**:
- [ ] Full-screen loading displays correctly
- [ ] Inline loading displays correctly
- [ ] Loading with message displays correctly
- [ ] Loading without message displays correctly
- [ ] Loading displays correctly in light theme
- [ ] Loading displays correctly in dark theme

**Error Handling**:
- [ ] Data management delete all trips shows error on failure
- [ ] Data management reset settings shows error on failure
- [ ] All screens show ErrorView instead of old error UI
- [ ] All error messages are user-friendly
- [ ] Retry buttons work correctly

**Screen Updates**:
- [ ] Trip History Screen uses ErrorView
- [ ] Trip Detail Screen uses ErrorView (special handling for not found)
- [ ] Settings Screen uses new widgets
- [ ] Trip Tracking Screen uses new widgets
- [ ] All loading states show LoadingView

**Theme Testing**:
- [ ] All new widgets render correctly in light theme
- [ ] All new widgets render correctly in dark theme
- [ ] Colors are accessible (WCAG AA)

**Performance**:
- [ ] No performance degradation
- [ ] Loading states don't flicker
- [ ] Smooth transitions

### Widget Tests (Optional)

**ErrorView Tests**:
```dart
testWidgets('ErrorView displays error message and retry button', (tester) async {
  var retryPressed = false;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ErrorView.generic(
          message: 'Test error message',
          onRetry: () => retryPressed = true,
        ),
      ),
    ),
  );

  expect(find.text('Test error message'), findsOneWidget);
  expect(find.byType(ElevatedButton), findsOneWidget);

  await tester.tap(find.byType(ElevatedButton));
  expect(retryPressed, true);
});
```

**LoadingView Tests**:
```dart
testWidgets('LoadingView displays message', (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: LoadingView(message: 'Loading...'),
      ),
    ),
  );

  expect(find.text('Loading...'), findsOneWidget);
  expect(find.byType(CircularProgressIndicator), findsOneWidget);
});
```

---

## Implementation Checklist

### Phase 1: Reusable Widgets
- [ ] Create ErrorView widget (lib/shared/widgets/error_view.dart)
- [ ] Create LoadingView widget (lib/shared/widgets/loading_view.dart)
- [ ] Test widgets in isolation

### Phase 2: Utilities
- [ ] Create ErrorHandler utility (lib/core/utils/error_handler.dart)
- [ ] Create AsyncValue extensions (lib/core/extensions/async_value_extensions.dart)
- [ ] Test error classification logic

### Phase 3: Fix Gaps
- [ ] Fix data_management_section.dart error handling
- [ ] Add error feedback for deleteAllTrips()
- [ ] Add error feedback for resetToDefaults()
- [ ] Document retry pattern standard in CLAUDE.md

### Phase 4: Refactor Screens
- [ ] Update Trip History Screen
- [ ] Update Trip Detail Screen
- [ ] Update Settings Screen
- [ ] Update Trip Tracking Screen
- [ ] Verify all imports are correct

### Phase 5: Testing
- [ ] Run flutter analyze (0 warnings)
- [ ] Test all error types
- [ ] Test all loading states
- [ ] Test retry functionality
- [ ] Test in both themes
- [ ] Test on physical device

### Phase 6: Completion
- [ ] Update TASKS.md to mark T026 complete
- [ ] Update progress summary
- [ ] Commit changes with task ID

---

## Expected Outcome

After completing this task:

✅ **Reusable Components**:
- ErrorView widget handles all error display needs
- LoadingView widget provides consistent loading UI
- No more duplicated error/loading code

✅ **Error Handling**:
- All async operations have error handling
- User receives clear feedback for all errors
- Errors are classified and displayed appropriately
- User-friendly error messages

✅ **Consistent UX**:
- All screens use the same error/loading patterns
- Retry functionality works consistently
- Theme-aware error and loading states

✅ **Code Quality**:
- Eliminated code duplication
- Centralized error handling logic
- Standardized retry patterns
- Better maintainability

---

## Common Pitfalls to Avoid

**From CLAUDE.md Lessons Learned**:

1. ⚠️ **Mistake #2**: Use `Ref ref`, not specific ref types
2. ⚠️ **Mistake #3**: Run `flutter analyze` to catch unused imports
3. ⚠️ **Best Practice**: Use `const` constructors where possible
4. ⚠️ **Context Safety**: Always check `context.mounted` before showing snackbars
5. ⚠️ **Error Messages**: Extract error messages properly, don't just `.toString()`
6. ⚠️ **Retry Logic**: Use standardized retry pattern (ref.refresh by default)

---

## Resources

**Existing Code References**:
- EmptyState widget: `lib/shared/widgets/empty_state.dart`
- Trip History Screen: `lib/features/trip_history/presentation/screens/trip_history_screen.dart`
- Settings providers: `lib/features/settings/data/services/settings_service.dart`
- Theme system: `lib/core/theme/`

**Flutter Documentation**:
- [AsyncValue](https://pub.dev/documentation/riverpod/latest/riverpod/AsyncValue-class.html)
- [Error Handling](https://dart.dev/guides/libraries/futures-error-handling)
- [Material Design - Error States](https://material.io/design/communication/empty-states.html#error-states)

---

## Definition of Done

- [ ] ErrorView widget created and working
- [ ] LoadingView widget created and working
- [ ] ErrorHandler utility created
- [ ] AsyncValue extensions created
- [ ] Data management error handling fixed
- [ ] All screens refactored to use new widgets
- [ ] Flutter analyze passes (0 warnings)
- [ ] Manual testing completed
- [ ] Both themes tested
- [ ] No unused imports or variables
- [ ] Documentation updated in TASKS.md
- [ ] Retry pattern documented in CLAUDE.md

---

## Time Tracking

- **Estimated**: 2 hours
- **Breakdown**:
  - Reusable widgets: 45 min
  - Error utilities: 30 min
  - Fix gaps: 20 min
  - Refactor screens: 25 min

---

**Created**: 2025-11-23
**Last Updated**: 2025-11-23
**Status**: In Progress
**Dependencies**: T020 ✅
**Assigned**: Claude Code
