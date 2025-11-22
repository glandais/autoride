# T021: Onboarding Flow

**Phase**: Phase 6 - User Interface
**Dependencies**: T020 (App Theme & Design System)
**Estimate**: 3-4 hours
**Status**: ⏳ In Progress

---

## Overview

Create a comprehensive first-launch onboarding experience that introduces new users to AutoRide, explains key features, and requests necessary permissions with clear rationale. The onboarding flow follows a progressive disclosure pattern, building user understanding before requesting permissions.

**Goal**: Create an intuitive onboarding experience that educates users, requests permissions properly, and sets up the app for successful first use while following platform-specific permission patterns.

---

## Objectives

1. ☐ Create welcome screens introducing the app
2. ☐ Implement progressive permission requests (foreground → background)
3. ☐ Build onboarding state management with Riverpod
4. ☐ Add first-launch detection and persistence
5. ☐ Create reusable onboarding widgets
6. ☐ Handle permission denial flows gracefully
7. ☐ Integrate with existing theme system
8. ☐ Allow skipping optional steps

---

## Design Decisions

### Progressive Permission Pattern

**Why Progressive?**
- Users need context before granting permissions
- Platform best practices (Android 10+, iOS 14+) require education
- Trust building through transparency
- Higher acceptance rates when rationale is clear

**Flow Strategy**:
1. **Welcome** → Introduce app value proposition
2. **Features** → Explain automatic detection and battery optimization
3. **Foreground Permission** → Request "While Using" with rationale
4. **Background Permission** → Request "Always" for automatic tracking
5. **Setup Complete** → Confirm ready state, provide encouragement

### Platform-Specific Considerations

**Android 10+ Requirements**:
- Two-step permission request (foreground → background)
- Background permission requires system settings dialog
- Must provide clear rationale before requesting
- "Deny" vs "Deny Forever" handling

**iOS 14+ Requirements**:
- "Allow Once" vs "While Using" vs "Always" options
- Background permission shown in separate prompt
- User can change permissions later in Settings
- Must handle all permission states gracefully

### User Experience Principles

1. **Education First**: Explain features before requesting permissions
2. **Transparency**: Clear rationale for each permission
3. **Control**: Allow skipping non-critical steps
4. **Progress Feedback**: Show current step and total steps
5. **Encouragement**: Positive messaging on completion

---

## Technical Specification

### Architecture

```
lib/features/onboarding/
├── domain/
│   └── models/
│       └── onboarding_state.dart          # Freezed model
├── data/
│   └── services/
│       └── onboarding_service.dart        # First-launch detection
└── presentation/
    ├── providers/
    │   └── onboarding_provider.dart       # State management
    ├── screens/
    │   ├── welcome_screen.dart            # Screen 1: Welcome
    │   ├── features_screen.dart           # Screen 2: Key features
    │   ├── location_permission_screen.dart # Screen 3: Foreground
    │   ├── background_permission_screen.dart # Screen 4: Background
    │   └── setup_complete_screen.dart     # Screen 5: Success
    └── widgets/
        ├── onboarding_page_indicator.dart # Progress dots
        └── onboarding_action_button.dart  # Styled CTA button
```

### Data Models

**OnboardingState** (Freezed):
```dart
sealed class OnboardingState {
  int currentPage;
  bool locationPermissionGranted;
  bool backgroundPermissionGranted;
  bool isComplete;
  bool canProceed;
}
```

**OnboardingStep** (Enum):
```dart
enum OnboardingStep {
  welcome,
  features,
  locationPermission,
  backgroundPermission,
  complete,
}
```

### Constants to Add

Add to `lib/core/constants/app_constants.dart`:
```dart
// Onboarding
static const String onboardingCompleteKey = 'onboarding_complete';
static const int onboardingPageCount = 5;
static const Duration onboardingAnimationDuration = Duration(milliseconds: 300);
```

---

## Implementation Steps

### Step 1: Domain Layer - OnboardingState Model

**File**: `lib/features/onboarding/domain/models/onboarding_state.dart`

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'onboarding_state.freezed.dart';

@freezed
sealed class OnboardingState with _$OnboardingState {
  const OnboardingState._();

  const factory OnboardingState({
    @Default(0) int currentPage,
    @Default(false) bool locationPermissionGranted,
    @Default(false) bool backgroundPermissionGranted,
    @Default(false) bool isComplete,
  }) = _OnboardingState;

  factory OnboardingState.initial() => const OnboardingState();
}

extension OnboardingStateExtensions on OnboardingState {
  bool get canProceedToNext {
    // Can always proceed from welcome and features
    if (currentPage < 2) return true;

    // Must have location permission to proceed from location screen
    if (currentPage == 2) return locationPermissionGranted;

    // Can proceed from background screen even if denied (optional)
    if (currentPage == 3) return true;

    return false;
  }

  bool get isLastPage => currentPage == 4;

  int get totalPages => 5;

  double get progress => (currentPage + 1) / totalPages;
}

enum OnboardingStep {
  welcome(0, 'Welcome'),
  features(1, 'Features'),
  locationPermission(2, 'Location'),
  backgroundPermission(3, 'Background'),
  complete(4, 'Complete');

  const OnboardingStep(this.index, this.label);
  final int index;
  final String label;
}
```

### Step 2: Data Layer - OnboardingService

**File**: `lib/features/onboarding/data/services/onboarding_service.dart`

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_constants.dart';

part 'onboarding_service.g.dart';

@riverpod
class OnboardingService extends _$OnboardingService {
  static const String _key = AppConstants.onboardingCompleteKey;

  @override
  Future<bool> build() async {
    return await isFirstLaunch();
  }

  /// Check if this is the first app launch
  Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    return !prefs.containsKey(_key) || !(prefs.getBool(_key) ?? false);
  }

  /// Mark onboarding as complete
  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
    state = const AsyncValue.data(false);
  }

  /// Reset onboarding (for testing)
  Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    state = const AsyncValue.data(true);
  }
}
```

### Step 3: Update AppConstants

**File**: `lib/core/constants/app_constants.dart`

Add to the AppConstants class:

```dart
// Onboarding Configuration
static const String onboardingCompleteKey = 'onboarding_complete';
static const int onboardingPageCount = 5;
static const Duration onboardingAnimationDuration = Duration(milliseconds: 300);
static const Duration onboardingPageTransitionDuration = Duration(milliseconds: 250);
```

### Step 4: Presentation Layer - OnboardingProvider

**File**: `lib/features/onboarding/presentation/providers/onboarding_provider.dart`

```dart
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/models/onboarding_state.dart';
import '../../data/services/onboarding_service.dart';
import '../../../trip_detection/data/services/location_permission_service.dart';

part 'onboarding_provider.g.dart';

@riverpod
class Onboarding extends _$Onboarding {
  PageController? _pageController;

  @override
  OnboardingState build() {
    _pageController = PageController();
    return OnboardingState.initial();
  }

  PageController get pageController => _pageController!;

  void dispose() {
    _pageController?.dispose();
  }

  /// Navigate to next page
  Future<void> nextPage() async {
    if (state.isLastPage) {
      await completeOnboarding();
      return;
    }

    final nextPage = state.currentPage + 1;
    await _pageController?.animateToPage(
      nextPage,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    state = state.copyWith(currentPage: nextPage);
  }

  /// Navigate to previous page
  Future<void> previousPage() async {
    if (state.currentPage == 0) return;

    final previousPage = state.currentPage - 1;
    await _pageController?.animateToPage(
      previousPage,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    state = state.copyWith(currentPage: previousPage);
  }

  /// Skip to final page
  Future<void> skip() async {
    await _pageController?.animateToPage(
      4, // Final page
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    state = state.copyWith(currentPage: 4);
  }

  /// Request foreground location permission
  Future<void> requestLocationPermission() async {
    final service = ref.read(locationPermissionServiceProvider.notifier);
    final granted = await service.requestPermission();

    state = state.copyWith(locationPermissionGranted: granted);

    if (granted) {
      await nextPage();
    }
  }

  /// Request background location permission
  Future<void> requestBackgroundPermission() async {
    final service = ref.read(locationPermissionServiceProvider.notifier);
    final granted = await service.requestBackgroundPermission();

    state = state.copyWith(backgroundPermissionGranted: granted);

    // Can proceed even if denied (background is optional for manual trips)
    await nextPage();
  }

  /// Complete onboarding flow
  Future<void> completeOnboarding() async {
    state = state.copyWith(isComplete: true);
    await ref.read(onboardingServiceProvider.notifier).completeOnboarding();
  }

  /// Update current page (for PageView listener)
  void updatePage(int page) {
    state = state.copyWith(currentPage: page);
  }
}
```

### Step 5: Screen 1 - Welcome Screen

**File**: `lib/features/onboarding/presentation/screens/welcome_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_action_button.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // App Icon/Logo
          Icon(
            Icons.directions_bike,
            size: 120,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.xl),

          // App Name
          Text(
            'AutoRide',
            style: theme.textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Tagline
          Text(
            'Automatic Trip Detection for Cyclists',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),

          // Value Proposition
          _FeatureHighlight(
            icon: Icons.auto_awesome,
            title: 'Automatic Detection',
            description: 'Detects when you start cycling automatically',
          ),
          const SizedBox(height: AppSpacing.lg),
          _FeatureHighlight(
            icon: Icons.battery_charging_full,
            title: 'Battery Optimized',
            description: 'Smart GPS usage saves your battery',
          ),
          const SizedBox(height: AppSpacing.lg),
          _FeatureHighlight(
            icon: Icons.route,
            title: 'Track Your Routes',
            description: 'Keep a history of all your cycling trips',
          ),

          const Spacer(),

          // Get Started Button
          OnboardingActionButton(
            label: 'Get Started',
            onPressed: () {
              ref.read(onboardingProvider.notifier).nextPage();
            },
          ),
        ],
      ),
    );
  }
}

class _FeatureHighlight extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _FeatureHighlight({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          icon,
          size: AppSpacing.iconLg,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium,
              ),
              Text(
                description,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
```

### Step 6: Screen 2 - Features Screen

**File**: `lib/features/onboarding/presentation/screens/features_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_action_button.dart';

class FeaturesScreen extends ConsumerWidget {
  const FeaturesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.xxl),

          // Title
          Text(
            'How It Works',
            style: theme.textTheme.displaySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),

          // Description
          Text(
            'AutoRide uses motion sensors and GPS to automatically detect when you start cycling',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),

          // Feature Cards
          Expanded(
            child: ListView(
              children: [
                _FeatureCard(
                  icon: Icons.sensors,
                  title: 'Motion Detection',
                  description: 'Detects cycling motion using accelerometer and gyroscope',
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: AppSpacing.md),
                _FeatureCard(
                  icon: Icons.location_on,
                  title: 'Smart GPS',
                  description: 'GPS activates only when motion is detected to save battery',
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(height: AppSpacing.md),
                _FeatureCard(
                  icon: Icons.history,
                  title: 'Trip History',
                  description: 'Automatic recording and storage of your cycling routes',
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(height: AppSpacing.md),
                _FeatureCard(
                  icon: Icons.battery_std,
                  title: 'Battery Friendly',
                  description: 'Adaptive tracking adjusts based on battery level',
                  color: Colors.green,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // Continue Button
          OnboardingActionButton(
            label: 'Continue',
            onPressed: () {
              ref.read(onboardingProvider.notifier).nextPage();
            },
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Icon(
                icon,
                size: AppSpacing.iconLg,
                color: color,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### Step 7: Screen 3 - Location Permission Screen

**File**: `lib/features/onboarding/presentation/screens/location_permission_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_action_button.dart';

class LocationPermissionScreen extends ConsumerWidget {
  const LocationPermissionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(onboardingProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.xxl),

          // Icon
          Icon(
            Icons.location_on,
            size: 100,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.xl),

          // Title
          Text(
            'Location Permission',
            style: theme.textTheme.displaySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),

          // Rationale
          Text(
            'AutoRide needs access to your location to track your cycling routes and calculate trip statistics.',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),

          // Why we need it
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Why we need this:',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ReasonItem(
                    icon: Icons.route,
                    text: 'Record your cycling routes on a map',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _ReasonItem(
                    icon: Icons.speed,
                    text: 'Calculate distance, speed, and duration',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _ReasonItem(
                    icon: Icons.pin_drop,
                    text: 'Mark trip start and end locations',
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // Privacy Note
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.privacy_tip,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Your location data stays on your device. We never share or upload it.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Allow Location Button
          OnboardingActionButton(
            label: state.locationPermissionGranted
                ? 'Location Enabled ✓'
                : 'Allow Location Access',
            onPressed: state.locationPermissionGranted
                ? () => ref.read(onboardingProvider.notifier).nextPage()
                : () => ref.read(onboardingProvider.notifier).requestLocationPermission(),
            icon: state.locationPermissionGranted ? Icons.check : Icons.location_on,
          ),
        ],
      ),
    );
  }
}

class _ReasonItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ReasonItem({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          icon,
          size: AppSpacing.iconMd,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
```

### Step 8: Screen 4 - Background Permission Screen

**File**: `lib/features/onboarding/presentation/screens/background_permission_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_action_button.dart';

class BackgroundPermissionScreen extends ConsumerWidget {
  const BackgroundPermissionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(onboardingProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.xxl),

          // Icon
          Icon(
            Icons.auto_awesome,
            size: 100,
            color: theme.colorScheme.secondary,
          ),
          const SizedBox(height: AppSpacing.xl),

          // Title
          Text(
            'Automatic Tracking',
            style: theme.textTheme.displaySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),

          // Rationale
          Text(
            'Enable background location to automatically detect and record trips even when the app is closed.',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),

          // Benefits Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Benefits:',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _BenefitItem(
                    icon: Icons.auto_mode,
                    text: 'Completely automatic - no need to start/stop manually',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _BenefitItem(
                    icon: Icons.battery_charging_full,
                    text: 'Battery optimized - only uses GPS when cycling',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _BenefitItem(
                    icon: Icons.check_circle,
                    text: 'Never miss a trip - records every ride',
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // Optional Note
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'This is optional. You can still record trips manually if you prefer.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Allow Background Button
          OnboardingActionButton(
            label: state.backgroundPermissionGranted
                ? 'Background Enabled ✓'
                : 'Enable Automatic Tracking',
            onPressed: state.backgroundPermissionGranted
                ? () => ref.read(onboardingProvider.notifier).nextPage()
                : () => ref.read(onboardingProvider.notifier).requestBackgroundPermission(),
            icon: state.backgroundPermissionGranted ? Icons.check : Icons.auto_awesome,
          ),
          const SizedBox(height: AppSpacing.sm),

          // Skip Button
          if (!state.backgroundPermissionGranted)
            TextButton(
              onPressed: () {
                ref.read(onboardingProvider.notifier).nextPage();
              },
              child: const Text('Skip for Now'),
            ),
        ],
      ),
    );
  }
}

class _BenefitItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _BenefitItem({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          icon,
          size: AppSpacing.iconMd,
          color: theme.colorScheme.secondary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
```

### Step 9: Screen 5 - Setup Complete Screen

**File**: `lib/features/onboarding/presentation/screens/setup_complete_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_action_button.dart';

class SetupCompleteScreen extends ConsumerWidget {
  const SetupCompleteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(onboardingProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Success Icon
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_circle,
              size: 100,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),

          // Title
          Text(
            'You\'re All Set!',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),

          // Description
          Text(
            state.backgroundPermissionGranted
                ? 'AutoRide will automatically detect when you start cycling. Just hop on your bike and ride!'
                : 'AutoRide is ready! Tap the record button when you start riding to track your trips.',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),

          // Setup Summary
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  _SetupItem(
                    icon: Icons.location_on,
                    label: 'Location Access',
                    enabled: state.locationPermissionGranted,
                  ),
                  const Divider(),
                  _SetupItem(
                    icon: Icons.auto_awesome,
                    label: 'Automatic Tracking',
                    enabled: state.backgroundPermissionGranted,
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // Start Riding Button
          OnboardingActionButton(
            label: 'Start Riding',
            onPressed: () {
              ref.read(onboardingProvider.notifier).completeOnboarding();
            },
            icon: Icons.directions_bike,
          ),
        ],
      ),
    );
  }
}

class _SetupItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;

  const _SetupItem({
    required this.icon,
    required this.label,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(
            icon,
            color: enabled ? Colors.green : theme.colorScheme.outline,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge,
            ),
          ),
          Icon(
            enabled ? Icons.check_circle : Icons.cancel,
            color: enabled ? Colors.green : theme.colorScheme.outline,
          ),
        ],
      ),
    );
  }
}
```

### Step 10: Shared Widgets - Page Indicator

**File**: `lib/features/onboarding/presentation/widgets/onboarding_page_indicator.dart`

```dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_spacing.dart';

class OnboardingPageIndicator extends StatelessWidget {
  final int currentPage;
  final int pageCount;

  const OnboardingPageIndicator({
    super.key,
    required this.currentPage,
    required this.pageCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        pageCount,
        (index) => Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          width: currentPage == index ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: currentPage == index
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withOpacity(0.3),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}
```

### Step 11: Shared Widgets - Action Button

**File**: `lib/features/onboarding/presentation/widgets/onboarding_action_button.dart`

```dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_spacing.dart';

class OnboardingActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool isSecondary;

  const OnboardingActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isSecondary = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md,
          ),
          backgroundColor: isSecondary ? null : null, // Use theme default
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon),
              const SizedBox(width: AppSpacing.sm),
            ],
            Text(label),
          ],
        ),
      ),
    );
  }
}
```

### Step 12: Main Onboarding Coordinator

**File**: `lib/features/onboarding/presentation/screens/onboarding_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_page_indicator.dart';
import 'welcome_screen.dart';
import 'features_screen.dart';
import 'location_permission_screen.dart';
import 'background_permission_screen.dart';
import 'setup_complete_screen.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  @override
  void dispose() {
    ref.read(onboardingProvider.notifier).dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar with Skip Button
            if (state.currentPage < 4)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back Button (if not first page)
                    if (state.currentPage > 0)
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => notifier.previousPage(),
                      )
                    else
                      const SizedBox(width: 48),

                    // Page Indicator
                    OnboardingPageIndicator(
                      currentPage: state.currentPage,
                      pageCount: 5,
                    ),

                    // Skip Button (if not on permission screens)
                    if (state.currentPage < 2)
                      TextButton(
                        onPressed: () => notifier.skip(),
                        child: const Text('Skip'),
                      )
                    else
                      const SizedBox(width: 48),
                  ],
                ),
              ),

            // Page View
            Expanded(
              child: PageView(
                controller: notifier.pageController,
                onPageChanged: (page) => notifier.updatePage(page),
                physics: const NeverScrollableScrollPhysics(), // Disable swipe
                children: const [
                  WelcomeScreen(),
                  FeaturesScreen(),
                  LocationPermissionScreen(),
                  BackgroundPermissionScreen(),
                  SetupCompleteScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## Integration with Main App

Update `lib/main.dart` to check onboarding status and route accordingly:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'features/onboarding/data/services/onboarding_service.dart';
import 'features/onboarding/presentation/screens/onboarding_screen.dart';
// Import your main app screen here

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
      home: const InitialRouteScreen(),
    );
  }
}

class InitialRouteScreen extends ConsumerWidget {
  const InitialRouteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFirstLaunchAsync = ref.watch(onboardingServiceProvider);

    return isFirstLaunchAsync.when(
      data: (isFirstLaunch) {
        if (isFirstLaunch) {
          return const OnboardingScreen();
        } else {
          // Return your main app screen
          return const Scaffold(
            body: Center(
              child: Text('Main App Screen'),
            ),
          );
        }
      },
      loading: () => const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, stack) => Scaffold(
        body: Center(
          child: Text('Error: $error'),
        ),
      ),
    );
  }
}
```

---

## Testing Strategy

### Widget Tests

**File**: `test/features/onboarding/presentation/screens/welcome_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:autoride/features/onboarding/presentation/screens/welcome_screen.dart';

void main() {
  testWidgets('WelcomeScreen displays app name and features', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: WelcomeScreen(),
        ),
      ),
    );

    expect(find.text('AutoRide'), findsOneWidget);
    expect(find.text('Automatic Trip Detection for Cyclists'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.byIcon(Icons.directions_bike), findsOneWidget);
  });

  testWidgets('WelcomeScreen has feature highlights', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: WelcomeScreen(),
        ),
      ),
    );

    expect(find.text('Automatic Detection'), findsOneWidget);
    expect(find.text('Battery Optimized'), findsOneWidget);
    expect(find.text('Track Your Routes'), findsOneWidget);
  });
}
```

### Integration Tests

Test the complete onboarding flow:
1. Navigate through all screens
2. Permission request handling
3. Skip functionality
4. Completion and persistence

### Manual Testing Checklist

- [ ] First launch shows onboarding
- [ ] Subsequent launches skip onboarding
- [ ] All screens display correctly
- [ ] Page indicator updates properly
- [ ] Back navigation works
- [ ] Skip button navigates to final screen
- [ ] Location permission request appears
- [ ] Background permission request appears
- [ ] Permission denial is handled gracefully
- [ ] Onboarding completion persists
- [ ] Works in both light and dark themes
- [ ] Responsive on different screen sizes
- [ ] Works on both Android and iOS

---

## Quality Gates

### Before Completion

1. **Code Generation**:
   ```bash
   flutter pub run build_runner watch
   ```

2. **Static Analysis**:
   ```bash
   flutter analyze  # Must pass with no errors
   ```

3. **Unit Tests**:
   ```bash
   flutter test
   ```

4. **Manual Testing**:
   - Test on physical device (Android + iOS)
   - Verify permission dialogs
   - Test both themes
   - Verify first-launch detection

---

## Common Mistakes to Avoid

### Mistake 1: Not Using Existing LocationPermissionService
❌ **Wrong**: Creating new permission request logic
✅ **Correct**: Reuse `LocationPermissionService` from T004

### Mistake 2: Incorrect Freezed Pattern
❌ **Wrong**: Placing methods inside freezed class
✅ **Correct**: Use extensions outside class (see CLAUDE.md)

### Mistake 3: Not Handling Permission Denials
❌ **Wrong**: Blocking user if permissions denied
✅ **Correct**: Allow progression, show manual mode option

### Mistake 4: Forgetting Platform Differences
❌ **Wrong**: Single permission request for all platforms
✅ **Correct**: Two-step for Android 10+, handle iOS options

---

## Edge Cases & Error Handling

1. **Permission Already Granted**: Skip to next screen
2. **Permission Denied Forever**: Show settings redirect option
3. **App Killed During Onboarding**: Resume from beginning
4. **Onboarding Data Corruption**: Reset and restart
5. **Network/GPS Unavailable**: Allow continuation (check later)

---

## Files Checklist

**Domain**:
- [ ] `lib/features/onboarding/domain/models/onboarding_state.dart`
- [ ] `lib/features/onboarding/domain/models/onboarding_state.freezed.dart` (generated)

**Data**:
- [ ] `lib/features/onboarding/data/services/onboarding_service.dart`
- [ ] `lib/features/onboarding/data/services/onboarding_service.g.dart` (generated)

**Presentation - Providers**:
- [ ] `lib/features/onboarding/presentation/providers/onboarding_provider.dart`
- [ ] `lib/features/onboarding/presentation/providers/onboarding_provider.g.dart` (generated)

**Presentation - Screens**:
- [ ] `lib/features/onboarding/presentation/screens/onboarding_screen.dart`
- [ ] `lib/features/onboarding/presentation/screens/welcome_screen.dart`
- [ ] `lib/features/onboarding/presentation/screens/features_screen.dart`
- [ ] `lib/features/onboarding/presentation/screens/location_permission_screen.dart`
- [ ] `lib/features/onboarding/presentation/screens/background_permission_screen.dart`
- [ ] `lib/features/onboarding/presentation/screens/setup_complete_screen.dart`

**Presentation - Widgets**:
- [ ] `lib/features/onboarding/presentation/widgets/onboarding_page_indicator.dart`
- [ ] `lib/features/onboarding/presentation/widgets/onboarding_action_button.dart`

**Tests**:
- [ ] `test/features/onboarding/presentation/screens/welcome_screen_test.dart`
- [ ] `test/features/onboarding/presentation/screens/features_screen_test.dart`
- [ ] `test/features/onboarding/presentation/widgets/onboarding_page_indicator_test.dart`
- [ ] `test/features/onboarding/data/services/onboarding_service_test.dart`

**Updated Files**:
- [ ] `lib/core/constants/app_constants.dart` (add onboarding constants)
- [ ] `lib/main.dart` (add routing logic)

---

## Dependencies Check

**Required (Already Available)**:
- ✅ T020 - Theme System (colors, spacing, typography)
- ✅ T011 - SharedPreferences (first-launch detection)
- ✅ T004 - LocationPermissionService (permission requests)
- ✅ T003 - Riverpod Setup (state management)
- ✅ T001 - Freezed (domain models)

**No New Dependencies Required**

---

## Acceptance Criteria

- ✅ Welcome screens introduce the app value proposition
- ✅ Progressive permission requests (foreground → background)
- ✅ Initial setup completed before main app usage
- ✅ User can skip optional steps (background permission)
- ✅ Onboarding shows only once (first launch)
- ✅ Permission denials handled gracefully
- ✅ Works on both Android and iOS with platform-specific flows
- ✅ Integrates with existing theme system
- ✅ Code passes `flutter analyze` and `flutter test`
- ✅ Manual testing completed on physical devices

---

## Next Steps

After completing T021:
1. Update task status in `tasks/TASKS.md` to ✅
2. Commit changes with task ID: `T021: Onboarding Flow`
3. Move to next Phase 6 task (Trip Recorder UI screens)

---

**Created**: 2025-11-22
**Last Updated**: 2025-11-22
