# T020: App Theme & Design System

**Phase**: Phase 6 - User Interface
**Dependencies**: T001 (Project Setup)
**Estimate**: 2-3 hours
**Status**: ⏳ In Progress

---

## Overview

Establish the visual foundation for AutoRide by creating a comprehensive theme and design system. This includes color schemes (light/dark), typography, spacing, and reusable UI components that ensure visual consistency throughout the app.

**Goal**: Create a polished, modern design system that supports both light and dark themes with excellent accessibility and a cycling/sports aesthetic.

---

## Objectives

1. ✅ Define color palettes for light and dark themes
2. ✅ Configure typography system with proper text styles
3. ✅ Create spacing and sizing constants
4. ✅ Implement reusable widget components
5. ✅ Set up theme data in Riverpod provider
6. ✅ Add theme switching functionality

---

## Design Decisions

### Color Palette Strategy

**Primary Color**: Cycling-oriented, energetic blue/teal
- Represents motion, technology, outdoor activity
- Good contrast for visibility during cycling
- Professional and modern

**Secondary Color**: Complementary accent (orange/amber)
- Highlights important actions (start/stop trip)
- High visibility for safety-critical elements
- Energetic, action-oriented

**Semantic Colors**:
- Success: Green (trip completed, goals achieved)
- Warning: Amber (battery low, permission issues)
- Error: Red (GPS loss, critical errors)
- Info: Blue (tips, informational messages)

### Typography

**Font Family**: System fonts for performance
- iOS: SF Pro Display/Text
- Android: Roboto
- Fallback: Platform default

**Text Styles**:
- Display: Large headings (trip stats)
- Headline: Section titles
- Title: Card headers
- Body: Regular content
- Label: Small text, captions

### Spacing System

**8-point grid system**:
- 4px (0.5x): Minimal spacing
- 8px (1x): Tight spacing
- 16px (2x): Standard spacing
- 24px (3x): Medium spacing
- 32px (4x): Large spacing
- 48px (6x): Extra large spacing

---

## Implementation Plan

### Step 1: Color Definitions

**File**: `lib/core/theme/app_colors.dart`

```dart
import 'package:flutter/material.dart';

/// App color palette for light and dark themes
class AppColors {
  AppColors._();

  // Primary Colors
  static const Color primaryLight = Color(0xFF0277BD); // Light Blue 800
  static const Color primaryDark = Color(0xFF29B6F6);  // Light Blue 400

  static const Color secondaryLight = Color(0xFFFF6F00); // Orange 900
  static const Color secondaryDark = Color(0xFFFFB74D);  // Orange 300

  // Background Colors
  static const Color backgroundLight = Color(0xFFFAFAFA);
  static const Color backgroundDark = Color(0xFF121212);

  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1E1E1E);

  // Text Colors
  static const Color textPrimaryLight = Color(0xFF212121);
  static const Color textPrimaryDark = Color(0xFFE0E0E0);

  static const Color textSecondaryLight = Color(0xFF757575);
  static const Color textSecondaryDark = Color(0xFFBDBDBD);

  // Semantic Colors
  static const Color success = Color(0xFF4CAF50); // Green 500
  static const Color warning = Color(0xFFFFA726); // Orange 400
  static const Color error = Color(0xFFE53935);   // Red 600
  static const Color info = Color(0xFF42A5F5);    // Blue 400

  // Trip Status Colors
  static const Color tripActive = Color(0xFF4CAF50);   // Green - active trip
  static const Color tripPaused = Color(0xFFFFA726);   // Orange - paused
  static const Color tripDetecting = Color(0xFF42A5F5); // Blue - detecting

  // Gradient Colors (for stats displays)
  static const List<Color> speedGradient = [
    Color(0xFF0277BD),
    Color(0xFF29B6F6),
  ];

  static const List<Color> distanceGradient = [
    Color(0xFFFF6F00),
    Color(0xFFFFB74D),
  ];
}
```

### Step 2: Typography

**File**: `lib/core/theme/app_text_styles.dart`

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography styles for the app
class AppTextStyles {
  AppTextStyles._();

  // Display - Large headings (trip stats)
  static TextStyle displayLarge = GoogleFonts.roboto(
    fontSize: 57,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.25,
  );

  static TextStyle displayMedium = GoogleFonts.roboto(
    fontSize: 45,
    fontWeight: FontWeight.w400,
  );

  static TextStyle displaySmall = GoogleFonts.roboto(
    fontSize: 36,
    fontWeight: FontWeight.w400,
  );

  // Headline - Section titles
  static TextStyle headlineLarge = GoogleFonts.roboto(
    fontSize: 32,
    fontWeight: FontWeight.w400,
  );

  static TextStyle headlineMedium = GoogleFonts.roboto(
    fontSize: 28,
    fontWeight: FontWeight.w400,
  );

  static TextStyle headlineSmall = GoogleFonts.roboto(
    fontSize: 24,
    fontWeight: FontWeight.w400,
  );

  // Title - Card headers, dialog titles
  static TextStyle titleLarge = GoogleFonts.roboto(
    fontSize: 22,
    fontWeight: FontWeight.w400,
  );

  static TextStyle titleMedium = GoogleFonts.roboto(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.15,
  );

  static TextStyle titleSmall = GoogleFonts.roboto(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  // Body - Regular content
  static TextStyle bodyLarge = GoogleFonts.roboto(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.5,
  );

  static TextStyle bodyMedium = GoogleFonts.roboto(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.25,
  );

  static TextStyle bodySmall = GoogleFonts.roboto(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.4,
  );

  // Label - Small text, captions
  static TextStyle labelLarge = GoogleFonts.roboto(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  static TextStyle labelMedium = GoogleFonts.roboto(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
  );

  static TextStyle labelSmall = GoogleFonts.roboto(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
  );
}
```

### Step 3: Spacing Constants

**File**: `lib/core/theme/app_spacing.dart`

```dart
/// Spacing constants using 8-point grid system
class AppSpacing {
  AppSpacing._();

  // Base unit: 8px
  static const double xs = 4.0;   // 0.5x - Minimal spacing
  static const double sm = 8.0;   // 1x - Tight spacing
  static const double md = 16.0;  // 2x - Standard spacing
  static const double lg = 24.0;  // 3x - Medium spacing
  static const double xl = 32.0;  // 4x - Large spacing
  static const double xxl = 48.0; // 6x - Extra large spacing

  // Common padding values
  static const double screenPadding = md;
  static const double cardPadding = md;
  static const double buttonPadding = sm;

  // Border radius
  static const double radiusSm = 4.0;
  static const double radiusMd = 8.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;

  // Icon sizes
  static const double iconSm = 16.0;
  static const double iconMd = 24.0;
  static const double iconLg = 32.0;
  static const double iconXl = 48.0;
}
```

### Step 4: Theme Configuration

**File**: `lib/core/theme/app_theme.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';
import 'app_spacing.dart';

class AppTheme {
  AppTheme._();

  /// Light theme configuration
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,

    // Color Scheme
    colorScheme: ColorScheme.light(
      primary: AppColors.primaryLight,
      secondary: AppColors.secondaryLight,
      surface: AppColors.surfaceLight,
      background: AppColors.backgroundLight,
      error: AppColors.error,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: AppColors.textPrimaryLight,
      onBackground: AppColors.textPrimaryLight,
      onError: Colors.white,
    ),

    // App Bar Theme
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.primaryLight,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: AppTextStyles.titleLarge.copyWith(color: Colors.white),
    ),

    // Card Theme
    cardTheme: CardTheme(
      color: AppColors.surfaceLight,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      margin: const EdgeInsets.all(AppSpacing.sm),
    ),

    // Elevated Button Theme
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryLight,
        foregroundColor: Colors.white,
        elevation: 2,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        textStyle: AppTextStyles.labelLarge,
      ),
    ),

    // Text Button Theme
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primaryLight,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        textStyle: AppTextStyles.labelLarge,
      ),
    ),

    // Icon Theme
    iconTheme: const IconThemeData(
      color: AppColors.primaryLight,
      size: AppSpacing.iconMd,
    ),

    // Input Decoration Theme
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: const BorderSide(color: Colors.grey),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: const BorderSide(color: AppColors.primaryLight, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      contentPadding: const EdgeInsets.all(AppSpacing.md),
    ),

    // Floating Action Button Theme
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.secondaryLight,
      foregroundColor: Colors.white,
      elevation: 4,
    ),

    // Text Theme
    textTheme: TextTheme(
      displayLarge: AppTextStyles.displayLarge,
      displayMedium: AppTextStyles.displayMedium,
      displaySmall: AppTextStyles.displaySmall,
      headlineLarge: AppTextStyles.headlineLarge,
      headlineMedium: AppTextStyles.headlineMedium,
      headlineSmall: AppTextStyles.headlineSmall,
      titleLarge: AppTextStyles.titleLarge,
      titleMedium: AppTextStyles.titleMedium,
      titleSmall: AppTextStyles.titleSmall,
      bodyLarge: AppTextStyles.bodyLarge,
      bodyMedium: AppTextStyles.bodyMedium,
      bodySmall: AppTextStyles.bodySmall,
      labelLarge: AppTextStyles.labelLarge,
      labelMedium: AppTextStyles.labelMedium,
      labelSmall: AppTextStyles.labelSmall,
    ),
  );

  /// Dark theme configuration
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,

    // Color Scheme
    colorScheme: ColorScheme.dark(
      primary: AppColors.primaryDark,
      secondary: AppColors.secondaryDark,
      surface: AppColors.surfaceDark,
      background: AppColors.backgroundDark,
      error: AppColors.error,
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onSurface: AppColors.textPrimaryDark,
      onBackground: AppColors.textPrimaryDark,
      onError: Colors.white,
    ),

    // App Bar Theme
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surfaceDark,
      foregroundColor: AppColors.textPrimaryDark,
      elevation: 0,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      titleTextStyle: AppTextStyles.titleLarge.copyWith(
        color: AppColors.textPrimaryDark,
      ),
    ),

    // Card Theme
    cardTheme: CardTheme(
      color: AppColors.surfaceDark,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      margin: const EdgeInsets.all(AppSpacing.sm),
    ),

    // Elevated Button Theme
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.black,
        elevation: 2,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        textStyle: AppTextStyles.labelLarge,
      ),
    ),

    // Text Button Theme
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primaryDark,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        textStyle: AppTextStyles.labelLarge,
      ),
    ),

    // Icon Theme
    iconTheme: const IconThemeData(
      color: AppColors.primaryDark,
      size: AppSpacing.iconMd,
    ),

    // Input Decoration Theme
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: const BorderSide(color: Colors.grey),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: BorderSide(color: Colors.grey.shade700),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: const BorderSide(color: AppColors.primaryDark, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      contentPadding: const EdgeInsets.all(AppSpacing.md),
    ),

    // Floating Action Button Theme
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.secondaryDark,
      foregroundColor: Colors.black,
      elevation: 4,
    ),

    // Text Theme
    textTheme: TextTheme(
      displayLarge: AppTextStyles.displayLarge.copyWith(
        color: AppColors.textPrimaryDark,
      ),
      displayMedium: AppTextStyles.displayMedium.copyWith(
        color: AppColors.textPrimaryDark,
      ),
      displaySmall: AppTextStyles.displaySmall.copyWith(
        color: AppColors.textPrimaryDark,
      ),
      headlineLarge: AppTextStyles.headlineLarge.copyWith(
        color: AppColors.textPrimaryDark,
      ),
      headlineMedium: AppTextStyles.headlineMedium.copyWith(
        color: AppColors.textPrimaryDark,
      ),
      headlineSmall: AppTextStyles.headlineSmall.copyWith(
        color: AppColors.textPrimaryDark,
      ),
      titleLarge: AppTextStyles.titleLarge.copyWith(
        color: AppColors.textPrimaryDark,
      ),
      titleMedium: AppTextStyles.titleMedium.copyWith(
        color: AppColors.textPrimaryDark,
      ),
      titleSmall: AppTextStyles.titleSmall.copyWith(
        color: AppColors.textPrimaryDark,
      ),
      bodyLarge: AppTextStyles.bodyLarge.copyWith(
        color: AppColors.textPrimaryDark,
      ),
      bodyMedium: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.textPrimaryDark,
      ),
      bodySmall: AppTextStyles.bodySmall.copyWith(
        color: AppColors.textSecondaryDark,
      ),
      labelLarge: AppTextStyles.labelLarge.copyWith(
        color: AppColors.textPrimaryDark,
      ),
      labelMedium: AppTextStyles.labelMedium.copyWith(
        color: AppColors.textSecondaryDark,
      ),
      labelSmall: AppTextStyles.labelSmall.copyWith(
        color: AppColors.textSecondaryDark,
      ),
    ),
  );
}
```

### Step 5: Theme Provider

**File**: `lib/core/theme/theme_provider.dart`

```dart
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'theme_provider.g.dart';

/// Theme mode provider (light/dark/system)
@riverpod
class ThemeMode extends _$ThemeMode {
  static const String _themeModeKey = 'theme_mode';

  @override
  ThemeMode build() {
    _loadThemeMode();
    return ThemeMode.system;
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(_themeModeKey);

    if (savedMode != null) {
      state = ThemeModeExtension.fromString(savedMode);
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
  }

  Future<void> toggleTheme() async {
    final newMode = state == ThemeMode.light
        ? ThemeMode.dark
        : ThemeMode.light;
    await setThemeMode(newMode);
  }
}

extension ThemeModeExtension on ThemeMode {
  static ThemeMode fromString(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  String get name {
    switch (this) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  String get displayName {
    switch (this) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }

  IconData get icon {
    switch (this) {
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
      case ThemeMode.system:
        return Icons.brightness_auto;
    }
  }
}
```

### Step 6: Shared Widgets

**File**: `lib/shared/widgets/stat_card.dart`

```dart
import 'package:flutter/material.dart';
import '../../core/theme/app_spacing.dart';

/// Reusable card widget for displaying trip statistics
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? iconColor;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: AppSpacing.iconLg,
                color: iconColor ?? theme.colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                value,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

**File**: `lib/shared/widgets/gradient_container.dart`

```dart
import 'package:flutter/material.dart';

/// Container with gradient background for highlighting important content
class GradientContainer extends StatelessWidget {
  final Widget child;
  final List<Color> colors;
  final AlignmentGeometry begin;
  final AlignmentGeometry end;
  final BorderRadius? borderRadius;

  const GradientContainer({
    super.key,
    required this.child,
    required this.colors,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: begin,
          end: end,
        ),
        borderRadius: borderRadius,
      ),
      child: child,
    );
  }
}
```

**File**: `lib/shared/widgets/status_badge.dart`

```dart
import 'package:flutter/material.dart';
import '../../core/theme/app_spacing.dart';

/// Status badge for displaying trip state (active/paused/detecting)
class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppSpacing.iconSm, color: color),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
```

**File**: `lib/shared/widgets/empty_state.dart`

```dart
import 'package:flutter/material.dart';
import '../../core/theme/app_spacing.dart';

/// Widget for displaying empty states with icon and message
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: AppSpacing.iconXl * 2,
              color: theme.colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                subtitle!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.textTheme.bodySmall?.color,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
```

---

## Testing Strategy

### Visual Testing

1. **Theme Switching**:
   - Test light theme appearance
   - Test dark theme appearance
   - Test system theme following OS setting
   - Verify smooth transitions

2. **Component Testing**:
   - Verify StatCard displays correctly
   - Test GradientContainer with different colors
   - Validate StatusBadge appearance
   - Check EmptyState layout

3. **Accessibility**:
   - Verify contrast ratios (WCAG AA minimum)
   - Test text scaling (up to 200%)
   - Check touch target sizes (minimum 44x44)

### Manual Testing Checklist

- [ ] Light theme loads correctly
- [ ] Dark theme loads correctly
- [ ] Theme persists across app restarts
- [ ] All colors are accessible (contrast ratio >4.5:1)
- [ ] Typography is readable at all sizes
- [ ] Spacing is consistent throughout
- [ ] Shared widgets render correctly
- [ ] Theme switching is smooth (no flicker)

---

## Quality Gates

### Before Completion

1. **Code Generation**:
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

2. **Static Analysis**:
   ```bash
   flutter analyze  # Must pass with no errors
   ```

3. **Visual Inspection**:
   - Create simple test screen with all widgets
   - Test on both light and dark themes
   - Verify on different screen sizes

4. **Documentation**:
   - Add inline documentation to theme files
   - Document color choices and accessibility
   - Create usage examples for shared widgets

---

## Dependencies Added

Add to `pubspec.yaml`:

```yaml
dependencies:
  google_fonts: ^6.1.0  # Typography (Roboto)

  # Already included from previous tasks:
  # flutter:
  # shared_preferences: (from T011)
  # riverpod_annotation: (from T003)
```

Run:
```bash
flutter pub get
```

---

## Files Created

**Theme Files**:
- `lib/core/theme/app_colors.dart`
- `lib/core/theme/app_text_styles.dart`
- `lib/core/theme/app_spacing.dart`
- `lib/core/theme/app_theme.dart`
- `lib/core/theme/theme_provider.dart`
- `lib/core/theme/theme_provider.g.dart` (generated)

**Shared Widgets**:
- `lib/shared/widgets/stat_card.dart`
- `lib/shared/widgets/gradient_container.dart`
- `lib/shared/widgets/status_badge.dart`
- `lib/shared/widgets/empty_state.dart`

---

## Integration with Main App

Update `lib/main.dart` to use theme:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';

void main() {
  runApp(
    const ProviderScope(
      child: AutoRideApp(),
    ),
  );
}

class AutoRideApp extends ConsumerWidget {
  const AutoRideApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'AutoRide',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const Scaffold(
        body: Center(
          child: Text('AutoRide - Theme Ready'),
        ),
      ),
    );
  }
}
```

---

## Success Criteria

- ✅ Light and dark themes defined with consistent color scheme
- ✅ Typography system implemented with proper text styles
- ✅ Spacing system follows 8-point grid
- ✅ Theme switching works and persists
- ✅ Shared widgets created and reusable
- ✅ All components accessible (WCAG AA)
- ✅ Code passes `flutter analyze`
- ✅ Visual inspection confirms polished appearance

---

## Next Steps

After completing T020:
1. Update task status in `tasks/TASKS.md` to ✅
2. Move to **T021**: Onboarding Flow (will use theme system)

---

**Created**: 2025-11-22
**Last Updated**: 2025-11-22
