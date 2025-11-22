# AutoRide - Automatic Bike Trip Detection

**Flutter app that automatically detects and records bike trips using motion sensors and ML-powered activity recognition.**

## Project Overview

- **Purpose**: Automatic bike trip detection and recording with battery-optimized background tracking
- **Platforms**: iOS & Android (primary)
- **State Management**: Riverpod with code generation
- **Core Tech**: Flutter 3.10.1+, TensorFlow Lite (HAR), Geolocator, Sensors
- **Key Challenge**: Balance accuracy with battery efficiency for background tracking

## Architecture Principles

### Riverpod State Management

**Code Generation Pattern** (Recommended):
```dart
// Use @riverpod annotation for compile-time safety
@riverpod
class TripDetectionState extends _$TripDetectionState {
  @override
  TripState build() => TripState.idle();

  void startTracking() { /* ... */ }
}
```

**Core Rules**:
- Use `autoDispose` for ephemeral state (UI state, form inputs)
- Use `keepAlive()` for persistent data (active trip, settings)
- Declare providers as **top-level final variables**
- **Never** initialize providers in widget `initState`
- Run `flutter pub run build_runner watch` during development

### Project Structure

**Feature-First Organization**:
```
lib/
├── core/
│   ├── constants/        # App-wide constants
│   ├── utils/            # Helper functions
│   └── theme/            # App theme
├── features/
│   ├── trip_detection/   # Core trip tracking
│   │   ├── data/         # Repository, data sources
│   │   ├── domain/       # Models, entities
│   │   ├── presentation/ # UI, providers
│   │   └── services/     # Background service, ML
│   ├── trip_history/     # View past trips
│   ├── settings/         # User preferences
│   └── onboarding/       # First-run experience
├── shared/
│   ├── models/           # Cross-feature models
│   ├── providers/        # Global providers
│   └── widgets/          # Reusable widgets
└── main.dart
```

**Design Philosophy**:
- **Separation of Concerns**: Data → Domain → Presentation
- **Battery First**: Design all background ops for power efficiency
- **Feature Isolation**: Each feature is self-contained

## Essential Dependencies

### Core Dependencies
```yaml
dependencies:
  # State Management
  flutter_riverpod: ^2.4.0
  riverpod_annotation: ^2.3.0

  # Location & Sensors
  geolocator: ^11.0.0
  sensors_plus: ^4.0.0
  flutter_background_service: ^5.0.0
  wakelock_plus: ^1.1.0

  # ML & Activity Recognition
  tflite_flutter: ^0.10.0

  # Persistence
  sqflite: ^2.3.0
  shared_preferences: ^2.2.0

  # Permissions
  permission_handler: ^11.0.0

dev_dependencies:
  # Code Generation
  build_runner: ^2.4.0
  riverpod_generator: ^2.3.0
  flutter_launcher_icons: ^0.13.0
```

## Background Location Tracking

### Battery Optimization Strategy

**Motion-Gated GPS Activation**:
```dart
// Don't run GPS continuously - use sensors to detect movement first
accelerometerEventStream().listen((event) {
  double magnitude = sqrt(pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2));

  if (magnitude > MOVEMENT_THRESHOLD && !isGPSActive) {
    startGPSTracking(); // Only activate GPS when moving
  }
});
```

**Adaptive Location Accuracy**:
```dart
final locationSettings = LocationSettings(
  accuracy: LocationAccuracy.medium,  // Balance: not too precise, not too coarse
  distanceFilter: 15,                 // Update every 15m (optimized for cycling)
  timeLimit: Duration(seconds: 30),   // Timeout for location requests
);

// Stream-based (not polling!)
Geolocator.getPositionStream(locationSettings: locationSettings)
  .listen((Position position) {
    // Process location update
  });
```

### Platform-Specific Setup

**Android** (`android/app/src/main/AndroidManifest.xml`):
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />

<application>
  <service
    android:name="com.your.app.BackgroundService"
    android:foregroundServiceType="location"
    android:exported="false" />
</application>
```

**iOS** (`ios/Runner/Info.plist`):
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need location access to automatically detect your bike trips.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>We need background location to track trips while the app is closed.</string>
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
</array>
```

**Foreground Service Pattern** (Android):
```dart
// MUST show notification during active tracking
await FlutterBackgroundService().configure(
  androidConfiguration: AndroidConfiguration(
    onStart: onStart,
    isForegroundMode: true,  // Required for reliable background execution
    notificationChannelId: 'trip_tracking',
    initialNotificationTitle: 'AutoRide',
    initialNotificationContent: 'Tracking your bike trip',
    foregroundServiceNotificationId: 888,
  ),
  iosConfiguration: IosConfiguration(onForeground: onStart),
);
```

## Motion Detection & Sensors

### Cycling Detection Pattern

**Multi-Sensor Approach**:
```dart
@riverpod
Stream<MotionData> motionDataStream(MotionDataStreamRef ref) {
  // Combine accelerometer + gyroscope
  return Rx.combineLatest2<AccelerometerEvent, GyroscopeEvent, MotionData>(
    accelerometerEventStream(),
    gyroscopeEventStream(),
    (accel, gyro) => MotionData(
      acceleration: sqrt(pow(accel.x, 2) + pow(accel.y, 2) + pow(accel.z, 2)),
      rotation: sqrt(pow(gyro.x, 2) + pow(gyro.y, 2) + pow(gyro.z, 2)),
      timestamp: DateTime.now(),
    ),
  );
}

@riverpod
class TripDetector extends _$TripDetector {
  @override
  DetectionState build() {
    // Listen to motion data
    ref.listen(motionDataStreamProvider, (previous, next) {
      next.when(
        data: (motionData) => _analyzeMotion(motionData),
        loading: () {},
        error: (err, stack) => _handleError(err),
      );
    });

    return DetectionState.idle();
  }

  void _analyzeMotion(MotionData data) {
    // 1. Check for sustained movement (velocity threshold)
    if (data.acceleration > CYCLING_THRESHOLD) {
      // 2. Validate with gyroscope (repetitive circular motion = pedaling)
      if (_detectPedalingPattern(data.rotation)) {
        // 3. Start GPS to validate speed (5-30 km/h typical for cycling)
        _startGPSValidation();
      }
    }
  }
}
```

**Sampling Strategy**:
- **Rate**: 50-100 Hz for cycling detection (balance responsiveness vs battery)
- **Buffer**: Use sliding window (e.g., 5-second windows) for pattern analysis
- **Threshold Tuning**: Adjust based on real-world testing

## Human Activity Recognition (HAR)

### ML Model Architecture

**Input → Model → Output**:
```
Time-series sensor data (60s window)
├── Accelerometer (x, y, z) @ 50 Hz
├── Gyroscope (x, y, z) @ 50 Hz
└── GPS speed (when available)
         ↓
    LSTM/CNN Model
         ↓
Activity Classification:
- Stationary (0.95 confidence)
- Walking (0.80 confidence)
- Cycling (0.92 confidence) ← Target
- Driving (0.75 confidence)
```

**Model Requirements**:
- **Size**: <500 KB (with quantization for mobile)
- **Inference Time**: <100ms on mid-range devices
- **Accuracy Target**: >90% for cycling vs other activities

### TensorFlow Lite Integration

**Model Training (Python/PyTorch) → Conversion → Deployment**:
```dart
@riverpod
class ActivityClassifier extends _$ActivityClassifier {
  late Interpreter _interpreter;

  @override
  Future<void> build() async {
    // Load TFLite model from assets
    _interpreter = await Interpreter.fromAsset('models/activity_classifier.tflite');
    ref.onDispose(() => _interpreter.close());
  }

  ActivityPrediction classify(SensorWindow window) {
    // 1. Prepare input tensor (normalize sensor data)
    var input = _preprocessSensorData(window);

    // 2. Allocate output tensor
    var output = List.filled(NUM_ACTIVITIES, 0.0).reshape([1, NUM_ACTIVITIES]);

    // 3. Run inference
    _interpreter.run(input, output);

    // 4. Parse predictions
    return ActivityPrediction.fromTensor(output);
  }
}
```

**Inference Optimization**:
- Run every **5-10 seconds** (not continuously)
- Use **sliding window** approach (30-60 second windows with 50% overlap)
- **Cache** predictions to reduce redundant calculations
- Only run during **suspected activity** (gated by accelerometer)

### Data Collection for Model Improvement

**Privacy-First Approach**:
```dart
@riverpod
class DataCollectionService extends _$DataCollectionService {
  // Collect raw sensor data + GPS during trips (with user consent)
  Future<void> recordTrainingData(Trip trip) async {
    if (!await _hasUserConsent()) return;

    // Store anonymized data locally
    await _database.insert('training_data', {
      'trip_id': trip.id,
      'sensor_data': _anonymizeSensorData(trip.sensorReadings),
      'gps_trace': _anonymizeGPSTrace(trip.routePoints),
      'user_labeled_activity': trip.confirmedActivity, // User feedback
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    // Batch upload weekly (Wi-Fi only, user-controlled)
    if (_shouldUploadTrainingData()) {
      await _uploadBatchToServer();
    }
  }
}
```

**User Consent Flow**:
1. Explain data usage clearly (improve detection accuracy)
2. Show what data is collected (anonymized sensor readings)
3. Allow opt-out anytime
4. Provide data export option

## Data Persistence

### Database Schema

**SQLite Structure** (`sqflite`):
```dart
// trips table
CREATE TABLE trips (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  start_time INTEGER NOT NULL,
  end_time INTEGER NOT NULL,
  distance REAL NOT NULL,        -- meters
  duration INTEGER NOT NULL,      -- seconds
  avg_speed REAL,                 -- km/h
  max_speed REAL,                 -- km/h
  detected_activity TEXT,         -- 'cycling', 'walking', etc.
  confidence_score REAL,          -- 0.0 - 1.0
  user_confirmed INTEGER DEFAULT 0 -- user validated the activity
);

// route_points table
CREATE TABLE route_points (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  trip_id INTEGER NOT NULL,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  altitude REAL,
  timestamp INTEGER NOT NULL,
  accuracy REAL,
  speed REAL,
  FOREIGN KEY (trip_id) REFERENCES trips(id) ON DELETE CASCADE
);

// Create index for efficient queries
CREATE INDEX idx_trip_start_time ON trips(start_time);
CREATE INDEX idx_route_points_trip_id ON route_points(trip_id);
```

**Repository Pattern**:
```dart
@riverpod
class TripRepository extends _$TripRepository {
  Database? _database;

  @override
  Future<void> build() async {
    _database = await openDatabase(
      'autoride.db',
      version: 1,
      onCreate: _createTables,
    );
  }

  Future<int> saveTrip(Trip trip) async {
    return await _database!.transaction((txn) async {
      // Insert trip
      final tripId = await txn.insert('trips', trip.toMap());

      // Insert route points in batch
      for (var point in trip.routePoints) {
        await txn.insert('route_points', {
          'trip_id': tripId,
          ...point.toMap(),
        });
      }

      return tripId;
    });
  }

  Future<List<Trip>> getTripHistory({int limit = 50}) async {
    final trips = await _database!.query(
      'trips',
      orderBy: 'start_time DESC',
      limit: limit,
    );

    return Future.wait(trips.map((trip) async {
      final points = await _getRoutePoints(trip['id'] as int);
      return Trip.fromMap(trip, points);
    }));
  }
}
```

### Storage Strategy

**Active Trip State**:
- **In-memory** (Riverpod state) for real-time updates
- **Periodic checkpoints** to disk (every 30 seconds)
- **Crash recovery**: Resume from last checkpoint

**Sensor Data Buffer**:
- **Circular buffer** in memory (e.g., last 60 seconds)
- **Flush to disk** only when trip is saved
- **Discard** if trip is cancelled (privacy)

**Settings**:
```dart
@riverpod
class SettingsRepository extends _$SettingsRepository {
  late SharedPreferences _prefs;

  @override
  Future<UserSettings> build() async {
    _prefs = await SharedPreferences.getInstance();
    return UserSettings.fromPrefs(_prefs);
  }

  Future<void> updateSettings(UserSettings settings) async {
    await _prefs.setBool('auto_detect_enabled', settings.autoDetectEnabled);
    await _prefs.setDouble('sensitivity', settings.detectionSensitivity);
    await _prefs.setBool('data_collection_consent', settings.dataCollectionConsent);
    state = AsyncValue.data(settings);
  }
}
```

## Battery Optimization Checklist

**Critical Optimizations**:
- [ ] Use accelerometer to **gate GPS activation** (don't run GPS continuously)
- [ ] Implement **adaptive location accuracy** (low → medium → high based on activity)
- [ ] Use **distance-based filtering** (`distanceFilter: 10-20m` for cycling)
- [ ] **Batch sensor readings** and process in intervals (not real-time for every sample)
- [ ] Run ML inference **every 5-10 seconds**, not continuously
- [ ] Use **foreground service only** during active trips
- [ ] **Stop all services** when trip ends (no background processing when idle)
- [ ] Implement **power state awareness** (reduce sampling when battery <20%)
- [ ] Use **stream-based location updates**, not polling
- [ ] Test with **battery profiler** (Android Studio / Xcode Energy Log)

**Power State Adaptation**:
```dart
@riverpod
class BatteryOptimizer extends _$BatteryOptimizer {
  Future<void> adaptTobatterylevel() async {
    final batteryLevel = await Battery().batteryLevel;

    if (batteryLevel < 20) {
      // Reduce sampling rates
      _locationUpdateInterval = Duration(seconds: 60);
      _sensorSamplingRate = 25; // Hz (reduced from 50)
      _mlInferenceInterval = Duration(seconds: 15);
    } else {
      // Normal operation
      _locationUpdateInterval = Duration(seconds: 30);
      _sensorSamplingRate = 50; // Hz
      _mlInferenceInterval = Duration(seconds: 10);
    }
  }
}
```

## Permission Handling

### Progressive Permission Strategy

**Timing Matters**:
```dart
@riverpod
class PermissionManager extends _$PermissionManager {
  // 1. Basic location on first launch (with rationale)
  Future<bool> requestLocationPermission() async {
    // Show custom dialog explaining why
    await _showRationaleDialog(
      title: 'Location Access',
      message: 'AutoRide needs location access to automatically detect your bike trips.',
    );

    var status = await Permission.location.request();
    return status.isGranted;
  }

  // 2. Background location ONLY when user starts first trip
  Future<bool> requestBackgroundLocation() async {
    // Android 10+: Must request foreground first
    if (!await Permission.location.isGranted) {
      return false;
    }

    await _showRationaleDialog(
      title: 'Background Location',
      message: 'To track trips while the app is closed, we need background location access.',
    );

    var status = await Permission.locationAlways.request();
    return status.isGranted;
  }

  // Handle denials gracefully
  Future<void> handlePermissionDenied() async {
    await _showFeatureLimitationDialog(
      'Without location access, AutoRide cannot automatically detect trips. '
      'You can still manually start/stop trip recording.',
    );
  }
}
```

**Platform Differences**:
- **Android 10+**: Foreground → Background (two-step)
- **Android 11+**: Background requires user to select "Allow all the time" in settings
- **iOS 14+**: "Allow Once" vs "While Using" vs "Always"

## Testing & Quality

### Test Coverage Strategy

**Unit Tests** (business logic, data):
```dart
test('Trip distance calculation is accurate', () {
  final trip = Trip(
    routePoints: [
      RoutePoint(lat: 48.8566, lon: 2.3522), // Paris
      RoutePoint(lat: 48.8606, lon: 2.3376), // ~1.2 km away
    ],
  );

  expect(trip.distance, closeTo(1200, 50)); // meters, ±50m tolerance
});

test('Activity classifier detects cycling correctly', () async {
  final classifier = ActivityClassifier();
  final mockSensorData = _generateCyclingSensorData();

  final prediction = classifier.classify(mockSensorData);

  expect(prediction.activity, equals(Activity.cycling));
  expect(prediction.confidence, greaterThan(0.85));
});
```

**Widget Tests** (UI with mocked providers):
```dart
testWidgets('Trip detection button starts tracking', (tester) async {
  final container = ProviderContainer(
    overrides: [
      tripDetectionStateProvider.overrideWith(
        (ref) => MockTripDetectionState(),
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MyApp(),
    ),
  );

  await tester.tap(find.byIcon(Icons.play_arrow));
  await tester.pump();

  verify(mockTripDetection.startTracking()).called(1);
});
```

**Integration Tests** (end-to-end flow):
```dart
testWidgets('Complete trip detection flow', (tester) async {
  // Mock location and sensor streams
  when(mockGeolocator.getPositionStream()).thenAnswer((_) => _mockLocationStream());
  when(mockSensors.accelerometer()).thenAnswer((_) => _mockAccelerometerStream());

  // Start app
  await tester.pumpWidget(MyApp());

  // Simulate movement detection
  _simulateCyclingMotion();
  await tester.pumpAndSettle();

  // Verify trip started
  expect(find.text('Trip in progress'), findsOneWidget);

  // Stop trip
  await tester.tap(find.byIcon(Icons.stop));
  await tester.pumpAndSettle();

  // Verify trip saved
  final trips = await container.read(tripRepositoryProvider).getTripHistory();
  expect(trips.length, equals(1));
});
```

**Battery Profiling**:
- **Android**: Use Android Studio Battery Profiler
- **iOS**: Use Xcode Energy Log
- **Target**: <5% battery drain per hour of active tracking

## Common Pitfalls & Solutions

### Background Service Killed by OS

**Problem**: Android/iOS kills background service to save battery.

**Solution**:
```dart
// 1. Use foreground service with persistent notification
await FlutterBackgroundService().configure(
  androidConfiguration: AndroidConfiguration(
    isForegroundMode: true,  // Critical!
    autoStartOnBoot: false,  // Don't auto-start (privacy)
  ),
);

// 2. Implement restart logic
@override
void onStart(ServiceInstance service) {
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Periodic heartbeat to detect if killed
  Timer.periodic(Duration(minutes: 1), (timer) {
    if (!service.isRunning()) {
      _attemptRestart();
    }
  });
}
```

### Excessive Battery Drain

**Problem**: Battery drains too quickly during tracking.

**Solution**:
```dart
// Profile with Android Studio Battery Profiler to identify culprits
// Common fixes:
// 1. Reduce GPS accuracy
LocationSettings(accuracy: LocationAccuracy.medium) // Not 'best'

// 2. Increase distance filter
LocationSettings(distanceFilter: 20) // meters

// 3. Gate GPS with accelerometer
if (isMoving && !isGPSActive) {
  startGPS(); // Only when needed
}

// 4. Reduce sensor sampling rate
accelerometerEventStream(samplingPeriod: Duration(milliseconds: 50)) // 20 Hz, not 100 Hz
```

### Inaccurate Trip Detection

**Problem**: False positives (detecting trips when not cycling) or false negatives (missing actual trips).

**Solution**:
```dart
// 1. Collect training data from real users
await dataCollectionService.recordLabeledTrip(trip, userConfirmedActivity);

// 2. Retrain ML model with new data
// (Python/PyTorch pipeline, then convert to TFLite)

// 3. Adjust detection thresholds based on analytics
const CYCLING_SPEED_MIN = 8.0; // km/h (tune based on data)
const CYCLING_SPEED_MAX = 40.0; // km/h
const MOVEMENT_THRESHOLD = 1.5; // m/s² acceleration

// 4. Add user feedback loop
void onTripEnd(Trip trip) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Was this a bike trip?'),
      actions: [
        TextButton(
          onPressed: () => _confirmActivity(trip, Activity.cycling),
          child: Text('Yes'),
        ),
        TextButton(
          onPressed: () => _correctActivity(trip),
          child: Text('No, it was...'),
        ),
      ],
    ),
  );
}
```

### Permission Handling Complexity

**Problem**: Different Android versions and iOS have different permission models.

**Solution**:
```dart
// Abstract platform differences into single interface
@riverpod
class PlatformPermissions extends _$PlatformPermissions {
  Future<LocationPermissionStatus> requestLocationPermission() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;

      if (androidInfo.version.sdkInt >= 30) { // Android 11+
        return _handleAndroid11Permissions();
      } else if (androidInfo.version.sdkInt >= 29) { // Android 10
        return _handleAndroid10Permissions();
      } else {
        return _handleLegacyAndroidPermissions();
      }
    } else {
      return _handleIOSPermissions();
    }
  }
}

// Test all scenarios:
// - Fresh install
// - Permission denied → re-request
// - Permission "denied forever" → open settings
// - Background permission on Android 11+ (requires settings navigation)
```

## Development Workflow

### Daily Development Pattern

```bash
# 1. Start code generation watcher
flutter pub run build_runner watch

# 2. Run on device (not emulator for sensor/GPS testing!)
flutter run --release  # Test battery usage in release mode

# 3. Enable verbose logging for debugging
flutter logs --verbose

# 4. Profile battery usage
# Android: Android Studio → Profiler → Energy
# iOS: Xcode → Debug Navigator → Energy Impact
```

### Code Generation Workflow

```dart
// 1. Write provider with annotation
@riverpod
class MyProvider extends _$MyProvider {
  @override
  String build() => 'initial';
}

// 2. Generate code (automatic with watch, or manual)
flutter pub run build_runner build --delete-conflicting-outputs

// 3. Import generated file
import 'my_provider.g.dart'; // Generated
```

### Testing on Real Devices

**Critical**: Always test location/sensor features on **physical devices**, not emulators.

**Test Scenarios**:
- [ ] Cycling trip (10+ minutes)
- [ ] Walking trip (false positive check)
- [ ] Driving trip (false positive check)
- [ ] Stationary (no trip detection)
- [ ] App backgrounded during trip
- [ ] App killed during trip (restart detection)
- [ ] Low battery scenario (<20%)
- [ ] No GPS signal (indoors)

## Resources & Documentation

### Official Documentation
- [Riverpod](https://riverpod.dev) - State management
- [Geolocator](https://pub.dev/packages/geolocator) - Location services
- [Flutter Background Service](https://pub.dev/packages/flutter_background_service) - Background tasks
- [Sensors Plus](https://pub.dev/packages/sensors_plus) - Accelerometer, gyroscope
- [TensorFlow Lite Flutter](https://pub.dev/packages/tflite_flutter) - ML inference

### Research & Best Practices
- [Handling Background Location Tracking Responsibly](https://vibe-studio.ai/insights/handling-background-location-tracking-responsibly-in-flutter)
- [Battery Optimization for Background Tasks](https://kotlincodes.com/flutter-dart/advanced-concepts/handling-battery-optimization-for-background-tasks-in-flutter/)
- [Human Activity Recognition Research](https://link.springer.com/article/10.1007/s12243-023-00962-x)
- [Building Lightweight HAR Models with TFLite](https://link.springer.com/article/10.1007/s12243-023-00962-x)

### Community Resources
- [Flutter Background Geolocation](https://github.com/transistorsoft/flutter_background_geolocation) - Advanced geolocation plugin
- [TensorFlow Lite Examples](https://github.com/tensorflow/examples/tree/master/lite) - ML model examples

---

## Quick Reference

**Start New Feature**:
```bash
mkdir -p lib/features/my_feature/{data,domain,presentation,services}
```

**Add Riverpod Provider**:
```dart
@riverpod
class MyProvider extends _$MyProvider {
  @override
  State build() => State();
}
```

**Run Code Generation**:
```bash
flutter pub run build_runner watch
```

**Test Battery Usage**:
```bash
flutter run --release  # On physical device
# Then: Profile → Energy
```

**Common Commands**:
```bash
flutter analyze                    # Static analysis
flutter test                       # Run tests
flutter pub outdated               # Check dependencies
flutter clean && flutter pub get   # Clean build
```

---

**Last Updated**: 2025-11-22
**Flutter Version**: 3.10.1+
**Target SDK**: iOS 13+, Android 8+ (API 26+)
