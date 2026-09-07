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
- ⏳ **T034**: Data Collection Service — code complete, awaiting the device run
  - *Detail*: `tasks/T034-data-collection.md` (plan + decisions, 2026-09-03)
  - *Scope*: On-device raw sensor capture (3-axis accel + gyro) batched to one `raw` row per second at `lvl = 2`, `lbl` ground-truth labels, capture retention separate from the journal's, consent toggle re-added, separate capture export. **Not anonymized** — data stays local, see the detail file §5
  - *Shipped*: `capture_controller.dart`, `capture_session.dart`, `capture_section.dart`, audit schema v2 (`sess` column + `capture_sessions`), `AuditLog` level/capture split
  - *Remaining*: the device run of the detail file §8 — measured MB/h against the ~8 MB/h projection, battery note, and a labelled bike + non-bike session read back through the audit-log skill
  - *Dependencies*: T015, T017 (and the audit subsystem from T043/T047)
  - *Estimate*: 3-4 hours — revised to 6-8 h by the plan

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
  - *Validation*: **physical device required** — see `tasks/T041-device-validation.md`. T041 closes only when that checklist passes. Since T043 the checklist is run with the diagnostic log on, and items 1, 4, 8, 9, 10 and 11 are settled from the exported log rather than from a cable and an impression — see that file's section 0 for which level each item needs.
  - *2026-09-01 (`4559820`)*: background-location status surfaced — `backgroundLocationStatusProvider` (OS grant + accuracy), home banner and settings switch bound to it, platform-specific "Always" / "Precise Location" guidance with a settings link; `PermissionRationaleDialog.show` double-pop fixed. Verified on iPhone 13 Pro (ledger L-071, validation item 6).
  - *References*: `tasks/BLOCKED-pipeline-refactor.md` (decisions + dependency order), `tasks/AUDIT-FINDINGS.md` (2026-06-17, deferred cluster), `tasks/LEDGER.md` (2026-08-31, §3 findings and §5 step 4)
  - *Retires*: the blocked halves of T006 and T013; unblocks T032 and the recorder/coordinator tests under T029/T031

### 11.2 Field findings — control run without a ride (2026-09-02)

The first log of an outing with **no bike** (shopping on foot and by transport, both phones on
1.0.0+9, verbose log) is the false-positive control the T041 checklist never had. Expected: zero
trips. Observed: four trips of 0 m on the Pixel, and an outing the iPhone never saw. The diagnoses
are ledger §6 (L-079…L-086); the four tasks below group them into units that share one cause and one
acceptance test. **Diagnosis only at this stage — no solution has been chosen for any of them.**

- ☐ **T044**: Trip Start Decision — one departure, one trip, and only a real one
  - *Detail*: ledger L-079, L-080, L-081 (create `tasks/T044-trip-start-decision.md` on request)
  - *Partly done*: 2026-09-02 — **L-080 closed** by ledger remediation row 20. One departure can no longer become two trips: the recorder, the coordinator and the manual button each claim the start synchronously, before the first `await` of their start path, so the ~50 Hz samples (or the second tap) that arrive while `saveTrip` is in flight are rejected instead of writing a second row. The loser of a race gets a typed `TripAlreadyStartingError` and skips its teardown — `hasActiveTrip` reads false in exactly that window, so both error paths would have stopped the trip the *other* caller had just started. Tests 654 → 664. **Not device-validated** — the acceptance test is the next control run. L-079 and L-081 keep this task open.
  - *Scope*: the three defects between "the detector says go" and "a ride is in History". Walking scores as cycling when no GPS speed is there to correct it (L-079); one departure starts two trips because nothing is re-entrant between the go and the state transition, leaving an orphan `active` row (L-080); a trip with no route point is saved, and only ever ends through the watchdog or `maxPause` (L-081). One task because the three share the same evidence and the same acceptance test: repeat the shopping run and expect zero trips in History and zero `active` rows in the database.
  - *Dependencies*: T041 (the pipeline), T043 (the log that decides it)
  - *Cross-refs*: L-011 (dead three-layer detector), L-022 (streak fixed, confidence not), L-068 (sub-60 s rule), L-074, L-075
  - *Partly done*: 2026-09-02 — **L-081 half closed** by ledger remediation row 21. A recording with fewer than `AppConstants.minTripRoutePoints` (2) route points is deleted instead of saved, on the live stop path as it already was on the recovery path — the two 0 m entries of the control run (627 s on one rejected fix, 134 s on none) no longer reach History. `Trip.isValidTrip` becomes `isRideWorthKeeping(routePointCount)`; a cumulative counter replaces the buffer length, which empties on every flush; the `trip` line gains `n` and the header's `k` gains `minTripPts`. On the way: a long ride discarded for want of GPS no longer arms the false-start cooldown, and a manual stop that gets discarded says so instead of returning to an unchanged history. Tests 664 → 674. **The safety-net half of L-081 stays open** — both trips ended through the L-074 watchdog or `maxPause` rather than a stop decision, which is the detection problem, and this change makes it visible only in the log (`trip discard` with `n: 0`).
  - *Estimate*: multi-session — the L-080 and L-081 halves are done, the L-079 half is the detection problem itself

- ☐ **T045**: Carried-Phone Motion Semantics — counters in seconds, a gate that closes on a walker
  - *Detail*: ledger L-082, L-083
  - *Partly done*: 2026-09-02 — ledger remediation row 22. **L-086's rate leftover is closed**: `motionDataStream` holds itself to `PowerModeConfig.sensorSamplingRate`, so the battery-mode ladder changes something the pipeline can feel for the first time (it only ever lengthened a *requested* period the OS was free to round back down). `hb` gains `dr` so the OS's real rate stays measurable across the drop. **L-082 is withdrawn — it was not a defect**: `shouldResumeTrip` already decided on 5 s of continuous movement, and the `cm:5` it was read from is a 1 Hz counter that path never touches. **L-083 stays open and is sequenced behind L-079** — see the T045 decision paragraph in ledger §6, which records the counterfactual (closing the gate would have cost zero extra departures on this run) and the reason that survives it. Tests 674 → 681.
  - *Carry into the next device run*: `critical` mode now really delivers 20 Hz, which has never been validated — the 1.5 s window falls to ~30 samples and Nyquist to 10 Hz, against a stationary verdict built on high-frequency vibration. A control run in `critical` is what closes it.
  - *Scope*: ~~the per-sample residue of L-022 on the resume path (5 samples ≈ 100 ms, L-082)~~ — withdrawn — and the GPS gate a walker's pocket keeps open indefinitely (38 min for 4 fixes, L-083). Decides T041 items 1, 4 and 9 for a carried phone.
  - *Dependencies*: T041; `07fabee`'s `MotionStateWindow` is the base it extends or replaces
  - *Cross-refs*: L-022, L-070, T006 (the battery target is unmeasurable while the gate stays open)
  - *Estimate*: the rate half is done; what is left is L-083, and it waits on L-079

- ⏳ **T046**: iOS Background Survival — the gate must not be the only thing keeping the process alive
  - *Status*: **implemented and green** (`./check.sh`, 724 tests); open on its acceptance, which is the five device runs of `tasks/T046-ios-background-survival.md` §5 and nothing less. The decision paragraph ledger §6 required before any code is written there (2026-09-03).
  - *Detail*: `tasks/T046-ios-background-survival.md`; ledger L-084, remediation row 23
  - *Scope*: two failures with one owner. (a) With "Always" granted, iOS suspended the process 40 s after the GPS gate closed and kept it suspended for 2 h 31 (L-084) — motion-gated GPS, as designed for Android, removes the only CoreLocation session iOS keeps a backgrounded process alive for, and the sensors that were supposed to re-open the gate then stop arriving. The coordinator now hands a native session the *complement* of the gate: a coarse 3 km session while it is closed, nothing while it is open. (b) Nothing could relaunch a terminated app after a kill or a reboot; the only three APIs that can are exposed by no Flutter package, so `ios/Runner/AutoRideBackgroundSession.swift` holds significant-change + visit monitoring and `AppDelegate` re-arms it synchronously at launch. Found on the way: `main.dart` bootstrapped the whole pipeline from an `addPostFrameCallback`, which a background relaunch is not guaranteed to reach.
  - *Dependencies*: T041 decision (b) (gate inside the coordinator) is what this revisits for iOS
  - *Acceptance*: runs 1–5 of the task file, on a release build at verbose. Run 5 (detection off ⇒ **no** relaunch) is the one whose failure is least visible and must not be skipped. Then T041 item 4 re-measured — the permanently-held coarse session is the risk this adds.
  - *Cross-refs*: L-067, L-078, L-087 (why a coarse fix must never reach the pipeline), T041 item 8, `platform-config` skill

- ✅ **T047**: Audit Log Cost and Honesty — a verbose level that does not purge its own session
  - *Completed*: 2026-09-02 — ledger remediation row 19 (L-085 and L-086 both closed). `win`, `stop` and `res` carry the throttle `07fabee` gave `start` (one line per evaluation interval; every decision, counter change and change of verdict or deciding arm kept), so the three emits that were 90 % of the 2026-09-02 Pixel file no longer purge the session's own header; a retention purge leaves an `aud {a:"purge", n, why}` line instead of deleting in silence. Duplicate `perm k:background` and `bat` lines de-duplicated, the detector's pause clock renamed `pd` → `so` with schema `sv` 2, and `hb` gains `hz` so the real sampling rate (55.6/83 Hz against a configured 50) is readable rather than asserted. Tests 636 → 654. **Not device-validated**: the next verbose run is what confirms the file survives its own session.
  - *Deliberately not done*: holding the motion stream to the configured sampling rate. It is a detection-and-battery change, not an instrumentation one — T045 owns it.
  - *Detail*: ledger L-085, L-086
  - *Scope*: `win`/`stop`/`res` emitted per motion sample (90 % of a verbose file, self-purge in ~2 h, L-085) — the same class as the `start` emit `07fabee` throttled — plus the duplicate `perm`/`bat` lines, the `pau` vs `pd` disagreement and the 55/83 Hz sample rate that contradicts the "configured rate exactly" claim (L-086). Without it every verbose run of T044–T046 loses its own header, session start, `fgs` and `perm` lines.
  - *Dependencies*: T043
  - *Cross-refs*: L-077 (silent retention purge, by design), T041 §0 table
  - *Estimate*: half a session

- *Recommended order* (as executed): T047 → T044 (L-080) → T044 (L-081) → T045 (rate hold) → **L-079** → L-083 and the rest, which all wait on it → T046 (decision first). Ledger §6 says why, and holds the T045 decision paragraph.
  **Superseded for the freshness gap by T048** — see §11.3 and ledger §7.

### 11.3 Field findings — first ride with the log on (2026-09-03)

The mirror image of the control run above: a real 7.4 km ride, both phones in a pocket, both on
1.0.0+9, verbose. Expected: one trip each. Observed: the iPhone recorded one **three minutes and
~1.3 km late**, the Pixel recorded **none**. Both failures are the same arithmetic §11.2 already
described from the other side — diagnoses in ledger §7 (L-087…L-089).

- ⏳ **T048**: Trusting a GPS Fix — a bad speed must not veto a real ride
  - *Status*: the three fixes are **implemented and green** (`./check.sh`, 701 tests); the task stays open on its acceptance, which is two device runs and nothing less. See `tasks/T048-gps-speed-trust.md` §8 for what landed and the two design decisions §3 had left open (the accuracy threshold is its own constant, not `rpAcc`; the derived speed is applied at ingestion so the confidence and the riding-tail cut cannot disagree).
  - *Detail*: `tasks/T048-gps-speed-trust.md`; ledger L-087, L-088, L-089
  - *Scope*: three fixes around one defect. A fix present and reporting < `cycMin` caps the start confidence at `motion × 0.6 = 0.60`, below the 0.7 threshold, whatever the sensors say — so **no fix scores higher than a bad fix** (L-087). (1) derive the speed from consecutive positions when `LocationData.speed` is 0 or invalid, for the confidence *and* for the pre-trip buffer's riding-tail cut, which is why the back-date recovered 3 s instead of 1.3 km; (2) treat a fix less accurate than the speed can justify as `location == null` rather than as zero speed (L-088); (3) apply `stationaryGpsMaxAge` on the start path, where only `TripStopDetector` applies it today (L-089). (2) and (3) are the accuracy arm and the age arm of one predicate and should land as one.
  - *Evidence*: Pixel — highest confidence of the entire ride **0.586** against a 0.7 threshold, i.e. 98 % of the available motion weight and a departure that was arithmetically impossible for 25 minutes; 30 of its 40 fixes above 50 m accuracy, 29 of them on the round 100/200/300/500/800 m of the fused provider's cell ladder; 80 % of its evaluations scored against a fix older than 10 s. iPhone — 192 of 219 fixes reading `sp` 0 on a 19 km/h ride, the departure firing on one isolated fix at 23.1 km/h. **Checked**: the three fixes are not redundant — the iPhone's lost fixes were accurate and fresh (only (1) saves it), the Pixel's positions are too noisy to derive a speed from (only (2)/(3) save it).
  - *Dependencies*: T041, T043
  - *Ordering*: **ahead of L-079, and it inherits L-079's risk in full.** Ledger §6 sequenced the freshness gap behind L-079 because removing a stale fix pushes every evaluation onto the motion-only path; that assumed the cap only ever suppressed *false* starts, and this run shows it suppressing a genuine ride. The trade-off is two-sided — but every one of the three fixes still moves evaluations onto the path that scored a jolt at a standstill 0.754.
  - *Acceptance*: **both** runs, on a post-T047 build at verbose — the 2026-09-02 shopping run (zero trips) *and* this ride (one trip per phone, starting within a minute of the real departure). Run 1 alone passes by doing nothing; run 2 alone passes by deleting the speed layer.
  - *Cross-refs*: L-011 and L-079 (the single-sample fit T048 leans on harder without improving), L-083, T041 item 11
  - *Estimate*: 1 session for the three fixes (done), then the two device runs
  - *Also found, not in scope*: the Pixel obtained **no GNSS fix at all** in 25 minutes of riding (L-088's cause, as opposed to its handling) — a separate look at `adaptive_location_settings.dart` and the accuracy actually requested in `normal` mode; and a `TripRecorderService` error deleting a discarded trip that was never written (`Trip not found: 8`), a discard path that matters more since T044's L-081 half.

---

### 11.4 Field findings — a meal cooked at home (2026-09-03 evening)

The inverse failure, on a **post-remediation build** (1.0.0+10, i.e. after T044/T045/T047 and
after T048's shipped fixes). 109 minutes, both phones lying in the kitchen, the rider cooking and
doing nothing else. Expected: zero trips each. Observed: the Pixel started **4** and persisted
**2 as cycling rides** (183 m at 2.5 km/h, 68 m at 1.4 km/h); the iPhone started **6** and
discarded all six — only because it received no fix at all during them, which is a pass by
accident. Diagnoses in ledger §8 (L-093…L-097).

- ⏳ **T049**: Three Gestures Are Not a Ride — false starts while standing still
  - *Status*: **the four fixes are written and green (772 tests); the two device runs of §5 are outstanding.** Sequencing decided (ledger §6): one build carries T048 and T049, because T048 is already shipped in 1.0.0+10 and T049's two runs *are* T048's acceptance and control runs.
  - *Detail*: `tasks/T049-false-starts-at-rest.md`; ledger L-093, L-094, L-095, L-096, L-097
  - *Scope*: four fixes around one defect and the three defences that should have caught it. **(1)** The detection window *slides on every hit* — `lastDetectionTime = now` is reassigned on each positive detection and `isWithinDetectionWindow` truncates with `.inSeconds <= 5` — so `consecutiveDetections` counts neither consecutive detections nor detections in a fixed window, but 3 spikes each within 6 s of the previous one, up to 18 s of wall clock (L-093). **(2)** The accuracy filter (50 m) and the route-point distance threshold (15 m) are independent, so a fix accurate to ±30 m clears a 15 m gate on noise and drift becomes recorded distance (L-094). **(3)** `isRideWorthKeeping` tests duration and point count only, never whether the ride went anywhere (L-095). **(4)** The `stop` audit throttle exempts every decision that is not `continueTrip`, so a *paused* trip re-emits `pauseTrip` at the sample rate (L-096). **(5)** And underneath that throttle, the evaluation itself: two motion samples 17 ms apart both ran the whole teardown for one ride — two `trip discard` lines and a `deleteTrip` on a row already deleted — because `stopRecording`'s only guard is `_activeTrip`, cleared at the *end* of the stop path. L-080 on the other end of the ride (L-097).
  - *Evidence*: all ten false starts are (1)'s signature, with no other cause present — Pixel trip 3 holds `n=2` through five consecutive sub-threshold seconds and fires 5.35 s later; intervals between the streaks' own positive detections run 1.03–5.35 s across all ten, and not one start has three detections in three consecutive seconds. The 9 points of the 183 m "ride" all sit inside a ~40 m square (`rp keep d=18.2 ac=33.5`). 88 208 `pauseTrip` lines on the Pixel, 32.3 per second against `evalMs` 1000, 83 % of the file. **`vt: false` on 100 % of evaluations on both phones** — the speed layer never voted once, so `c` was motion-only throughout and 0.7 was crossed by wrist movement (`mag` 12.8–16.2 against a 9.82 baseline).
  - *The blue indicator*: the rider's own report. The iPhone held the GPS gate open **42.8 of 109 min (39 %)** — 3.8 min across five correct `inactivityTimeout` closes, and **39.0 min across five `session` closes**, each a false trip holding the gate from start to discard. Not a gate defect: fixing (1) removes 91 % of the open time without touching the gate. Battery is **not** measurable from this run (one 5 % iOS step, verbose log) and must not be quoted; T041 item 4 unaffected.
  - *Dependencies*: T041, T043
  - *Ordering*: **decided (2026-09-03) — one build, both tasks.** T048 is already in 1.0.0+10, so "separate builds" would have meant reverting shipped code, and T049's run 2 *is* T048's ride run while run 1 *is* its control run. What is traded away: if run 2 fails to start a trip, the log has to be read on `n`/`c`/`vt` to say whether the tighter streak (L-093) or T048's speed trust owns it — a streak reaching 2 and dying is L-093's cost, one never reaching 1 is the confidence. Decision paragraph in ledger §6.
  - *Acceptance*: **both** runs, at verbose, on a build carrying all four fixes — (1) this run repeated, an hour of ordinary indoor activity, pass is **zero trips on both phones** plus a gate-open fraction under 5 %; (2) a real ride, pass is **one trip per phone within a minute of the real departure**, route matching a parallel Strava recording. Run 1 alone passes by refusing to start anything; run 2 alone passes by reverting to today's behaviour. Same trap as T048 §5.
  - *Cross-refs*: **L-088** (confirmed at rest, not re-opened — the reason the motion path is the only path); **L-079** and the single-sample fit, the deeper reason a hand gesture scores like pedalling — narrowing the streak makes false starts rarer without making the fit better, and T049 does not pre-empt it; **L-011** (`CyclingPatternDetector` still unwired — a frequency layer would separate cooking from pedalling on its own, which is exactly why it must not be smuggled in here); L-081 (the cooldown *did* work — two `falseStart` arms on the iPhone's 31 s trips — but is armed by the duration floor, so it never sees a 930 s false trip).
  - *Field re-read (2026-09-03 22:24/22:27 exports)*: the same session exported again, spanning 19:38→22:27. The T049 build launches at 22:14, so only **10.4 min (Pixel) / 13.1 min (iPhone)** are on it — **zero trips started on both**, the Pixel crossing the threshold once (`c` 0.718) with the streak dying at `n=1` on the next second, which is L-093 working. **Not run 1 of §5** and not to be quoted as one: ten minutes with the phone in hand, no trip in the slice, so L-096's throttle and L-094's `drift` reason have nothing to fire on. The 1.0.0+10 tail those exports added is where **L-097** comes from.
  - *Shipped*: (1) the streak breaks on the first evaluation interval with no positive detection, and the window constant now only refuses to resume a streak across a gap in which nothing was evaluated (its comparison is on `Duration`s, so 5 s no longer means 5.99 s); (2) a fix whose displacement does not beat its own accuracy is dropped as `drift`, a reason of its own beside `dist`; (3) `Trip.discardReason` names the arm that fired — `dur`/`pts`/`still` — and the third is `net >= minTripNet` (100 m) **or** `avg >= minTripKmh` (4 km/h), an OR because a loop comes home with zero net displacement; (4) the `stop` throttle keys on the previous decision. `trip {a:"discard"}` carries `why` and `net`; `_emitResumeEval` was checked and does not have (4)'s hole; (5) the ending is claimed synchronously before the first `await`, at the coordinator (one decision) and at the recorder (which the Stop button and the notification action reach directly), and `startListening` clears both claims. 775 tests green.
  - *Estimate*: the four fixes are done; what remains is the two device runs shared with T048
  - *Also found, not in scope*: a recovery deletion writes a `log` line and no `trip` event, so a reader counting trips in a log misses a trip `TripRecoveryService` finalised (the Pixel's trip 1 here) — one line, unassigned.

### 11.5 Field findings — a real ride home (2026-09-06 evening)

§11.3 again, on the build that was supposed to have fixed it. One verbose log, iPhone 14,3,
**1.0.0+12** — after T048 and all five T049 fixes. The rider cycled home; expected one trip
covering the ride. Observed: **one trip, 9 min 50 s and ≈ 2.9 km short at the front** — departure
~23:20:50, `trip start` 23:30:38, `bdate` reaching back 86 s and 595 m of 3 459 m ridden.
751 `start` evaluations in between, streak `n` reaching 3 exactly once. Diagnoses in ledger §9
(L-079 measured at last, L-098, L-099).

- ⏳ **T050**: A Window, Not an Instant — the ride that started ten minutes late
  - *Status*: **the three fixes are written and green (782 tests); the device run is outstanding** — and it is T048/T049's run 2, not a new one.
  - *Detail*: `tasks/T050-windowed-motion-fit.md`; ledger L-079, L-098, L-099
  - *Scope*: three fixes in one chain. **(1)** The motion score was one 20 ms sample against bands written for an instantaneous magnitude, so an evaluation interval was decided by whichever sample landed on its boundary — 250 of 751 evaluations above `k.conf` while the rider was demonstrably cycling, 6.5 % on the unbiased 1 Hz series, and L-093's three-consecutive rule multiplying that into a 590 s wait (L-079, open since 2026-09-02 and now measured on a ride). It is now the standard deviation of \|a\| and the mean \|gyro\| over `detectionEvaluationInterval`, on asymmetric ramps. **(2)** `speedIsTrustworthyAt` never asked whether a fix *has* a speed, so iOS's `sp: 0` at 20 km/h was trusted as a measurement of standing still and capped the confidence at 0.60 — 155 of the 751 (L-098). **(3)** The pre-trip buffer was 90 s, sized on the intended confirmation delay, so a late detection could not be repaired even in principle — 10 min / 256 points now (L-099).
  - *Evidence*: streak distribution 501/222/27/**1**, exactly the geometric law a per-sample coin toss predicts. Per-phase statistics from the same log's 1 Hz `sens` series, std(\|a\|) / mean \|gyro\|: **still 0.56 / 0.16; walking about 1.86 / 0.65; the missed ride 3.90 / 1.32; the ride once started 3.39 / 1.08** — a 6× separation the old fit was not measuring, and the numbers the new ramps are set from.
  - *Dependencies*: T041, T043
  - *Ordering*: **(1) and (2) ship together or not at all.** (2) moves evaluations onto the motion-only path, which §11.4 showed starting trips on hand gestures; (1) is what makes that path trustworthy. Shipping (2) alone would re-open T049.
  - *Acceptance*: **no new device run** — T048 §5 / T049 §5's two runs, with run 2's criterion now the operative one (one trip within a minute of the real departure). Read on `start`'s new `asd`/`gav`/`wn` against `k.asd*`/`k.gav*`: `asd` below `k.asdMin` while pedalling means the ramp is set too high for this phone's placement; three consecutive seconds above it in a kitchen means too low, and (2) has to be reconsidered with it.
  - *Cross-refs*: **L-093 is not the cause and must not be loosened on this evidence** — the streak dies on the first sub-threshold interval exactly as designed, and ledger §6's discriminator (`n` reaching 2 and dying vs never reaching 1) points at the confidence. **L-011** stays unwired — a windowed fit is not the frequency layer, and smuggling one in would make the device run unreadable. **L-083** was sequenced behind L-079 and is now unblocked. T041 item 11 is what (3) serves.
  - *Shipped*: the windowed fit (reusing `StationaryWindow`, now parameterised, built over the evaluation interval so a second's verdict is about that second); `hasReportedSpeed` as the third arm of the speed-trust predicate; the buffer bounds; and schema **3** — `start` carries `asd`/`gav`/`wn`, the ramps travel in `k`, and `c` keeps its name while changing what its motion half is, which is why the version moved and the reading skill now branches on `hdr.sv`.
  - *Estimate*: the three fixes are done; what remains is the device run shared with T048 and T049
  - *Provisional*: the ramps come from a 1 Hz series and the fit runs at 20–50 Hz. Erring low starts rides on walks, erring high repeats this ride. Only the device run settles them.

### 11.6 Field findings — a drive to the shops (2026-09-07 midday)

The first run on a build carrying T050 (1.0.0+13), and it settles two things at once.
**T050 works**: 93 minutes of a phone lying still gave 4 370 evaluations, a median `asd` of 0.01
and **zero false starts**, and the departure was confirmed **three seconds** after the first shaken
second with `pre: 0` and no `bdate`. **And the trip is a car**: 3 137 m, 27 min, `avg` 6.9 km/h,
`max` 39.3, `net` 16 m, written as `act: "cycling"`. Diagnoses in ledger §10 (L-100, L-101).

- ⏳ **T051**: A Car Shakes Like a Bicycle — the drive that was recorded as a ride
  - *Status*: **the three changes are written and green (794 tests); the device run is outstanding** — T048/T049's run 2, plus an optional drive.
  - *Detail*: `tasks/T051-vehicle-veto.md`; ledger L-100, L-101
  - *Scope*: **(1)** The motion fit cannot tell a car from a bicycle and nothing else was asking — replaying the T050 score over the drive and over the 2026-09-06 ride gives **0.298 vs 0.331** and 22.6 % vs 23.0 % of windows above `k.conf`, with matching percentiles throughout. `VehicleSpeedWatch` adds the only axis that does separate them, with a live arm (four of the last six measured speeds ≥ 35 km/h over ≥ 5 s) that ends the ride and an end-of-ride arm (four fast fixes and a quarter of the evidence); `Trip.discardReason` gains a `vehicle` arm (L-100). **(2)** A 300 s cooldown after a vehicle discard, because a car's motion *is* a bicycle's and 30 s would turn one drive into a string of discarded trips. **(3)** T050's ramps were calibrated on a series of *instants*, which overstates the within-second spread ~2× — corrected in the constants, **values unchanged**, with the replay table that justifies leaving them (L-101).
  - *Evidence*: the GPS said "car" from **+243 s** (57.0 / 54.5 / 51.4 / 55.0 / 49.3 km/h) and nothing read a speed after the start decision — `cycMax` only feeds `speedScore` while evaluating a start, `maxKmh` (60) only rejects route points, which a 57 km/h peak passes under. Measured speeds: the drive **37, max 39.3, an 11-fix run above 30**; the ride **11, max 31.6, longest run 1**.
  - *Dependencies*: T050
  - *Load-bearing invariant*: **only provider-measured speeds are evidence.** Every reading above 40 km/h during the *bicycle* ride is a `dsp` derived from a fix accurate to 23–38 m; a watch fed those would discard real rides on GPS noise. The recorder subscribes to `locationStreamProvider` directly, so it sees the provider's own number — if the refinement ever moves into that stream, this rule silently starts deciding on inferences.
  - *Acceptance*: T048 §5 / T049 §5's run 2 with a second criterion — **one trip, and no `veh` line in it** — plus, if a car is to hand, a drive whose pass is `veh {a:"fire"}` → `trip {a:"discard", why:"vehicle"}` → `cool {a:"arm", why:"vehicle"}`. Read `vfx`/`vmf` on every ending: a ride ending with `vfx` 2 or 3 is one descent away from being thrown out.
  - *What it costs*: a cyclist holding 35 km/h across four measured fixes spanning five seconds loses the ride. There is no threshold on this axis that separates a town car from a fast cyclist; 35 sits between *this* drive and *this* ride, and one of each is the whole evidence base.
  - *Cross-refs*: **L-011** — a pedalling cadence is the one thing that might separate the two on motion alone, and this run is the strongest argument yet for wiring `CyclingPatternDetector` and the weakest possible argument for doing it here. **L-098**'s trade-off is visible: `vt` absent throughout the departure window, so the score was motion-only as designed — and the veto T050 removed would have had nothing to veto with, the car being stationary. **L-099** was not exercised (`pre: 0`), exactly as §9 predicted for its own fix.

---

## Phase 12: Data Portability

- ⏳ **T042**: FIT Export
  - *Detail*: this entry (no separate task doc)
  - *Scope*: export a recorded trip as a Garmin FIT activity file and hand it to the OS share sheet, so a ride can land in Strava, Garmin Connect, Files or anything else that reads `.fit`.
  - *Dependencies*: T041's recorder (the route points and the moving/pause split are what the file is made of)
  - *Implementation*: `lib/features/trip_export/`
    - `FitActivityEncoder` — pure Dart, no `dart:io` and no plugin, so it is testable off-device. Writes the sequence every FIT reader expects: `file_id` → `device_info` → timer `start` → `record`s → timer `stop` → `lap` / `session` / `activity`. Coordinates in semicircles; altitude and speed in `enhanced_altitude`/`enhanced_speed` (the uint16 fields clip); cumulative distance computed point-to-point; ascent/descent behind a 3 m noise gate; `total_elapsed_time` from the timestamps and `total_timer_time` from `movingDuration`; `local_timestamp` offset by the zone, since FIT stores local wall-clock with no zone attached.
    - `TripExportService` — the platform half: encodes on another isolate (a long ride is tens of thousands of records), writes `<cache>/fit_exports/autoride-YYYY-MM-DD-HHMM.fit`, then opens the share sheet.
    - `TripDetailScreen` gained an "Export as FIT" action; the screen became a `ConsumerStatefulWidget` to hold the in-flight state.
  - *Dependencies added*: `fit_dart_sdk`, `share_plus` (13.x — 12.x conflicts with `package_info_plus ^10.2.1` over `win32`), `path_provider`
  - *Tests*: 11 round-trip tests — encode, then decode with the same SDK an importer would use, and assert on what comes back. Byte-level expectations would only restate the encoder.
  - *Not validated*: the share sheet itself and an actual import into Strava/Garmin Connect (needs a device), and a multi-hour ride's encode time.
  - *Not covered*: pause intervals (the model stores only the pause total, so no per-pause timer events), heart rate, cadence and power (not recorded), and there is no import side.

- ⏳ **T043**: Opt-in Audit Log
  - *Detail*: this entry (no separate task doc); analysis side in `.claude/skills/autoride-audit-log/`
  - *Scope*: an opt-in diagnostic journal of what the detection pipeline does, exportable as gzipped NDJSON through the share sheet, so the `tasks/T041-device-validation.md` checklist can be settled from evidence instead of impressions. Several of its items say "log line to look for", but `Logger` only writes `debugPrint` behind `kDebugMode` — invisible in a release build — and nothing at all traced the `idle→detecting→active→paused` transitions, the GPS gate, the power mode or the detectors' decisions.
  - *Dependencies*: T041's pipeline (what is being observed), T011 settings, T042 (the share-sheet pattern it copies)
  - *Decisions (maintainer, 2026-09-02)*: NDJSON gzipped · share sheet only, no backend · two levels (normal/verbose, never raw 50 Hz sensors) · circular buffer 7 days / 200 000 rows / ~20 MB
  - *Implementation*:
    - `lib/core/audit/` — the port, pure Dart: `AuditLog` (static, because the call sites are stream callbacks and plain-Dart pipeline pieces with no `Ref`, including `core/utils/logger.dart`), `AuditSink`, the event vocabulary and line encoder, and `AuditSchema.thresholds()` which stamps the build's own `AppConstants` into every export.
    - `lib/features/diagnostics/` — the adapter: a **separate** `autoride_audit.db` (WAL, `synchronous = NORMAL`), a batching sink (200 lines / 5 s / immediately on a `critical` event / on `AppLifecycleState.paused`), amortised purge, streaming gzip export, and the settings section.
    - `Logger` now mirrors into the log, which captures the two lines T041 cites literally, in release builds.
    - A heartbeat (`hb`, 30 s: ticks, motion samples, fixes, real elapsed) — without it a gap in the timeline cannot distinguish an OS suspension from a lost buffer, which are opposite verdicts for items 3 and 8.
  - *Privacy*: the file holds unrounded coordinates (the cross-reference against a Strava FIT needs them). A blocking dialog states that before the share sheet, and that dialog is the condition under which `store-metadata/data-safety.md` §3.3 can keep answering "nothing shared". Policy §2.5/§3.1/§3.2/§3.3/§6/§7.1 updated, and T042's export — missing from the policy until now — covered in the same pass.
  - *Tests*: 114 (472 → 586 after the review), including a group that pins the emitted event sequence in the coordinator: the real risk here is not a subtle bug but three missing `emit` calls, which would make the journal look like evidence while being silent about the transition under investigation.
  - *Replaces*: the dead `debugLoggingEnabled` setting, which nothing ever read.
  - *Not validated*: the share sheet itself, a 200 000-row log on a device, and exporting while Doze-suspended.
  - *Review (2026-09-02)*: `tasks/T043-review.md` — 24 findings, two blocking (R-01: any settings change closed the shared sink and the log silently stopped; R-02: pragma order left `auto_vacuum` off, so every purge past 20 MB emptied the journal). All 24 fixed the same day in `31d8940` / `47d110c` / `e67077c`; 586 tests.

---

## Progress Summary

**Total Tasks**: 49
**Completed**: 26
**In Progress**: 15 (T006, T013, T030, T034, T037, T038, T039, T041, T042, T043, T046, T048, T049, T050, T051)
**Pending**: 12
**Blocked**: 0

**Current Phase**: Phase 10 - Release Preparation, alongside the Phase 11 audit backlog and the Phase 12 export work
**Last Completed**: T047 - audit log cost and honesty (2026-09-02); **T034 code-complete 2026-09-03** — on-device training capture on a second axis of the audit log (`raw` at `lvl 2`, `lbl` ground truth, its own retention and export), device run outstanding. T044's L-080 and L-081 halves and T045's sampling-rate half the same day. **T048 opened 2026-09-03** (diagnosis only) from the first ride run — ledger §7. **T049 opened 2026-09-03** from the evening's kitchen run, on the post-remediation build — ledger §8 — and its **four fixes written the same day** (the streak is consecutive, drift is not distance, a kept ride went somewhere, a paused trip does not flood the log); both tasks now wait on the same two device runs, on one build. **T050 opened 2026-09-06** from the evening ride home on 1.0.0+12 — ledger §9 — with its **three fixes written the same day** (the start fit is windowed, a fix with no speed does not vote, the back-date window covers a late confirmation); it joins the same build and the same two runs, and it is the task that finally closes **L-079**. **T051 opened 2026-09-07** from the first run on a T050 build — ledger §10 — which confirms T050 (zero false starts in 93 min, a three-second departure) and finds the next thing: a drive to the shops recorded as a cycling trip, because a car's motion *is* a bicycle's and nothing was reading the one axis that separates them.
**Current Task**: **T048 + T049 + T050 + T051 together** (Phases 11.3/11.4/11.5/11.6), then T044–T046 (Phase 11.2). **The two are one problem seen from both ends and §11.4 changed the shape of the queue.** T048 answers a real ride that could not start; T049 answers a kitchen that did, on a build that already carries T048's fixes. Every T048 fix moves evaluations onto the motion-only path, and T049 shows that path starting four trips on the Pixel — two of them persisted as cycling rides — and six on the iPhone, from three hand gestures inside twelve seconds. Neither task's acceptance is readable without the other's, and both need the same pair of device runs (an idle hour, a real ride), so they share a build unless attribution is worth a second session. The 2026-09-03 ride run turned the cluster around: the confidence cap ledger §6 read as *damping false starts* is a **veto on real ones** — the Pixel peaked at 0.586 against a 0.7 threshold for 25 minutes of genuine pedalling and recorded nothing, the iPhone started three minutes and 1.3 km late. T048 holds the three fixes (derived speed, an unusable fix treated as no fix, the 10 s freshness rule on the start path) and now runs **ahead** of L-079 rather than behind it, inheriting its risk — its acceptance test is both the shopping run and the ride. **L-079, the single-sample fit, is no longer behind them: §11.5 measured it on a real ride and T050 fixes it.** The 2026-09-06 ride home started 9 min 50 s and 2.9 km late with 751 evaluations in between, and the streak distribution 501/222/27/1 is a per-sample coin toss, not a rider — so the fit is now a window (std of \|a\|, mean \|gyro\|) and the queue behind it is L-083, then the safety-net half of L-081. **T046 was taken out of that queue and implemented on 2026-09-03**, because it is not a detection question and does not wait on the detector: on iOS the app recorded nothing at all once the rider stopped, and could never come back after a kill or a reboot (L-084, remediation row 23). Its acceptance is five iPhone runs, not a test suite. Then T039/T041 — iOS release is 2 blockers from submittable (build attach + screenshots); T041 device validation under way (items 1, 8, 9 and the pause logic settled on the iPhone by the 2026-09-03 log; item 11 blocked on T048). T038 open on manual Play Console setup; T037 open (§5.6/§5.7).
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

**Last Updated**: 2026-09-03
**Version**: 1.2
