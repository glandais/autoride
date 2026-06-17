# AutoRide Audit — Findings & Remediation Status

Date: 2026-06-17. Source: multi-agent audit across 8 dimensions (correctness,
resource leaks, Riverpod/architecture, battery, error handling, data layer,
privacy, tests) → adversarial verification → synthesis. 42 findings confirmed.

This file tracks what was **fixed** in this pass and what is **deferred**. The
deferred items change live trip behavior and must be validated on a physical
device (sensors/GPS), so they were intentionally left for a focused follow-up
rather than applied blind.

---

## ✅ Fixed in this pass (safe, bounded, verified by `flutter analyze` + tests)

| # | Severity | Area | Fix |
|---|----------|------|-----|
| 0 | Critical (build) | tooling | Regenerated stale `.g.dart` that was incompatible with installed Riverpod 3.2.1 (was breaking 9 test files) |
| 1 | Critical | trip_stop_detector | Stationary check now compares accelerometer deviation from gravity (`\|mag − 9.8\| ≤ threshold`) instead of raw magnitude vs a gravity-removed threshold — auto-pause/stop could **never** fire before. Added `AppConstants.standardGravity`, documented the gravity-included convention, added a regression test |
| 6 | High | battery_optimizer | `onBatteryStateChanged` subscription stored and cancelled in `ref.onDispose` (was leaked; fired on a disposed notifier) |
| 18 | Medium | gps_controller | Inactivity `Timer` cancelled in `ref.onDispose` |
| 23 | Low | activity_confidence | Combined confidence now uses documented 0.4/0.35/0.25 weights instead of unweighted mean |
| 24 | Medium | cycling_pattern_detector | Pedaling frequency computed over the first→last peak span, not the whole (growing) buffer duration |
| 26 | Low | error_handler | `TimeoutException` classified by type before the network string-match (was mislabeled as network) |
| 22 | Medium | privacy / Android | `android:allowBackup="false"` + `fullBackupContent="false"` so the location DB isn't copied off-device |
| 28 | Low | Android manifest | Corrected the INTERNET-permission comment (OSM tiles do use it) |
| 9 | High | trip_recorder | Route-point flush returns success/failure, logs dropped count; final flush failure logged loudly instead of silent data loss |
| 10 | High | trip_recorder | Location-stream `onError` now logs instead of swallowing |
| 16 | Medium | trip_recorder | Added a 1s metrics ticker so duration/avg speed don't freeze between distance-filtered GPS points |
| 19 | Medium | coordinator | `startRecording` DB failure wrapped in try/catch → resets to idle + surfaces error (was unhandled inside a stream callback) |
| 15 | Medium | coordinator | Added `_disposed` guard for delayed restarts; motion-stream error now tears down cleanly and sets `AsyncError` |
| 17 | Medium | database_service | `databaseProvider` is now the single keepAlive owner, goes through the singleton getter, and closes the handle in `ref.onDispose` |
| 21 | Medium | tests | Added positive/negative tests for `hasDetectionTimedOut` and `hasPauseTimedOut` (were only tested in the not-expired case / never) |

Quality gates after the pass: `flutter analyze` clean, **157 tests pass**.

---

## ✅ Completed in follow-up (parallel worktree subagents)

Done after the first pass, each in an isolated git worktree, verified by
`flutter analyze` + `flutter test`. Integrated tree: **190 tests pass**.

| # | Severity | Area | Fix |
|---|----------|------|-----|
| 27 | Low | trip_repository | `getTripsByDateRange` route-point loading batched into one `WHERE trip_id IN (?, …)` query (was N+1), grouped in Dart, order preserved; added association/order test |
| 14 | Medium | trip_stop_detector | Movement hysteresis: pause is only reset after `tripStopMovementHysteresisSamples` (=3) consecutive non-stationary readings, so a single noisy GPS speed spike no longer starves the 300 s auto-stop; added tests |
| 12 | High | tests | Added `TripRecorderService` tests (lifecycle, double-start/stop StateErrors, pause/resume bookkeeping, final persistence). Location-driven paths could not be covered — see note below |
| 13 | High | tests | Added `TripDetectionCoordinator` tests (init/idle, safe stop). Decision-routing could not be covered — see note below |
| 29 | Low | tests | Renamed mislabeled `location_service_test` → `location_data_test` and added a real `LocationService` permission-gating test; added `MotionDetectionService` and `GPSController` behavior tests |

**Testability limitation surfaced by #12/#13/#29 (feeds the deferred cluster):**
`TripRecorderService`, `TripDetectionCoordinator`, `MotionDetectionService`, and
`GPSController` consume sensor/location data by calling the generated provider
*functions* directly (`locationStream(ref)`, `motionDataStream(ref)`,
`motionDetectionServiceProvider.notifier.build()`) rather than via
`ref.watch(...Provider)`. That bypasses provider overrides, so fake streams
cannot be injected in unit tests — the distance/filtering/flush logic and the
coordinator's routing logic remain untestable until those call sites are
refactored to use overridable providers. This is the same anti-pattern as
finding #5 and is captured in the deferred-cluster doc below.

---

## ⏳ Deferred — larger refactors needing device validation

These are real and confirmed, but each changes the live tracking pipeline and
cannot be meaningfully verified without on-device sensor/GPS testing. They
should be sequenced roughly in this order.

### Tier 0 — headline features that don't actually work

- **#3 Motion-gated GPS is a no-op.** `gps_controller.dart` `_startGPS/_stopGPS`
  only flip a private enum; `gpsControllerProvider` is read by nothing. The
  documented battery-first GPS gating does not exist. Real GPS lifecycle is
  driven by `locationStream()` with no motion gating.
- **#2 Session state can be lost.** `TripRecorderService` (and the state machine
  / coordinator) are `autoDispose` but hold the entire in-progress trip in
  instance fields, while all callers use `ref.read(...notifier)` (no listener).
  When the tracking screen isn't foregrounded, the provider can auto-dispose and
  discard the active trip. Needs `keepAlive`/explicit `ref.keepAlive()` session
  ownership.
- **#11 Automatic detection has no live entry point.** `TripDetectionCoordinator`
  is only ever (re)started by itself; nothing in `lib/` starts it. The advertised
  auto-detection never runs. Needs wiring to a real lifecycle owner (depends on
  #2/#3).

### Tier 1 — battery strategy inert / background unreliable

- **#4 Adaptive battery settings are inert.** `AdaptiveLocationSettings` has zero
  consumers; GPS always runs high accuracy + 10 m filter. Sensor streams hardcode
  50 Hz and never read power mode. `BatteryOptimizer` recomputes a config nobody
  applies → defeats the <5%/hr goal.
- **#5 Duplicate sensor subscriptions.** `GPSController.build()` and
  `CurrentMotionState.build()` call a Notifier's `build()` directly, creating
  unmanaged duplicate sensor streams. (Prerequisite for #3.)
- **#7/#8 Background isolate disconnected.** The background isolate emits via
  `service.invoke('update')` (surfaced only by `LocationTracking`) while the
  recorder subscribes to a separate foreground `locationStream`; they're never
  connected and nothing starts/stops the background service with recording. The
  isolate also polls GPS on a fixed 30 s timer with no motion/battery adaptation.

### Tier 2/3 — remaining polish

- **#29 (partial)** `background_location_service_test` still only asserts
  "is defined"; the isolate handlers (`onStart`/`onIosBackground`) require
  platform channels / a device, so this is blocked with the cluster below.
- **#12/#13 (partial)** The location- and motion-driven paths of the recorder
  and coordinator remain untested — blocked by the same direct-function-call
  anti-pattern as #5 (see the testability note above and the cluster doc).

Why the rest of this cluster is NOT auto-implemented, the decisions it needs
from you, and a proposed sequencing: **see `tasks/BLOCKED-pipeline-refactor.md`**.

Full per-finding detail with verification reasoning is in the audit transcript.
