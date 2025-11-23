# T024 - Settings Screen

**Status**: ☐ Pending
**Assignee**: Claude
**Estimated Time**: 2-3 hours
**Phase**: Phase 6 - User Interface (Task 6.1.4)

## Overview

Create a comprehensive settings screen that allows users to configure all app preferences including detection settings, battery optimization, location preferences, notifications, data privacy, display units, and theme selection. The screen integrates with the settings system from T011 and uses the design system from T020.

## Dependencies

- ✅ **T011** - Settings & Preferences (provides data layer and models)
- ✅ **T020** - App Theme & Design System (provides UI components and theme)

## Objectives

1. Create a well-organized settings screen with clear sections
2. Implement settings controls for all user preferences
3. Provide immediate visual feedback for setting changes
4. Handle permission requests appropriately (background location)
5. Include data management actions (clear trips, reset settings)
6. Support theme switching with live preview
7. Show developer settings only in debug builds

## Technical Requirements

### Available Settings (from T011)

**UserSettings Model**:
```dart
UserSettings {
  // Detection
  DetectionSettings detection {
    bool autoStartEnabled
    CyclingSensitivity sensitivity  // low, medium, high
    int minimumTripDurationSeconds
    int stationaryTimeoutSeconds
  }

  // Battery
  BatteryOptimizationMode batteryMode  // aggressive, balanced, performance

  // Location
  LocationAccuracyPreference locationAccuracy  // low, medium, high
  int distanceFilterMeters
  bool backgroundLocationEnabled

  // Notifications
  bool tripNotificationsEnabled
  bool showOngoingNotification
  bool soundOnTripStartStop

  // Data & Privacy
  bool dataCollectionConsent
  bool anonymousUsageStats

  // Display
  DistanceUnit distanceUnit  // metric, imperial
  SpeedUnit speedUnit  // kmh, mph, ms
  ThemeMode themeMode  // light, dark, system

  // Developer (debug only)
  bool debugLoggingEnabled
  bool showSensorOverlay
}
```

**Available Providers** (from T011):
```dart
// Main settings provider
currentSettingsProvider → UserSettings

// UI-specific notifiers
DetectionSettingsNotifier {
  updateAutoStart(bool)
  updateSensitivity(CyclingSensitivity)
  updateMinimumDuration(int)
  updateStationaryTimeout(int)
}

DisplaySettingsNotifier {
  updateDistanceUnit(DistanceUnit)
  updateSpeedUnit(SpeedUnit)
  updateThemeMode(ThemeMode)
}

SettingsService {
  updateSettings(UserSettings)
  updatePartial(UserSettings Function(UserSettings))
  resetToDefaults()
}
```

### Files to Create

#### 1. Main Settings Screen

**`lib/features/settings/presentation/screens/settings_screen.dart`**
- Scaffold with scrollable settings sections
- AppBar with title and reset button
- Organized sections with clear headers
- Integration with all settings providers

#### 2. Settings Section Widgets

**`lib/features/settings/presentation/widgets/detection_settings_section.dart`**
- Auto-start toggle
- Sensitivity selector (Low/Medium/High)
- Minimum trip duration slider
- Stationary timeout slider

**`lib/features/settings/presentation/widgets/battery_settings_section.dart`**
- Battery mode selector (Aggressive/Balanced/Performance)
- Description of each mode's behavior
- Current battery level indicator (optional)

**`lib/features/settings/presentation/widgets/location_settings_section.dart`**
- Location accuracy selector (Low/Medium/High)
- Distance filter slider
- Background location toggle with permission handling
- Accuracy impact description

**`lib/features/settings/presentation/widgets/notification_settings_section.dart`**
- Trip notifications toggle
- Ongoing notification toggle
- Sound toggle
- Preview notification button (optional)

**`lib/features/settings/presentation/widgets/privacy_settings_section.dart`**
- Data collection consent toggle
- Anonymous usage stats toggle
- Privacy policy link
- Clear explanation of what data is collected

**`lib/features/settings/presentation/widgets/display_settings_section.dart`**
- Distance unit selector (Metric/Imperial)
- Speed unit selector (km/h, mph, m/s)
- Theme mode selector with icons (Light/Dark/System)
- Live theme preview

**`lib/features/settings/presentation/widgets/data_management_section.dart`**
- Clear all trips button (with confirmation)
- Reset settings to defaults button (with confirmation)
- App version and build number display

**`lib/features/settings/presentation/widgets/developer_settings_section.dart`** (kDebugMode only)
- Debug logging toggle
- Sensor overlay toggle
- Export logs button (optional)

#### 3. Reusable Settings Widgets

**`lib/features/settings/presentation/widgets/setting_section.dart`**
- Reusable section container with title
- Consistent spacing and styling
- Optional description/subtitle

**`lib/features/settings/presentation/widgets/setting_tile.dart`**
- Reusable setting row with label and control
- Support for Switch, Radio, Slider, etc.
- Optional subtitle/description
- Consistent styling

**`lib/features/settings/presentation/widgets/setting_slider.dart`**
- Labeled slider with current value display
- Min/max labels
- Optional unit display

**`lib/features/settings/presentation/widgets/setting_radio_group.dart`**
- Radio button group with labels
- Support for enums
- Optional icons per option

## Implementation Guide

### Step 1: Create Reusable Setting Widgets (30 min)

These foundation widgets will make implementing the actual settings much faster and more consistent.

#### SettingSection Widget

**File**: `lib/features/settings/presentation/widgets/setting_section.dart`

**Purpose**: Container for grouping related settings with a title

**Key Features**:
- Section title with proper styling
- Optional subtitle/description
- Consistent padding and spacing
- Card-based or plain background option

**Pattern**:
```dart
class SettingSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool useCard;

  // Displays title, optional subtitle, and children
  // Uses AppSpacing for consistent padding
  // Theme-aware colors
}
```

#### SettingTile Widget

**File**: `lib/features/settings/presentation/widgets/setting_tile.dart`

**Purpose**: Individual setting row with label and control

**Key Features**:
- Title and optional subtitle
- Trailing widget (Switch, Radio, etc.)
- Optional onTap callback
- Consistent height and padding
- Theme-aware styling

**Pattern**:
```dart
class SettingTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget trailing;
  final VoidCallback? onTap;
  final IconData? leadingIcon;

  // ListTile-like widget with consistent styling
  // Uses theme colors and text styles
}
```

#### SettingSlider Widget

**File**: `lib/features/settings/presentation/widgets/setting_slider.dart`

**Purpose**: Slider with label and value display

**Key Features**:
- Title with current value
- Min/max labels
- Optional unit suffix
- Value formatting
- onChanged callback

**Pattern**:
```dart
class SettingSlider extends StatelessWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final String? unit;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final String Function(double)? valueFormatter;

  // Displays slider with labels and current value
  // Theme-aware colors
}
```

#### SettingRadioGroup Widget

**File**: `lib/features/settings/presentation/widgets/setting_radio_group.dart`

**Purpose**: Radio button group for enum selections

**Key Features**:
- Generic type support for enums
- Option labels and descriptions
- Optional icons
- Current selection highlighting
- onChanged callback

**Pattern**:
```dart
class SettingRadioGroup<T> extends StatelessWidget {
  final String title;
  final T value;
  final List<RadioOption<T>> options;
  final ValueChanged<T> onChanged;

  // Radio button group with proper spacing
  // Highlights selected option
}

class RadioOption<T> {
  final T value;
  final String label;
  final String? description;
  final IconData? icon;
}
```

### Step 2: Create Settings Sections (60 min)

Now implement each settings section using the reusable widgets.

#### Detection Settings Section

**File**: `lib/features/settings/presentation/widgets/detection_settings_section.dart`

**Controls**:
```dart
SettingSection(
  title: 'Trip Detection',
  subtitle: 'Configure automatic trip detection behavior',
  children: [
    // Auto-start toggle
    SettingTile(
      title: 'Auto-start trips',
      subtitle: 'Automatically detect and start tracking cycling trips',
      trailing: Switch(
        value: settings.detection.autoStartEnabled,
        onChanged: (value) => ref.read(detectionSettingsNotifierProvider.notifier)
                                 .updateAutoStart(value),
      ),
    ),

    // Sensitivity selector
    SettingRadioGroup<CyclingSensitivity>(
      title: 'Detection sensitivity',
      value: settings.detection.sensitivity,
      options: [
        RadioOption(
          value: CyclingSensitivity.low,
          label: 'Low',
          description: 'Fewer false positives, may miss some trips',
        ),
        RadioOption(
          value: CyclingSensitivity.medium,
          label: 'Medium',
          description: 'Balanced detection (recommended)',
        ),
        RadioOption(
          value: CyclingSensitivity.high,
          label: 'High',
          description: 'Catch all trips, may have false positives',
        ),
      ],
      onChanged: (value) => ref.read(detectionSettingsNotifierProvider.notifier)
                               .updateSensitivity(value),
    ),

    // Minimum duration slider
    SettingSlider(
      title: 'Minimum trip duration',
      value: settings.detection.minimumTripDurationSeconds.toDouble(),
      min: 60,
      max: 300,
      unit: 's',
      divisions: 48,
      valueFormatter: (value) => '${value.toInt()}s',
      onChanged: (value) => ref.read(detectionSettingsNotifierProvider.notifier)
                               .updateMinimumDuration(value.toInt()),
    ),

    // Stationary timeout slider
    SettingSlider(
      title: 'Stationary timeout',
      value: settings.detection.stationaryTimeoutSeconds.toDouble(),
      min: 60,
      max: 600,
      unit: 's',
      divisions: 54,
      valueFormatter: (value) => '${value.toInt()}s (${(value / 60).toStringAsFixed(1)}m)',
      onChanged: (value) => ref.read(detectionSettingsNotifierProvider.notifier)
                               .updateStationaryTimeout(value.toInt()),
    ),
  ],
)
```

#### Battery Settings Section

**File**: `lib/features/settings/presentation/widgets/battery_settings_section.dart`

**Controls**:
```dart
SettingSection(
  title: 'Battery Optimization',
  subtitle: 'Adjust battery usage vs accuracy trade-off',
  children: [
    SettingRadioGroup<BatteryOptimizationMode>(
      title: 'Battery mode',
      value: settings.batteryMode,
      options: [
        RadioOption(
          value: BatteryOptimizationMode.aggressive,
          label: 'Aggressive',
          description: 'Maximum battery savings, lower GPS accuracy',
        ),
        RadioOption(
          value: BatteryOptimizationMode.balanced,
          label: 'Balanced',
          description: 'Good balance of accuracy and battery life',
        ),
        RadioOption(
          value: BatteryOptimizationMode.performance,
          label: 'Performance',
          description: 'Best accuracy, higher battery usage',
        ),
      ],
      onChanged: (value) => ref.read(settingsServiceProvider.notifier)
                               .updatePartial((s) => s.copyWith(batteryMode: value)),
    ),

    // Optional: Current battery level indicator
    // SettingTile(
    //   title: 'Current battery level',
    //   trailing: Text('85%'),
    // ),
  ],
)
```

#### Location Settings Section

**File**: `lib/features/settings/presentation/widgets/location_settings_section.dart`

**Important**: Handle background location permission with proper rationale

**Controls**:
```dart
SettingSection(
  title: 'Location',
  subtitle: 'Configure GPS accuracy and tracking behavior',
  children: [
    SettingRadioGroup<LocationAccuracyPreference>(
      title: 'Location accuracy',
      value: settings.locationAccuracy,
      options: [
        RadioOption(
          value: LocationAccuracyPreference.low,
          label: 'Low',
          description: '~100m accuracy, saves battery',
        ),
        RadioOption(
          value: LocationAccuracyPreference.medium,
          label: 'Medium',
          description: '~10m accuracy (recommended)',
        ),
        RadioOption(
          value: LocationAccuracyPreference.high,
          label: 'High',
          description: '<10m accuracy, uses more battery',
        ),
      ],
      onChanged: (value) => ref.read(settingsServiceProvider.notifier)
                               .updatePartial((s) => s.copyWith(locationAccuracy: value)),
    ),

    SettingSlider(
      title: 'Distance filter',
      value: settings.distanceFilterMeters.toDouble(),
      min: 5,
      max: 50,
      unit: 'm',
      divisions: 9,
      valueFormatter: (value) => '${value.toInt()}m',
      onChanged: (value) => ref.read(settingsServiceProvider.notifier)
                               .updatePartial((s) => s.copyWith(distanceFilterMeters: value.toInt())),
    ),

    SettingTile(
      title: 'Background location',
      subtitle: 'Track trips when app is in background',
      trailing: Switch(
        value: settings.backgroundLocationEnabled,
        onChanged: (value) async {
          if (value) {
            // Request background location permission
            final hasPermission = await _requestBackgroundLocation();
            if (hasPermission) {
              ref.read(settingsServiceProvider.notifier)
                 .updatePartial((s) => s.copyWith(backgroundLocationEnabled: value));
            }
          } else {
            ref.read(settingsServiceProvider.notifier)
               .updatePartial((s) => s.copyWith(backgroundLocationEnabled: value));
          }
        },
      ),
    ),
  ],
)
```

#### Notification Settings Section

**File**: `lib/features/settings/presentation/widgets/notification_settings_section.dart`

**Controls**:
```dart
SettingSection(
  title: 'Notifications',
  subtitle: 'Configure notification preferences',
  children: [
    SettingTile(
      title: 'Trip notifications',
      subtitle: 'Notify when trips start and stop',
      trailing: Switch(
        value: settings.tripNotificationsEnabled,
        onChanged: (value) => ref.read(settingsServiceProvider.notifier)
                                 .updatePartial((s) => s.copyWith(tripNotificationsEnabled: value)),
      ),
    ),

    SettingTile(
      title: 'Ongoing notification',
      subtitle: 'Show notification during active trip',
      trailing: Switch(
        value: settings.showOngoingNotification,
        onChanged: (value) => ref.read(settingsServiceProvider.notifier)
                                 .updatePartial((s) => s.copyWith(showOngoingNotification: value)),
      ),
    ),

    SettingTile(
      title: 'Sound',
      subtitle: 'Play sound on trip start/stop',
      trailing: Switch(
        value: settings.soundOnTripStartStop,
        onChanged: (value) => ref.read(settingsServiceProvider.notifier)
                                 .updatePartial((s) => s.copyWith(soundOnTripStartStop: value)),
      ),
    ),
  ],
)
```

#### Privacy Settings Section

**File**: `lib/features/settings/presentation/widgets/privacy_settings_section.dart`

**Controls**:
```dart
SettingSection(
  title: 'Data & Privacy',
  subtitle: 'Control data collection and usage',
  children: [
    SettingTile(
      title: 'Data collection',
      subtitle: 'Allow anonymous sensor data collection for ML improvement',
      trailing: Switch(
        value: settings.dataCollectionConsent,
        onChanged: (value) => ref.read(settingsServiceProvider.notifier)
                                 .updatePartial((s) => s.copyWith(dataCollectionConsent: value)),
      ),
    ),

    SettingTile(
      title: 'Usage statistics',
      subtitle: 'Send anonymous app usage stats',
      trailing: Switch(
        value: settings.anonymousUsageStats,
        onChanged: (value) => ref.read(settingsServiceProvider.notifier)
                                 .updatePartial((s) => s.copyWith(anonymousUsageStats: value)),
      ),
    ),

    SettingTile(
      title: 'Privacy policy',
      trailing: Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () {
        // Navigate to privacy policy screen or open URL
      },
    ),
  ],
)
```

#### Display Settings Section

**File**: `lib/features/settings/presentation/widgets/display_settings_section.dart`

**Controls**:
```dart
SettingSection(
  title: 'Display',
  subtitle: 'Customize units and appearance',
  children: [
    SettingRadioGroup<DistanceUnit>(
      title: 'Distance unit',
      value: settings.distanceUnit,
      options: [
        RadioOption(
          value: DistanceUnit.metric,
          label: 'Metric (km)',
          description: 'Kilometers',
        ),
        RadioOption(
          value: DistanceUnit.imperial,
          label: 'Imperial (mi)',
          description: 'Miles',
        ),
      ],
      onChanged: (value) => ref.read(displaySettingsNotifierProvider.notifier)
                               .updateDistanceUnit(value),
    ),

    SettingRadioGroup<SpeedUnit>(
      title: 'Speed unit',
      value: settings.speedUnit,
      options: [
        RadioOption(
          value: SpeedUnit.kmh,
          label: 'km/h',
          description: 'Kilometers per hour',
        ),
        RadioOption(
          value: SpeedUnit.mph,
          label: 'mph',
          description: 'Miles per hour',
        ),
        RadioOption(
          value: SpeedUnit.ms,
          label: 'm/s',
          description: 'Meters per second',
        ),
      ],
      onChanged: (value) => ref.read(displaySettingsNotifierProvider.notifier)
                               .updateSpeedUnit(value),
    ),

    SettingRadioGroup<ThemeMode>(
      title: 'Theme',
      value: settings.themeMode,
      options: [
        RadioOption(
          value: ThemeMode.light,
          label: 'Light',
          icon: Icons.light_mode,
        ),
        RadioOption(
          value: ThemeMode.dark,
          label: 'Dark',
          icon: Icons.dark_mode,
        ),
        RadioOption(
          value: ThemeMode.system,
          label: 'System',
          icon: Icons.brightness_auto,
          description: 'Follow system theme',
        ),
      ],
      onChanged: (value) => ref.read(displaySettingsNotifierProvider.notifier)
                               .updateThemeMode(value),
    ),
  ],
)
```

#### Data Management Section

**File**: `lib/features/settings/presentation/widgets/data_management_section.dart`

**Important**: Require confirmation dialogs before destructive actions

**Controls**:
```dart
SettingSection(
  title: 'Data Management',
  children: [
    SettingTile(
      title: 'Clear all trips',
      subtitle: 'Delete all recorded trip data',
      trailing: Icon(Icons.delete_outline, color: AppColors.error),
      onTap: () async {
        final confirmed = await _showConfirmDialog(
          context,
          title: 'Clear all trips?',
          message: 'This will permanently delete all trip data. This action cannot be undone.',
          confirmText: 'Delete',
          isDestructive: true,
        );

        if (confirmed) {
          final repository = await ref.read(tripRepositoryProvider.future);
          await repository.deleteAllTrips();

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('All trips deleted')),
            );
          }
        }
      },
    ),

    SettingTile(
      title: 'Reset settings',
      subtitle: 'Restore all settings to defaults',
      trailing: Icon(Icons.restore, color: AppColors.warning),
      onTap: () async {
        final confirmed = await _showConfirmDialog(
          context,
          title: 'Reset all settings?',
          message: 'This will restore all settings to their default values.',
          confirmText: 'Reset',
        );

        if (confirmed) {
          await ref.read(settingsServiceProvider.notifier).resetToDefaults();

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Settings reset to defaults')),
            );
          }
        }
      },
    ),

    SettingTile(
      title: 'App version',
      subtitle: 'AutoRide v1.0.0 (build 1)',
      trailing: SizedBox.shrink(),
    ),
  ],
)
```

#### Developer Settings Section

**File**: `lib/features/settings/presentation/widgets/developer_settings_section.dart`

**Important**: Only show in debug builds using `kDebugMode`

**Controls**:
```dart
import 'package:flutter/foundation.dart';

// Only export this widget in debug builds
Widget? buildDeveloperSection(UserSettings settings, WidgetRef ref) {
  if (!kDebugMode) return null;

  return SettingSection(
    title: 'Developer',
    subtitle: 'Debug tools (only in debug builds)',
    children: [
      SettingTile(
        title: 'Debug logging',
        subtitle: 'Enable verbose logging',
        trailing: Switch(
          value: settings.debugLoggingEnabled,
          onChanged: (value) => ref.read(settingsServiceProvider.notifier)
                                   .updatePartial((s) => s.copyWith(debugLoggingEnabled: value)),
        ),
      ),

      SettingTile(
        title: 'Sensor overlay',
        subtitle: 'Show real-time sensor data on screen',
        trailing: Switch(
          value: settings.showSensorOverlay,
          onChanged: (value) => ref.read(settingsServiceProvider.notifier)
                                   .updatePartial((s) => s.copyWith(showSensorOverlay: value)),
        ),
      ),
    ],
  );
}
```

### Step 3: Create Main Settings Screen (30 min)

**File**: `lib/features/settings/presentation/screens/settings_screen.dart`

**Structure**:
```dart
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        actions: [
          // Optional: Reset button in app bar
          IconButton(
            icon: Icon(Icons.restore),
            onPressed: () => _handleResetSettings(context, ref),
            tooltip: 'Reset to defaults',
          ),
        ],
      ),
      body: settingsAsync.when(
        data: (settings) => _buildSettingsBody(context, ref, settings),
        loading: () => Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text('Failed to load settings: $error'),
        ),
      ),
    );
  }

  Widget _buildSettingsBody(BuildContext context, WidgetRef ref, UserSettings settings) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetectionSettingsSection(settings: settings),
          SizedBox(height: AppSpacing.md),

          BatterySettingsSection(settings: settings),
          SizedBox(height: AppSpacing.md),

          LocationSettingsSection(settings: settings),
          SizedBox(height: AppSpacing.md),

          NotificationSettingsSection(settings: settings),
          SizedBox(height: AppSpacing.md),

          PrivacySettingsSection(settings: settings),
          SizedBox(height: AppSpacing.md),

          DisplaySettingsSection(settings: settings),
          SizedBox(height: AppSpacing.md),

          DataManagementSection(settings: settings),

          // Developer section (only in debug builds)
          if (kDebugMode) ...[
            SizedBox(height: AppSpacing.md),
            DeveloperSettingsSection(settings: settings),
          ],

          // Bottom spacing
          SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  Future<void> _handleResetSettings(BuildContext context, WidgetRef ref) async {
    final confirmed = await _showConfirmDialog(
      context,
      title: 'Reset all settings?',
      message: 'This will restore all settings to their default values.',
      confirmText: 'Reset',
    );

    if (confirmed && context.mounted) {
      await ref.read(settingsServiceProvider.notifier).resetToDefaults();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Settings reset to defaults')),
      );
    }
  }

  Future<bool> _showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmText,
    bool isDestructive = false,
  }) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: isDestructive
                ? ElevatedButton.styleFrom(backgroundColor: AppColors.error)
                : null,
            child: Text(confirmText),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<bool> _requestBackgroundLocation() async {
    // Request background location permission
    // This should use permission_handler package
    // For now, return true (implement in T027 - Permission Handler)
    return true;
  }
}
```

### Step 4: Integrate with App Navigation (10 min)

**Update Main Navigation** (if using bottom navigation):

```dart
// In main navigation widget or home screen
BottomNavigationBar(
  currentIndex: _currentIndex,
  onTap: (index) => setState(() => _currentIndex = index),
  items: [
    BottomNavigationBarItem(
      icon: Icon(Icons.map),
      label: 'Track',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.history),
      label: 'History',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.settings),
      label: 'Settings',
    ),
  ],
)

// In body
IndexedStack(
  index: _currentIndex,
  children: [
    TripTrackingScreen(),
    TripHistoryScreen(),
    SettingsScreen(),
  ],
)
```

## UI/UX Considerations

### Visual Hierarchy

**Section Organization** (top to bottom):
1. Detection settings (most important for core functionality)
2. Battery optimization (affects user experience)
3. Location settings (related to detection)
4. Notifications (user preferences)
5. Privacy (transparency)
6. Display (personalization)
7. Data management (destructive actions at bottom)
8. Developer (debug only)

### User Feedback

**Immediate Feedback**:
- Settings changes apply immediately (no "Save" button needed)
- Visual feedback for toggles and selections
- Snackbar confirmations for destructive actions
- Loading states for async operations

**Permission Handling**:
- Clear rationale before requesting permissions
- Graceful handling of denied permissions
- Link to system settings if permission denied

**Confirmations**:
- Confirmation dialog for "Clear all trips"
- Confirmation dialog for "Reset settings"
- Visual distinction for destructive actions (red color)

### Accessibility

**Color Contrast**:
- All text meets WCAG AA standards (4.5:1 minimum)
- Don't rely on color alone for information
- Use icons + text for clarity

**Touch Targets**:
- Minimum 44x44 logical pixels for all interactive elements
- Adequate spacing between controls
- Proper padding for tap areas

**Screen Readers**:
- Semantic labels for all controls
- Proper heading hierarchy
- Meaningful descriptions for toggles

### Theme Usage

**Colors** (from AppColors):
- Primary: Section headers, active states
- Secondary: Action buttons
- Success: Confirmation messages
- Warning: Reset actions
- Error: Destructive actions
- Surface: Card backgrounds
- Text: Primary and secondary text

**Spacing** (from AppSpacing):
- Section padding: `AppSpacing.md`
- Between sections: `AppSpacing.md`
- Card padding: `AppSpacing.md`
- Screen padding: `AppSpacing.md`
- Bottom safe area: `AppSpacing.xxl`

## Testing Strategy

### Manual Testing Checklist

**Settings Persistence**:
- [ ] Change detection settings → restart app → verify persisted
- [ ] Change theme → restart app → verify persisted
- [ ] Change units → restart app → verify persisted

**Settings Functionality**:
- [ ] Auto-start toggle enables/disables detection
- [ ] Sensitivity changes affect detection thresholds
- [ ] Battery mode changes affect GPS behavior
- [ ] Location accuracy changes GPS settings
- [ ] Background location requests permission
- [ ] Theme mode changes app appearance immediately
- [ ] Unit changes update displayed values

**Data Management**:
- [ ] Clear trips deletes all trip data (with confirmation)
- [ ] Reset settings restores all defaults (with confirmation)
- [ ] App version displays correctly

**Developer Settings** (debug build only):
- [ ] Developer section only visible in debug builds
- [ ] Debug logging can be toggled
- [ ] Sensor overlay can be toggled

**UI/UX**:
- [ ] All sections render correctly
- [ ] Scrolling is smooth
- [ ] All controls are responsive
- [ ] Confirmation dialogs work
- [ ] Snackbar feedback appears
- [ ] Loading states display
- [ ] Error states display

**Theme Testing**:
- [ ] Test all settings in light theme
- [ ] Test all settings in dark theme
- [ ] Verify theme switches work
- [ ] Check all colors are accessible

**Permissions**:
- [ ] Background location permission requested appropriately
- [ ] Permission denial handled gracefully
- [ ] Can toggle off without errors

### Widget Tests (Optional)

**Test reusable widgets**:
```dart
testWidgets('SettingTile renders correctly', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SettingTile(
          title: 'Test Setting',
          subtitle: 'Test description',
          trailing: Switch(value: true, onChanged: (_) {}),
        ),
      ),
    ),
  );

  expect(find.text('Test Setting'), findsOneWidget);
  expect(find.text('Test description'), findsOneWidget);
  expect(find.byType(Switch), findsOneWidget);
});
```

## Quality Gates

**Before marking T024 complete**:

1. ✅ All files created and implemented
2. ✅ Run `flutter pub run build_runner build` (if using generated code)
3. ✅ Run `flutter analyze` - MUST pass with 0 warnings
4. ✅ Manual testing on physical device completed
5. ✅ No unused imports or variables
6. ✅ `const` constructors used where possible
7. ✅ All sections render correctly in both themes
8. ✅ Settings persist across app restarts
9. ✅ Confirmation dialogs work for destructive actions
10. ✅ Theme and spacing consistent with design system
11. ✅ Documentation updated (TASKS.md marked ✅)

## Common Pitfalls to Avoid

**From CLAUDE.md Lessons Learned**:

1. ⚠️ **Mistake #2**: Use `Ref ref`, not specific ref types in providers
2. ⚠️ **Mistake #3**: Run `flutter analyze` to catch unused imports/variables
3. ⚠️ **Best Practice**: Use `const` constructors where possible
4. ⚠️ **File Organization**: Put settings screen in proper directory structure
5. ⚠️ **Permission Handling**: Always provide rationale before requesting permissions
6. ⚠️ **Destructive Actions**: Always confirm before clearing data or resetting
7. ⚠️ **Theme Awareness**: Test all UI in both light and dark themes
8. ⚠️ **Developer Settings**: Only show in `kDebugMode`, never in production

## Resources

**Existing Code References**:
- Settings models: `lib/features/settings/domain/models/`
- Settings service: `lib/features/settings/data/services/settings_service.dart`
- Settings providers: `lib/features/settings/presentation/providers/settings_provider.dart`
- Theme system: `lib/core/theme/`
- Shared widgets: `lib/shared/widgets/`
- Similar screen: `lib/features/trip_history/presentation/screens/trip_history_screen.dart`

**Flutter Documentation**:
- [ListTile](https://api.flutter.dev/flutter/material/ListTile-class.html)
- [Switch](https://api.flutter.dev/flutter/material/Switch-class.html)
- [Slider](https://api.flutter.dev/flutter/material/Slider-class.html)
- [Radio](https://api.flutter.dev/flutter/material/Radio-class.html)
- [AlertDialog](https://api.flutter.dev/flutter/material/AlertDialog-class.html)

## Definition of Done

- [ ] All reusable setting widgets created (4 widgets)
- [ ] All settings sections created (8 sections)
- [ ] Main settings screen created
- [ ] Navigation integration complete
- [ ] Flutter analyze passes with 0 warnings
- [ ] Manual testing completed on physical device
- [ ] Settings persist across restarts
- [ ] Confirmation dialogs work
- [ ] Theme consistency verified
- [ ] Both light and dark themes tested
- [ ] Developer section only in debug builds
- [ ] Documentation updated in tasks/TASKS.md

## Time Tracking

- **Estimated**: 2-3 hours
- **Breakdown**:
  - Reusable widgets: 30 min
  - Settings sections: 60 min
  - Main screen: 30 min
  - Navigation integration: 10 min
  - Testing and fixes: 20-50 min

## Notes

- This task creates the UI layer for settings. The data layer was completed in T011.
- Permission handling is simplified for now. Full permission flow will be in T027.
- Privacy policy link can point to a placeholder or external URL.
- Developer settings are only visible in debug builds using `kDebugMode`.
- Settings apply immediately - no "Save" button needed.
- All destructive actions require confirmation dialogs.

---

**Created**: 2025-11-23
**Last Updated**: 2025-11-23
**Dependencies**: T011 ✅, T020 ✅
**Blocks**: T025 (Notifications UI integration)
