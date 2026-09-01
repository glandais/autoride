# AutoRide - Project Tasks

**Purpose**: High-level task tracking for AutoRide development. This file tracks overall progress and references detailed task documents in the `tasks/` folder.

**Important**: This file contains only task summaries. Detailed implementation guides are created on-demand in separate `.md` files within this directory.

---

## Task Progression Workflow

1. **Review** this TASKS.md to understand current progress
2. **Select** a task to work on (start with ☐ Pending tasks)
3. **Request** detailed task document: "Create detailed task for [TASK_ID]"
4. **Implement** following the detailed task guide
5. **Update** task status in this file (☐ → ⏳ → ✅)
6. **Commit** changes and move to next task

**Status Indicators**:
- ☐ **Pending** - Not started
- ⏳ **In Progress** - Currently working on
- ✅ **Complete** - Finished and tested
- ⚠️ **Blocked** - Waiting on dependency or decision

---

## Phase 1: Foundation & Setup

### 1.1 Project Infrastructure
- ✅ **T001**: Project Setup & Dependencies
  - *Detail*: `tasks/T001-project-setup.md`
  - *Scope*: Add dependencies, configure pubspec.yaml, project structure
  - *Dependencies*: None
  - *Estimate*: 1-2 hours

- ✅ **T002**: Feature-First Directory Structure
  - *Detail*: `tasks/T002-directory-structure.md`
  - *Scope*: Create core/, features/, shared/ directories with initial files
  - *Dependencies*: T001
  - *Estimate*: 30 min

- ✅ **T003**: Riverpod Code Generation Setup
  - *Detail*: `tasks/T003-riverpod-setup.md`
  - *Scope*: Configure build_runner, create first provider example
  - *Dependencies*: T001
  - *Estimate*: 1 hour

---

## Phase 2: Core Location & Sensors

### 2.1 Location Tracking
- ✅ **T004**: Basic Location Service
  - *Detail*: `tasks/T004-location-service.md`
  - *Scope*: Implement geolocator integration, location provider, permission check
  - *Dependencies*: T001, T003
  - *Estimate*: 2-3 hours

- ✅ **T005**: Background Location Tracking
  - *Detail*: `tasks/T005-background-location.md`
  - *Scope*: Configure flutter_background_service, foreground service, platform setup
  - *Dependencies*: T004
  - *Estimate*: 3-4 hours

- ⏳ **T006**: Battery-Optimized Location Strategy
  - *Detail*: `tasks/T006-battery-optimization.md`
  - *Scope*: Adaptive accuracy, distance filtering, motion-gated GPS
  - *Dependencies*: T005, T007
  - *Estimate*: 2-3 hours
  - *Status*: implemented in T041 part 2 (`529db42`) — GPS gating lives in the coordinator (GPSController deleted), power modes drive location settings and sensor rates. Awaiting `tasks/T041-device-validation.md` items 1 and 4 before ✅

### 2.2 Motion Detection
- ✅ **T007**: Sensor Integration (Accelerometer/Gyroscope)
  - *Detail*: `tasks/T007-sensor-integration.md`
  - *Scope*: sensors_plus setup, motion data provider, basic movement detection
  - *Dependencies*: T003
  - *Estimate*: 2-3 hours

- ✅ **T008**: Cycling Motion Pattern Detection
  - *Detail*: `tasks/T008-cycling-detection.md`
  - *Scope*: Implement cycling-specific motion patterns, threshold tuning
  - *Dependencies*: T007
  - *Estimate*: 3-4 hours

---

## Phase 3: Data Management

### 3.1 Database & Persistence
- ✅ **T009**: SQLite Database Schema
  - *Detail*: `tasks/T009-database-schema.md`
  - *Scope*: Create trips/route_points tables, repository pattern
  - *Dependencies*: T001
  - *Estimate*: 2 hours

- ✅ **T010**: Trip Repository Implementation
  - *Detail*: `tasks/T010-trip-repository.md`
  - *Scope*: CRUD operations, trip history queries, Riverpod integration
  - *Dependencies*: T009, T003
  - *Estimate*: 2-3 hours

- ✅ **T011**: Settings & Preferences
  - *Detail*: `tasks/T011-settings-management.md`
  - *Scope*: SharedPreferences setup, settings provider, user preferences
  - *Dependencies*: T003
  - *Estimate*: 1-2 hours

---

## Phase 4: Trip Detection Logic

### 4.1 Core Detection
- ✅ **T012**: Trip State Machine
  - *Detail*: `tasks/T012-trip-state-machine.md`
  - *Scope*: Idle/Detecting/Active/Paused states, state transitions
  - *Dependencies*: T007, T008
  - *Estimate*: 2-3 hours

- ⏳ **T013**: Automatic Trip Start Detection
  - *Detail*: `tasks/T013-trip-start-detection.md`
  - *Scope*: Combine motion + GPS for automatic trip start
  - *Dependencies*: T004, T008, T012
  - *Estimate*: 3-4 hours
  - *Completed*: 2025-11-22 (detector logic only)
  - *Status*: implemented in T041 part 3 (`da3ad62`) — `AutoDetectionController` starts the coordinator from the new `automaticDetectionEnabled` setting + permissions; manual start button added; auto-pause/stop reachable during a trip. Awaiting `tasks/T041-device-validation.md` before ✅

- ✅ **T014**: Automatic Trip Stop Detection
  - *Detail*: `tasks/T014-trip-stop-detection.md`
  - *Scope*: Detect trip end (stationary threshold, timeout logic)
  - *Dependencies*: T013
  - *Estimate*: 2-3 hours
  - *Completed*: 2025-11-22

- ✅ **T015**: Trip Data Recording
  - *Detail*: `tasks/T015-trip-recording.md`
  - *Scope*: Record route points, calculate distance/duration/speed
  - *Dependencies*: T010, T013
  - *Estimate*: 2-3 hours
  - *Completed*: 2025-11-22

---

## Phase 5: Machine Learning (HAR)

### 5.1 ML Infrastructure
- ☐ **T016**: TensorFlow Lite Integration
  - *Detail*: `tasks/T016-tflite-setup.md` (create on request)
  - *Scope*: Add tflite_flutter, model asset setup, interpreter initialization
  - *Dependencies*: T001
  - *Estimate*: 2 hours

- ☐ **T017**: Activity Classifier Implementation
  - *Detail*: `tasks/T017-activity-classifier.md` (create on request)
  - *Scope*: Preprocessing, inference, prediction parsing
  - *Dependencies*: T016, T007
  - *Estimate*: 3-4 hours

- ☐ **T018**: HAR Model Training Pipeline (Python)
  - *Detail*: `tasks/T018-model-training.md` (create on request)
  - *Scope*: Data collection, model training, TFLite conversion
  - *Dependencies*: T017
  - *Estimate*: 8-12 hours (separate Python project)

- ☐ **T019**: Activity Classification Integration
  - *Detail*: `tasks/T019-classification-integration.md` (create on request)
  - *Scope*: Integrate classifier into trip detection flow
  - *Dependencies*: T017, T013
  - *Estimate*: 2-3 hours

---

## Phase 6: User Interface

### 6.1 Core UI Screens
- ✅ **T020**: App Theme & Design System
  - *Detail*: `tasks/T020-theme-design.md`
  - *Scope*: Color scheme, typography, shared widgets
  - *Dependencies*: T001
  - *Estimate*: 2-3 hours
  - *Completed*: 2025-11-22

- ✅ **T021**: Onboarding Flow
  - *Detail*: `tasks/T021_onboarding_flow.md`
  - *Scope*: Welcome screens, permission requests, initial setup
  - *Dependencies*: T020
  - *Estimate*: 3-4 hours
  - *Completed*: 2025-11-22

- ✅ **T022**: Trip Tracking Screen (Active Trip)
  - *Detail*: `tasks/T022-tracking-screen.md`
  - *Scope*: Real-time stats, map view, start/stop controls
  - *Dependencies*: T015, T020
  - *Estimate*: 4-5 hours
  - *Completed*: 2025-11-22

- ✅ **T023**: Trip History Screen
  - *Detail*: `tasks/T023_trip_history_screen.md`
  - *Scope*: List view, trip details, route map
  - *Dependencies*: T010, T020
  - *Estimate*: 3-4 hours
  - *Completed*: 2025-11-23

- ✅ **T024**: Settings Screen
  - *Detail*: `tasks/T024-settings-screen.md`
  - *Scope*: Preferences, permissions, data management
  - *Dependencies*: T011, T020
  - *Estimate*: 2-3 hours
  - *Completed*: 2025-11-23

### 6.2 UI Polish
- ✅ **T025**: Notifications & Foreground Service UI
  - *Detail*: `tasks/T025-notifications.md`
  - *Scope*: Trip progress notification, service controls
  - *Dependencies*: T005, T022
  - *Estimate*: 2 hours
  - *Started*: 2025-11-23
  - *Completed*: 2025-11-23

- ✅ **T026**: Loading States & Error Handling
  - *Detail*: `tasks/T026-loading-errors.md`
  - *Scope*: Loading indicators, error messages, retry logic
  - *Dependencies*: T020
  - *Estimate*: 2 hours
  - *Started*: 2025-11-23
  - *Completed*: 2025-11-23

---

## Phase 7: Permissions & Platform

### 7.1 Permission Management
- ✅ **T027**: Permission Handler Implementation
  - *Detail*: `tasks/T027-permission-handler.md`
  - *Scope*: Progressive permission requests, rationale dialogs
  - *Dependencies*: T003
  - *Estimate*: 2-3 hours
  - *Completed*: 2025-11-23

- ✅ **T028**: Platform-Specific Configuration
  - *Detail*: `tasks/T028-platform-config.md`
  - *Scope*: AndroidManifest.xml, Info.plist, capabilities, platform info service
  - *Dependencies*: T027
  - *Estimate*: 1-2 hours
  - *Completed*: 2025-11-23

---

## Phase 8: Testing & Quality

### 8.1 Automated Testing
- ✅ **T029**: Unit Tests (Business Logic)
  - *Detail*: `tasks/T029-unit-tests.md` (create on request)
  - *Scope*: Repository, state machine, calculations
  - *Dependencies*: T010, T012
  - *Estimate*: 3-4 hours
  - *Completed*: 2026-09-01 (`a3dd31c`, on top of T041's coordinator/recorder tests) — suite recut: every test file exercises the unit it is named for, database tests run the production schema (duplicated DDL helper deleted), 331 tests total (ledger L-011 test side, L-014, L-015, L-026)

- ⏳ **T030**: Widget Tests (UI Components)
  - *Detail*: `tasks/T030-widget-tests.md` (create on request)
  - *Scope*: Screen tests with mocked providers
  - *Dependencies*: T022, T023, T024
  - *Estimate*: 3-4 hours
  - *Status*: started 2026-09-01 (`99eae4c`) — 25 widget tests with shared fakes in `test/helpers/widget/`: onboarding permission flow, tracking screen, HomeShell session guarantee (ledger L-013). Remaining: settings screen, trip history/detail, InitialRouteScreen, map interactions

- ☐ **T031**: Integration Tests (E2E Flow)
  - *Detail*: `tasks/T031-integration-tests.md` (create on request)
  - *Scope*: Complete trip detection flow
  - *Dependencies*: T015, T022
  - *Estimate*: 4-5 hours

### 8.2 Performance & Quality
- ☐ **T032**: Battery Profiling & Optimization
  - *Detail*: `tasks/T032-battery-profiling.md` (create on request)
  - *Scope*: Profile battery usage, optimize GPS/sensor sampling
  - *Dependencies*: T006, T015
  - *Estimate*: 3-4 hours

- ✅ **T033**: Code Quality & Linting
  - *Detail*: `tasks/T033-code-quality.md` (create on request)
  - *Scope*: flutter analyze, code formatting, linting rules
  - *Dependencies*: All implementation tasks
  - *Estimate*: 2 hours
  - *Completed*: 2026-09-01 — analyze clean under the curated lint set with real strict modes (`strict-casts`/`strict-raw-types` since `11e74b7`, ledger L-042). The CI formatting gate is tracked under ledger step 6 (L-050), not here. This resolves the T038/T039 dependency caveat (L-053): the dependency is now satisfied.

---

## Phase 9: Data Collection & ML Improvement

### 9.1 Training Data Pipeline
- ☐ **T034**: Data Collection Service
  - *Detail*: `tasks/T034-data-collection.md` (create on request)
  - *Scope*: Anonymized sensor data collection, user consent
  - *Dependencies*: T015, T017
  - *Estimate*: 3-4 hours

- ☐ **T035**: Training Data Export
  - *Detail*: `tasks/T035-data-export.md` (create on request)
  - *Scope*: Export to CSV/JSON for model retraining
  - *Dependencies*: T034
  - *Estimate*: 2 hours

---

## Phase 10: Release Preparation

### 10.1 Documentation & Assets
- ✅ **T036**: App Icons & Splash Screen
  - *Detail*: `tasks/T036-app-assets.md`
  - *Scope*: Master artwork + reproducible generation script, iOS icon set, Android legacy + adaptive icons, branded launch screen (incl. Android 12+ SplashScreen API)
  - *Dependencies*: T020
  - *Estimate*: 2-3 hours (actual ~2h)

- ⏳ **T037**: Privacy Policy & Terms
  - *Detail*: `tasks/T037-privacy-policy.md`
  - *Scope*: Privacy policy, terms of use, LICENSE, `store-metadata/data-safety.md` (source of truth for both stores' privacy declarations)
  - *Dependencies*: None — the former T034 dependency is resolved in `T037-privacy-policy.md` §1 (the policy documents today's behaviour; `data-safety.md` §7 lists what T034 will force to be re-declared)
  - *Estimate*: 2-3 hours (documents ✅ done) + ~2 hours for the 6 code changes in §5
  - *Blocks*: T038 (Play needs the policy URL + background-location declaration), T039 (ASC App Privacy answers)

### 10.2 Release Build
- ⏳ **T038**: Android Release Configuration
  - *Detail*: `tasks/T038-android-release.md`
  - *Scope*: `X.Y.Z+N` version scheme, keystore signing, ProGuard/R8, fastlane + Play internal track, `publish_beta.sh`
  - *Dependencies*: T033, T036
  - *Estimate*: 3-4 hours
  - *Done in-repo*: `version: 1.0.0+1`; `key.properties` read by Gradle with a loud-fallback release signing config; `minSdk` pinned to 26; `android:label="AutoRide"`; `key.properties.example`; `android/Gemfile(.lock)` + `fastlane/{Appfile,Fastfile}` (`internal`/`metadata`/`deploy` lanes); `fastlane/metadata/android/en-US/` listing copy + 512² icon; `publish_beta.sh` with the bump guards; README build/publish sections rewritten
  - *Also fixed*: the Gradle wrapper was pinned at 8.14 while AGP 9.3.0 requires 9.5.0 — `flutter build appbundle --release` failed at plugin resolution before any of this task's changes. Wrapper bumped; upstream `develop` has since moved it to 9.7.1, which also satisfies the requirement.
  - *Deferred*: R8/minification stays off (D6) — its failures are runtime-only and gating it on a physical-device smoke test is the point; rationale is in a comment in `android/app/build.gradle.kts`
  - *Play Console done*: app record `AutoRide: Bike Trip Tracker` created (app ID `4975962567441094743`, package available, en-US, App, Free); internal testing track page reachable; API auth verified (`validate_play_store_json_key` → "Successfully established connection")
  - *Remaining (manual, Play Console)*: add at least one internal tester, Data safety form, background-location declaration (needs T037's policy URL + a screencast), accept Play App Signing. Then the first `./publish_beta.sh` run produces the release commit + tag.
  - *Shared credentials with the sibling `tribly` project* (both outside git, by design):
    - upload keystore — `android/key.properties` (gitignored) → `~/Documents/pedalons/android/tribly-release.keystore`, alias `tribly`. Verified: a release AAB carries SHA-256 `26:24:FF:9B:9E:62:FA:C2:...`, i.e. `CN=Landais Gabriel`, not `CN=Android Debug`.
    - Play service account — `~/.secrets/autoride-play.json` is a **symlink** to tribly's `pedalons-play-store-b3697e930223.json` (`fastlane-supply@pedalons-play-store.iam.gserviceaccount.com`). It holds account-level Administrator, so it already covers this app. Consequence to accept knowingly: one leaked key can publish both Pedalons and AutoRide.

- ⏳ **T039**: iOS Release Configuration
  - *Detail*: `tasks/T039-ios-release.md`
  - *Scope*: Signing, capabilities, export compliance, privacy manifest reconciliation, fastlane + TestFlight
  - *Dependencies*: **T038** (owns the version scheme and `publish_beta.sh`), T033, T036
  - *Estimate*: 3-4 hours
  - *Status 2026-09-01*: **pipeline proven end-to-end** — TestFlight build 3 uploaded and VALID via `fastlane beta` (April's App Store profile reused, no signing repair needed); build `1.0.0+4` (with the `856f7a8` crash fix) launched through the first full dual-platform `publish_beta.sh` run. Credentials wired via `~/.secrets/autoride-asc.env` (`0966a0c`). Store surface cleared by agents: name **AutoRide**, version `1.0.0`, full metadata, **App Privacy published**, age rating 4+, content rights, free + 175 territories, App Review contact + notes filed — `asc validate` down from 33 errors to **2** (attach a build — use build 4, build 3 carries the crash — and screenshots). Remaining beyond that: privacy-manifest reconciliation (detail doc step 6), Motion & Fitness prompt still unverified on device (SPM finding below — location/notification prompts confirmed OK on iPhone)
  - *⚠️ New finding*: Flutter 3.47 resolves `permission_handler_apple` via Swift Package Manager, so the Podfile's `PERMISSION_*` post_install macros no longer reach it — the cc1c088 permission fix is bypassed. iOS permission prompts must be re-verified on device (see `tasks/T041-device-validation.md` item 7); plausible TestFlight blocker — **resolved 2026-09-01 for location and notifications**: the plugin's `Package.swift` derives the flags from `Info.plist`, so the Podfile macros are dead but nothing is bypassed; motion prompt still unverified

- ✅ **Build-chain alignment with `../tribly/mobile`** (2026-09-01)
  - *Why*: both apps share one release mechanic, and autoride's was modelled on tribly's (T038 "Reference Implementation"). They had drifted — but **not in one direction**: on release plumbing autoride is ahead (non-expiring ASC API key vs tribly's Apple ID session, `~/.secrets` + env-var Play credentials vs a hardcoded absolute path, guarded `publish_beta.sh` with a rollback trap and tag vs a minimal script). Those were deliberately **not** imported.
  - *Imported from tribly*: `ios/.bundle/config` + `android/.bundle/config` (`BUNDLE_PATH: vendor/bundle` — both `.gitignore`s already ignored `vendor/bundle/` and explained why, but the file enabling it was missing, so `bundle install` hit the very EACCES the comment described); `check.sh` as a standalone quality gate, now also called by `publish_beta.sh` so the gates have one definition; `(cd android && ./gradlew --stop)` after the Android upload (the daemon otherwise outlives the release holding JDK 21); `clean.sh` now regenerates code, so `./clean.sh && flutter analyze` no longer fails; CI `build-android` + `build-ios` jobs (closes L-018); dependabot `bundler` ecosystem for the two fastlane Gemfiles.
  - *Deliberately NOT aligned*: Gradle/AGP versions (autoride stays on Gradle 9.7.1 / AGP 9.3.2 / `builtInKotlin=true`, tribly on 8.14.5 / 8.13.0 — neither project moves); the CocoaPods→SPM migration tribly completed; the Dart SDK constraint; tribly itself (no file in that repo was touched).
  - *L-050, format half closed*: the 103-file formatting backlog under `lib/`+`test/` was cleared in its own commit (`834451f`, recorded in `.git-blame-ignore-revs`), and `check.sh` now enforces `dart format --set-exit-if-changed`. Coverage collection and `flutter pub get --enforce-lockfile` remain open.
  - *Unvalidated*: the two new CI jobs have never run. Three assumptions to confirm on the first PR — SDK platform 37 installs on the runner, the capped heap survives AGP 9, and `macos-latest`'s default Xcode still builds against `IPHONEOS_DEPLOYMENT_TARGET = 15.0`.

- ☐ **T040**: Beta Testing & Feedback
  - *Detail*: `tasks/T040-beta-testing.md` (create on request)
  - *Scope*: TestFlight/Internal Testing, collect feedback
  - *Dependencies*: T038, T039
  - *Estimate*: Ongoing

---

## Phase 11: Audit Backlog

### 11.1 Core Pipeline
- ⏳ **T041**: Core Tracking-Pipeline Refactor
  - *Detail*: `tasks/BLOCKED-pipeline-refactor.md`
  - *Scope*: The deferred audit cluster — #5 providerize the six direct stream call sites → #2 session ownership for the recorder/state machine/coordinator → #3 real motion-gated GPS → #4 apply adaptive settings → #11 a live entry point for auto-detection (plus a manual start control) → #7/#8 one source of truth between the background isolate and the foreground stream. Maps to ledger L-001…L-011.
  - *Dependencies*: T006, T013, T015 — and the three maintainer decisions below
  - *Estimate*: multi-session; land one dependency-chain step at a time, validating each on-device
  - *Decisions (maintainer, 2026-08-31)*: (a) session lifetime = scoped `ref.keepAlive()` opened on start, released on stop/error/dispose (note: Riverpod 3 deactivates `ref.listen` subscriptions when the last listener leaves, so session streams are container-owned); (b) GPS gating inside the coordinator, `GPSController` deleted; (c) auto-detection setting-gated (`automaticDetectionEnabled`, default ON); (d) foreground stream is the single source of truth — the background isolate only holds the foreground-service notification.
  - *Status*: **code complete** — landed in three commits per the dependency order: `7afb833` (#5 providerize + #2 sessions), `529db42` (#3 gating + #4 adaptive), `da3ad62` (#11 entry point + #7/#8 isolate). 245 tests, analyze clean.
  - *Validation*: **physical device required** — see `tasks/T041-device-validation.md`. T041 closes only when that checklist passes.
  - *2026-09-01 (`4559820`)*: background-location status surfaced — `backgroundLocationStatusProvider` (OS grant + accuracy), home banner and settings switch bound to it, platform-specific "Always" / "Precise Location" guidance with a settings link; `PermissionRationaleDialog.show` double-pop fixed. Verified on iPhone 13 Pro (ledger L-071, validation item 6).
  - *References*: `tasks/BLOCKED-pipeline-refactor.md` (decisions + dependency order), `tasks/AUDIT-FINDINGS.md` (2026-06-17, deferred cluster), `tasks/LEDGER.md` (2026-08-31, §3 findings and §5 step 4)
  - *Retires*: the blocked halves of T006 and T013; unblocks T032 and the recorder/coordinator tests under T029/T031

---

## Progress Summary

**Total Tasks**: 41
**Completed**: 25
**In Progress**: 7 (T006, T013, T030, T037, T038, T039, T041)
**Pending**: 9
**Blocked**: 0

**Current Phase**: Phase 10 - Release Preparation, alongside the Phase 11 audit backlog
**Last Completed**: T029/T033 - test-suite recut and code quality (2026-09-01)
**Current Task**: T039/T041 — iOS release is 2 blockers from submittable (build attach + screenshots); T041 device validation under way (first iPhone run done: prompts OK, one crash found and fixed — see `tasks/T041-device-validation.md`). T038 open on manual Play Console setup; T037 open (§5.6/§5.7).
**Next Task**: T039 - iOS Release Configuration (T038 now owns the version scheme and `publish_beta.sh`, so T039 can extend both)
**Audit backlog**: `tasks/AUDIT-FINDINGS.md` (2026-06-17) and `tasks/LEDGER.md` (2026-08-31) record open defects that are not otherwise tracked here; the blocked core-pipeline cluster is T041.

---

## How to Use This File

### Starting a New Task
1. Identify next pending task (☐)
2. Request detailed task document:
   ```
   "Create detailed task for T001"
   ```
3. Detailed task `.md` file will be created in `tasks/` folder
4. Update task status to ⏳ In Progress
5. Follow detailed task guide

### Completing a Task
1. Test implementation thoroughly
2. Run `flutter analyze` and fix issues
3. Update task status to ✅ Complete
4. Commit changes with task ID:
   ```bash
   git commit -m "T001: Project setup and dependencies"
   ```
5. Update progress summary

### Blocking a Task
1. Update task status to ⚠️ Blocked
2. Add blocking reason in task notes
3. Move to next unblocked task
4. Resolve blocker and update status

---

## Notes

- Task estimates are approximate - adjust based on experience
- Dependencies are critical - complete prerequisite tasks first
- Create detailed task documents only when needed (on-demand)
- Keep this file updated as single source of truth for progress
- Review and update task list as project evolves

---

**Last Updated**: 2026-09-01
**Version**: 1.2
