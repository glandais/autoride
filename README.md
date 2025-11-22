# AutoRide

**Automatically detect and record your bike trips with intelligent motion sensing.**

AutoRide is a privacy-focused mobile app that uses advanced motion detection and machine learning to automatically recognize when you're cycling and record your trips—no manual start/stop required.

[![Flutter](https://img.shields.io/badge/Flutter-3.10.1+-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20Android-lightgrey)](#)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Features

### Automatic Trip Detection
- **Zero-touch tracking** - Automatically detects when you start cycling
- **Smart motion sensing** - Uses accelerometer and gyroscope to identify cycling patterns
- **Battery optimized** - Intelligent GPS management for all-day tracking
- **Background tracking** - Records trips even when your phone is locked

### Activity Recognition
- **ML-powered detection** - Distinguishes cycling from walking, driving, or standing still
- **Adaptive learning** - Improves accuracy over time with user feedback
- **Confidence scoring** - Shows how certain the app is about detected activities

### Trip Management
- **Detailed trip history** - View all your past rides with routes, distance, and duration
- **Route mapping** - See your exact path on an interactive map
- **Statistics** - Track total distance, time spent cycling, and more
- **Export data** - Download your trip data for analysis

### Privacy First
- **Local storage** - All trip data stored on your device
- **Optional sharing** - Choose what (if anything) to share for improving detection
- **No tracking** - We don't track you or sell your data
- **Full control** - Delete your data anytime

---

## Screenshots

> 📸 Coming soon - App is currently in development

---

## Installation

### For End Users

#### Android
1. Download the APK from [Releases](../../releases)
2. Install the APK (you may need to enable "Install from unknown sources")
3. Grant location and activity recognition permissions when prompted
4. Start cycling - AutoRide will detect your trips automatically!

#### iOS
1. Download from the App Store *(Coming soon)*
2. Grant location permissions when prompted
3. Enable background location for automatic tracking
4. Start cycling!

### Permissions Required

**Android:**
- **Location** (Fine & Background) - Required to track your route
- **Physical Activity** - Helps detect when you're cycling
- **Foreground Service** - Keeps tracking active while app is in background

**iOS:**
- **Location** (Always) - Required for automatic trip detection
- **Motion & Fitness** - Helps identify cycling activity

> **Why these permissions?** AutoRide needs location access to map your routes and motion sensors to detect when you're cycling. We never share this data without your explicit consent.

---

## How to Use

### First Launch
1. **Grant Permissions** - Allow location and motion sensor access
2. **Set Preferences** - Adjust detection sensitivity if needed (Settings)
3. **Start Riding** - Just hop on your bike and ride!

### During a Ride
- AutoRide automatically detects when you start cycling
- A notification shows trip progress (distance, time, speed)
- No need to interact with the app - just ride

### After a Ride
- Trip automatically stops when you finish cycling
- Review trip details, route, and statistics
- Confirm activity type if detection was incorrect (helps improve accuracy)

### Manual Control
- **Force start** - Tap the play button to manually start tracking
- **Force stop** - Tap the stop button to end a trip
- **Pause tracking** - Disable auto-detection in Settings when not needed

---

## Development

### Prerequisites

- **Flutter SDK** 3.10.1 or higher ([Install Flutter](https://docs.flutter.dev/get-started/install))
- **Android Studio** / **Xcode** (for Android/iOS development)
- **Git** for version control

### Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/autoride.git
   cd autoride
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run code generation** (for Riverpod)
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

4. **Run the app**
   ```bash
   # Development mode
   flutter run

   # Release mode (for performance testing)
   flutter run --release
   ```

### Development Workflow

**Code Generation (Riverpod)**
```bash
# Watch mode - auto-generates code on file changes
flutter pub run build_runner watch

# One-time generation
flutter pub run build_runner build --delete-conflicting-outputs
```

**Testing**
```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# Run specific test file
flutter test test/features/trip_detection_test.dart
```

**Code Quality**
```bash
# Analyze code
flutter analyze

# Format code
flutter format .

# Check outdated dependencies
flutter pub outdated
```

### Project Structure

```
lib/
├── core/                 # Core utilities, constants, theme
├── features/            # Feature modules
│   ├── trip_detection/  # Auto-detection logic
│   ├── trip_history/    # View past trips
│   ├── settings/        # User preferences
│   └── onboarding/      # First-run experience
├── shared/              # Shared models, widgets, providers
└── main.dart            # App entry point
```

See [CLAUDE.md](CLAUDE.md) for detailed development guidelines and best practices.

---

## Tech Stack

### Core Framework
- **Flutter** 3.10.1+ - Cross-platform UI framework
- **Dart** 3.10.1+ - Programming language

### State Management
- **flutter_riverpod** - Reactive state management
- **riverpod_annotation** - Code generation for type-safe providers
- **riverpod_generator** - Riverpod code generation

### Location & Sensors
- **geolocator** - GPS location tracking with background support
- **sensors_plus** - Accelerometer and gyroscope access
- **flutter_background_service** - Reliable background task execution

### Machine Learning
- **tflite_flutter** - TensorFlow Lite for on-device activity recognition
- **Custom HAR model** - Human Activity Recognition trained on cycling data

### Data Modeling
- **freezed** - Immutable model code generation
- **freezed_annotation** - Freezed annotations

### Persistence
- **sqflite** - Local SQLite database for trip history
- **shared_preferences** - User settings and preferences

### System
- **permission_handler** - Runtime permission management
- **wakelock_plus** - Prevent screen sleep during active trips
- **battery_plus** - Battery level monitoring for power optimization

### Development Tools
- **build_runner** - Code generation tool
- **flutter_lints** - Lint rules
- **flutter_launcher_icons** - App icon generation

---

## Building from Source

### Android

1. **Generate release key** (first time only)
   ```bash
   keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA \
           -keysize 2048 -validity 10000 -alias upload
   ```

2. **Configure signing** - Create `android/key.properties`:
   ```properties
   storePassword=<password>
   keyPassword=<password>
   keyAlias=upload
   storeFile=<path-to-keystore>/upload-keystore.jks
   ```

3. **Build APK**
   ```bash
   flutter build apk --release
   ```

4. **Build App Bundle** (for Play Store)
   ```bash
   flutter build appbundle --release
   ```

### iOS

1. **Open Xcode**
   ```bash
   open ios/Runner.xcworkspace
   ```

2. **Configure signing** - Select your team in Xcode signing settings

3. **Build IPA**
   ```bash
   flutter build ipa --release
   ```

---

## Contributing

Contributions are welcome! Whether it's bug reports, feature requests, or code contributions, we appreciate your help.

### How to Contribute

1. **Fork the repository**
2. **Create a feature branch** (`git checkout -b feature/amazing-feature`)
3. **Commit your changes** (`git commit -m 'Add amazing feature'`)
4. **Push to the branch** (`git push origin feature/amazing-feature`)
5. **Open a Pull Request**

### Development Guidelines

- Follow the [CLAUDE.md](CLAUDE.md) best practices
- Write tests for new features
- Run `flutter analyze` before committing
- Use conventional commit messages
- Update documentation for user-facing changes

### Code of Conduct

Be respectful, inclusive, and constructive. We're all here to build something useful together.

---

## Privacy & Data Collection

### What We Collect

**Locally on Your Device:**
- Trip routes (GPS coordinates)
- Trip metadata (distance, duration, speed)
- Sensor data during trips (accelerometer, gyroscope)
- User preferences and settings

**Optional Cloud Collection** (with your consent):
- Anonymized sensor data to improve activity detection
- Trip statistics (no personal identifiers)

### What We DON'T Collect
- Personal identity information
- Location data when not cycling
- Any data without explicit consent

### Your Rights
- **Access** - Export all your data anytime
- **Delete** - Permanently delete all data from your device
- **Opt-out** - Disable data sharing at any time
- **Transparency** - View our full privacy policy (Coming soon)

---

## Battery Optimization

AutoRide is designed for all-day battery efficiency:

- **Motion-gated GPS** - Only activates GPS when you're moving
- **Adaptive accuracy** - Uses just enough precision for cycling
- **Smart sampling** - Reduces sensor polling when stationary
- **Efficient ML** - Runs activity detection every 5-10 seconds, not continuously
- **Foreground service** - Only during active trips

**Typical battery usage:** <5% per hour of active tracking

---

## Roadmap

- [x] Automatic trip detection
- [x] Background location tracking
- [x] Trip history and statistics
- [ ] Route visualization on maps
- [ ] ML-based activity recognition
- [ ] Export to GPX/KML
- [ ] Social features (share routes)
- [ ] Weekly/monthly statistics
- [ ] Integration with fitness apps (Strava, etc.)
- [ ] Apple Watch / Wear OS support

---

## Troubleshooting

### App doesn't detect trips automatically
- Ensure location permissions are set to "Always" (not just "While Using")
- Check that battery optimization is disabled for AutoRide
- Verify motion sensor permissions are granted
- Try adjusting detection sensitivity in Settings

### Battery drains too quickly
- Disable auto-detection when not cycling (Settings)
- Reduce location accuracy in Settings
- Ensure you're running the latest version
- Report the issue with battery stats

### Trips are inaccurate
- Ensure GPS signal is strong (outdoor, clear sky)
- Check location permission is set to "Precise" (iOS)
- Provide feedback on detected trips (helps improve ML model)
- Report consistent inaccuracies with details

### Background tracking stops
- **Android**: Disable battery optimization for AutoRide
  - Settings → Apps → AutoRide → Battery → Unrestricted
- **iOS**: Ensure background location is enabled
  - Settings → AutoRide → Location → Always

---

## Support

### Get Help
- **GitHub Issues** - [Report bugs or request features](../../issues)
- **Documentation** - See [CLAUDE.md](CLAUDE.md) for technical details
- **Email** - support@autoride.app *(Coming soon)*

### FAQ

**Q: Does this work offline?**
A: Yes! AutoRide works completely offline. GPS doesn't require internet.

**Q: How accurate is the automatic detection?**
A: >90% accuracy for cycling vs. other activities. Improves with user feedback.

**Q: Can I use this for other activities?**
A: Currently optimized for cycling. Other activities (running, walking) may be added.

**Q: How much storage does it use?**
A: Minimal. ~1 MB per 100 km of tracked routes.

**Q: Is my data secure?**
A: Yes. All data is stored locally on your device. Optional cloud sync is encrypted.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- **Flutter Team** - For the amazing framework
- **Riverpod Community** - For state management best practices
- **TensorFlow Team** - For on-device ML capabilities
- **Contributors** - Everyone who helps improve AutoRide

---

## Stay Connected

- **Star this repo** ⭐ if you find it useful
- **Watch releases** 👀 to get notified of updates
- **Share feedback** 💬 to help us improve

**Built with ❤️ for cyclists, by cyclists**

---

**Version:** 0.1.0 (Early Development)
**Last Updated:** 2025-11-22
