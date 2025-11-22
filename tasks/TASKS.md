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

- ✅ **T006**: Battery-Optimized Location Strategy
  - *Detail*: `tasks/T006-battery-optimization.md`
  - *Scope*: Adaptive accuracy, distance filtering, motion-gated GPS
  - *Dependencies*: T005, T007
  - *Estimate*: 2-3 hours

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

- ✅ **T013**: Automatic Trip Start Detection
  - *Detail*: `tasks/T013-trip-start-detection.md`
  - *Scope*: Combine motion + GPS for automatic trip start
  - *Dependencies*: T004, T008, T012
  - *Estimate*: 3-4 hours
  - *Completed*: 2025-11-22

- ✅ **T014**: Automatic Trip Stop Detection
  - *Detail*: `tasks/T014-trip-stop-detection.md`
  - *Scope*: Detect trip end (stationary threshold, timeout logic)
  - *Dependencies*: T013
  - *Estimate*: 2-3 hours
  - *Completed*: 2025-11-22

- ☐ **T015**: Trip Data Recording
  - *Detail*: `tasks/T015-trip-recording.md` (create on request)
  - *Scope*: Record route points, calculate distance/duration/speed
  - *Dependencies*: T010, T013
  - *Estimate*: 2-3 hours

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
- ☐ **T020**: App Theme & Design System
  - *Detail*: `tasks/T020-theme-design.md` (create on request)
  - *Scope*: Color scheme, typography, shared widgets
  - *Dependencies*: T001
  - *Estimate*: 2-3 hours

- ☐ **T021**: Onboarding Flow
  - *Detail*: `tasks/T021-onboarding-flow.md` (create on request)
  - *Scope*: Welcome screens, permission requests, initial setup
  - *Dependencies*: T020
  - *Estimate*: 3-4 hours

- ☐ **T022**: Trip Tracking Screen (Active Trip)
  - *Detail*: `tasks/T022-tracking-screen.md` (create on request)
  - *Scope*: Real-time stats, map view, start/stop controls
  - *Dependencies*: T015, T020
  - *Estimate*: 4-5 hours

- ☐ **T023**: Trip History Screen
  - *Detail*: `tasks/T023-history-screen.md` (create on request)
  - *Scope*: List view, trip details, route map
  - *Dependencies*: T010, T020
  - *Estimate*: 3-4 hours

- ☐ **T024**: Settings Screen
  - *Detail*: `tasks/T024-settings-screen.md` (create on request)
  - *Scope*: Preferences, permissions, data management
  - *Dependencies*: T011, T020
  - *Estimate*: 2-3 hours

### 6.2 UI Polish
- ☐ **T025**: Notifications & Foreground Service UI
  - *Detail*: `tasks/T025-notifications.md` (create on request)
  - *Scope*: Trip progress notification, service controls
  - *Dependencies*: T005, T022
  - *Estimate*: 2 hours

- ☐ **T026**: Loading States & Error Handling
  - *Detail*: `tasks/T026-loading-errors.md` (create on request)
  - *Scope*: Loading indicators, error messages, retry logic
  - *Dependencies*: T020
  - *Estimate*: 2 hours

---

## Phase 7: Permissions & Platform

### 7.1 Permission Management
- ☐ **T027**: Permission Handler Implementation
  - *Detail*: `tasks/T027-permission-handler.md` (create on request)
  - *Scope*: Progressive permission requests, rationale dialogs
  - *Dependencies*: T003
  - *Estimate*: 2-3 hours

- ☐ **T028**: Platform-Specific Configuration
  - *Detail*: `tasks/T028-platform-config.md` (create on request)
  - *Scope*: AndroidManifest.xml, Info.plist, capabilities
  - *Dependencies*: T027
  - *Estimate*: 1-2 hours

---

## Phase 8: Testing & Quality

### 8.1 Automated Testing
- ☐ **T029**: Unit Tests (Business Logic)
  - *Detail*: `tasks/T029-unit-tests.md` (create on request)
  - *Scope*: Repository, state machine, calculations
  - *Dependencies*: T010, T012
  - *Estimate*: 3-4 hours

- ☐ **T030**: Widget Tests (UI Components)
  - *Detail*: `tasks/T030-widget-tests.md` (create on request)
  - *Scope*: Screen tests with mocked providers
  - *Dependencies*: T022, T023, T024
  - *Estimate*: 3-4 hours

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

- ☐ **T033**: Code Quality & Linting
  - *Detail*: `tasks/T033-code-quality.md` (create on request)
  - *Scope*: flutter analyze, code formatting, linting rules
  - *Dependencies*: All implementation tasks
  - *Estimate*: 2 hours

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
- ☐ **T036**: App Icons & Splash Screen
  - *Detail*: `tasks/T036-app-assets.md` (create on request)
  - *Scope*: Design and configure app icons, splash screen
  - *Dependencies*: T020
  - *Estimate*: 2-3 hours

- ☐ **T037**: Privacy Policy & Terms
  - *Detail*: `tasks/T037-privacy-policy.md` (create on request)
  - *Scope*: Write privacy policy, terms of service
  - *Dependencies*: T034
  - *Estimate*: 2-3 hours

### 10.2 Release Build
- ☐ **T038**: Android Release Configuration
  - *Detail*: `tasks/T038-android-release.md` (create on request)
  - *Scope*: Signing, ProGuard, release build
  - *Dependencies*: T033, T036
  - *Estimate*: 2 hours

- ☐ **T039**: iOS Release Configuration
  - *Detail*: `tasks/T039-ios-release.md` (create on request)
  - *Scope*: Signing, capabilities, release build
  - *Dependencies*: T033, T036
  - *Estimate*: 2-3 hours

- ☐ **T040**: Beta Testing & Feedback
  - *Detail*: `tasks/T040-beta-testing.md` (create on request)
  - *Scope*: TestFlight/Internal Testing, collect feedback
  - *Dependencies*: T038, T039
  - *Estimate*: Ongoing

---

## Progress Summary

**Total Tasks**: 40
**Completed**: 14
**In Progress**: 0
**Pending**: 26
**Blocked**: 0

**Current Phase**: Phase 4 - Trip Detection Logic
**Last Completed**: T014 - Automatic Trip Stop Detection (2025-11-22)
**Current Task**: None (ready for next task)
**Next Task**: T015 - Trip Data Recording

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

**Last Updated**: 2025-11-22
**Version**: 1.0
