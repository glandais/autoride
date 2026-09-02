# AutoRide

**Automatically detect and record your bike trips with intelligent motion sensing.**

AutoRide is a privacy-focused mobile app that uses motion sensing to automatically recognize when you're cycling and record your trips—no manual start/stop required.

> ⚠️ **Status: in development.** The automatic detection pipeline is not yet wired to a live
> entry point, so the shipped build cannot start a trip. See `tasks/LEDGER.md` and task **T041**.
> Sections below marked *(planned)* describe work that is not implemented yet.

[![Flutter](https://img.shields.io/badge/Flutter-3.47.2+-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20Android-lightgrey)](#)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Features

### Automatic Trip Detection
- **Zero-touch tracking** - Automatically detects when you start cycling
- **Smart motion sensing** - Uses accelerometer and gyroscope to identify cycling patterns
- **Battery optimized** - Intelligent GPS management for all-day tracking
- **Background tracking** - Records trips even when your phone is locked

### Activity Recognition *(planned — T016–T019)*
- **ML-powered detection** - Distinguish cycling from walking, driving, or standing still
- **Adaptive learning** - Improve accuracy over time with user feedback
- **Confidence scoring** - Show how certain the app is about detected activities

None of the above ships today: there is no on-device model and no TensorFlow Lite code path.
The current build scores cycling from accelerometer/gyroscope thresholds only.

### Trip Management
- **Detailed trip history** - View all your past rides with routes, distance, and duration
- **Route mapping** - See your exact path on an interactive map
- **Statistics** - Track total distance, time spent cycling, and more
- **Export data** - Download your trip data for analysis

### Privacy First
- **Local storage** - All trip data stored on your device
- **No cloud** - No account, no server, no sync; the app works fully offline except for map tiles
- **No tracking** - We don't track you or sell your data
- **Full control** - Delete your data anytime

---

## Screenshots

> 📸 Coming soon - App is currently in development

---

## Installation

### For End Users

#### Android
There is no download yet — no public release, no GitHub release APK, and **no closed beta
either**: the Play internal-testing track is configured but nothing has been published to it,
so there is no tester invitation to request today.

The only way to run AutoRide right now is to [build it from source](#building-from-source).

#### iOS
1. Download from the App Store *(Coming soon)*
2. Grant location permissions when prompted
3. Enable background location for automatic tracking
4. Start cycling!

### Permissions Required

**Android:**
- **Location** (Fine & Background) - Required to track your route
- **Notifications** - Required on Android 13+ for the ongoing tracking notification
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
- *(Planned)* Confirm activity type if detection was incorrect

### Manual Control
- **Pause / resume / stop** - Available on the tracking screen for a trip in progress
- **Force start** *(planned — T041)* - There is no manual start control yet; the tracking
  screen can only act on a trip that is already running
- **Pause tracking** - Disable auto-detection in Settings when not needed

---

## Development

### Prerequisites

- **Flutter SDK** 3.47.2 or higher (ships Dart 3.13, required by `freezed` ^4) ([Install Flutter](https://docs.flutter.dev/get-started/install))
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
   dart run build_runner build --delete-conflicting-outputs
   ```

4. **Run the app**
   ```bash
   # Development mode
   flutter run

   # Release mode (for performance testing)
   flutter run --release
   ```

### Development Workflow

**Quality gates (all of them, in order)**
```bash
# pub get -> code generation -> format check -> analyze -> test. This is exactly what CI runs
# and what ./publish_beta.sh runs before it will publish anything.
./check.sh

# One-time per clone: keep the bulk-reformatting commit out of `git blame`.
git config blame.ignoreRevsFile .git-blame-ignore-revs
```

**Code Generation (Riverpod)**
```bash
# Watch mode - auto-generates code on file changes
dart run build_runner watch

# One-time generation (this is what CI runs)
dart run build_runner build --delete-conflicting-outputs
```

**Testing**
```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# Run specific test file
flutter test test/features/trip_detection/data/services/trip_stop_detector_test.dart
```

**Code Quality**
```bash
# Analyze code
flutter analyze

# Format code
dart format .

# Check outdated dependencies
flutter pub outdated
```

**Battery profiling** (sensors and GPS only behave realistically on a physical device)
```bash
# Run on a real phone, in release mode — debug builds distort drain
flutter run --release

# Follow the device logs while riding
flutter logs --verbose
```

Then read the energy trace: **Android** — Android Studio → Profiler → Energy;
**iOS** — Xcode → Debug Navigator → Energy Impact. The target is < 5 % drain per hour
of active tracking; see `tasks/T041-device-validation.md` item 4 for the measurement
protocol (it requires the diagnostic log at `normal` level, and a control run).

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
- **Flutter** 3.47.2+ - Cross-platform UI framework
- **Dart** 3.13+ - Programming language

### State Management
- **flutter_riverpod** - Reactive state management
- **riverpod_annotation** - Code generation for type-safe providers
- **riverpod_generator** - Riverpod code generation

### Location & Sensors
- **geolocator** - GPS location tracking with background support
- **sensors_plus** - Accelerometer and gyroscope access
- **flutter_background_service** - Reliable background task execution

### Machine Learning *(planned — T016–T019)*
- **tflite_flutter** - Declared in `pubspec.yaml`, but not imported anywhere in `lib/` yet
- **Custom HAR model** - Not built; no model asset exists in the repository

### Data Modeling
- **freezed** - Immutable model code generation
- **freezed_annotation** - Freezed annotations

### Persistence
- **sqflite** - Local SQLite database for trip history
- **shared_preferences** - User settings and preferences

### System
- **permission_handler** - Runtime permission management
- **battery_plus** - Battery level monitoring for power optimization

### Development Tools
- **build_runner** - Code generation tool
- **flutter_lints** - Lint rules
- **flutter_launcher_icons** - App icon generation

---

## Building from Source

### Android

A release build works out of the box — without signing credentials it falls back to the debug
keystore so `flutter run --release` works on a fresh clone. That fallback is fine for local
testing and **rejected by Google Play**, so configure real signing before publishing anything.

1. **Generate an upload keystore** (first time only). Back it up offline: losing it means
   losing the ability to update the app on Play.
   ```bash
   keytool -genkey -v -keystore ~/.secrets/autoride-upload.jks -keyalg RSA \
           -keysize 2048 -validity 10000 -alias upload
   ```

2. **Configure signing** — copy `android/key.properties.example` to `android/key.properties`
   and fill it in. `storeFile` must be an absolute path. The real file is gitignored;
   `android/app/build.gradle.kts` reads it and picks the release signing config when it exists.
   ```bash
   cp android/key.properties.example android/key.properties
   $EDITOR android/key.properties
   ```

3. **Build**
   ```bash
   export JAVA_HOME="$(/usr/libexec/java_home -v 21)"   # Gradle/AGP are not validated on JDK 25
   flutter build apk --release
   flutter build appbundle --release                     # for Play
   ```

4. **Confirm the bundle is not debug-signed** — this is the check that catches the failure
   mode above, because a debug-signed build otherwise looks like it worked.
   ```bash
   keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab | head -20
   # Owner must be your keystore's DN, NOT "CN=Android Debug, O=Android, C=US"
   ```

### Publishing to Play (internal testing)

`./publish_beta.sh` is the only supported path. It bumps the build number in `pubspec.yaml`,
runs the quality gates, builds, uploads to the Play internal track via fastlane, then commits
and tags the release. It refuses to run on a dirty tree or without `android/key.properties`,
and rolls the version bump back if anything fails before an upload lands.

```bash
./publish_beta.sh
```

Requires a Play service-account JSON at `~/.secrets/autoride-play.json` (override with
`AUTORIDE_PLAY_JSON_KEY`). Validate it before the first run:

```bash
cd android && bundle install && bundle exec fastlane run validate_play_store_json_key
```

Promotion to production is deliberately manual: `fastlane deploy` exists but no script calls it.

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

📄 **[Privacy Policy](https://glandais.github.io/autoride/legal/privacy-policy.html)** ·
**[Terms of Use](https://glandais.github.io/autoride/legal/terms-of-service.html)**

### Stored on your device

- Trip routes (GPS coordinates, altitude, timestamps, accuracy, speed)
- Trip metadata (distance, duration, average and maximum speed, detected activity, confidence)
- Your preferences and settings

Nothing else is stored. Accelerometer and gyroscope readings are processed in memory to recognise
pedalling and are **never written to the trip database** — that is how GPS stays switched off
until you actually start riding. One caveat: the optional diagnostic log (Settings → Diagnostic
log, **off by default**) writes one *summary* per second — an average and a variability figure —
into its own database when set to "Verbose". The raw 50 Hz readings are never recorded at any
setting.

### What leaves your device

**Automatically, exactly one thing:** when you open a map, your device requests map images from
the OpenStreetMap Foundation's tile servers, which reveals your IP address and the map area you
are viewing to that third party. If you never open a map, the app makes **no network requests at
all**.

**On your explicit request:** two features write a file and hand it to your device's own share
sheet — **Export as FIT** on a trip, and **Export log** for the diagnostic log (which contains
your precise GPS positions, and asks you to confirm first). Nothing is sent until you pick a
destination, and the app never learns what you picked. See
[§3.3 of the Privacy Policy](https://glandais.github.io/autoride/legal/privacy-policy.html).

There is no AutoRide account, no AutoRide server, and no analytics, crash-reporting or advertising
SDK. Your trips are never uploaded — not to us, not to anyone.

### Your control

- **Delete** — Settings → Data Management → Clear all trips removes every trip and route point
- **Uninstall** — removes the database and all settings; nothing survives elsewhere
- **Revoke** — background location can be withdrawn in system settings, or turned off in the app,
  and manual recording keeps working

For the full detail, including the Android/iOS backup difference and the exact database contents,
see the [Privacy Policy](https://glandais.github.io/autoride/legal/privacy-policy.html).

---

## Battery Optimization

AutoRide is *designed* for all-day battery efficiency. This is the target architecture, not the
current behaviour — motion-gating and adaptive settings are written but not yet applied (T041):

- **Motion-gated GPS** *(planned)* - Only activate GPS when you're moving
- **Adaptive accuracy** *(planned)* - Use just enough precision for cycling
- **Smart sampling** *(planned)* - Reduce sensor polling when stationary
- **Foreground service** - Only during active trips

**Target battery usage:** <5% per hour of active tracking (not yet measured on device)

---

## Roadmap

- [ ] Automatic trip detection *(detector implemented, no live entry point yet — T041)*
- [ ] Background location tracking *(isolate implemented, not connected — T041)*
- [x] Trip history and statistics
- [x] Route visualization on maps
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
- On iOS, verify Motion & Fitness access is granted
- Try adjusting detection sensitivity in Settings

### Battery drains too quickly
- Disable auto-detection when not cycling (Settings)
- Reduce location accuracy in Settings
- Ensure you're running the latest version
- Report the issue with battery stats

### Trips are inaccurate
- Ensure GPS signal is strong (outdoor, clear sky)
- Check location permission is set to "Precise" (iOS)
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
A: Unknown — no accuracy has been measured yet. Detection is threshold-based today and has not
been validated on a physical device; there is no published accuracy figure to quote.

**Q: Can I use this for other activities?**
A: Currently optimized for cycling. Other activities (running, walking) may be added.

**Q: How much storage does it use?**
A: Minimal. ~1 MB per 100 km of tracked routes.

**Q: Is my data secure?**
A: All trip data stays in the app's private storage on your device — there is no cloud sync, so
there is nothing to intercept in transit. It is protected by your device's own screen lock and
encryption; the database itself is not separately encrypted, so use a passcode. Details in the
[Privacy Policy](https://glandais.github.io/autoride/legal/privacy-policy.html).

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

**Version:** see `version:` in `pubspec.yaml` (single source of truth for both platforms)
**Last Updated:** 2026-07-25
