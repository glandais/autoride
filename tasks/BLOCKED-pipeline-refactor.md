# BLOCKED: Core tracking-pipeline refactor (audit findings #2, #3, #4, #5, #7, #8, #11)

Date: 2026-06-17.

This document exists because these findings were requested to be processed but
**cannot be responsibly completed by an autonomous coding agent**. They are real
and confirmed by the audit, but each one (a) requires a **product/architecture
decision that only the maintainer can make**, and/or (b) **can only be verified
on a physical device** (real accelerometer, gyroscope, GPS, background execution,
and battery drain) — which an agent in CI cannot do. They are also **tightly
interdependent**, so they cannot be parallelized or landed piecemeal without
risking a half-migrated, unverifiable core app.

The safe, independent findings around this cluster (#14, #27, #12/#13, #29) were
implemented and verified — see `AUDIT-FINDINGS.md`. What remains is the heart of
the tracking engine.

---

## Why "all tests pass" is not enough here

The whole point of this cluster is **runtime behavior on real hardware**:
- Does GPS actually stop when the rider is stationary? (battery)
- Is the <5%/hour battery target met under each power mode?
- Does an in-progress trip survive backgrounding / a notification tap?
- Does the background isolate keep recording when the OS suspends the app?

None of that is observable from `flutter analyze` or `flutter test` on a host
machine — emulators don't produce real sensor/GPS/battery behavior (the project's
own CLAUDE.md says "test sensor/location features on physical devices only").
Implementing these blind would produce code that compiles and passes unit tests
but whose actual purpose is unverified — the worst kind of "done."

---

## The findings and the decisions each one needs from you

### #5 — Sensor/location data is consumed via direct function calls, not providers
`GPSController.build()` calls `motionDetectionServiceProvider.notifier.build()`;
the recorder/coordinator call `locationStream(ref)` / `motionDataStream(ref)`
directly. This creates **duplicate, unmanaged sensor subscriptions** and makes
the consumers **impossible to unit-test** (provider overrides are bypassed —
this is exactly why #12/#13 coverage is partial).

- **Prerequisite for everything else** and the lowest-risk starting point.
- **Decision needed:** none, really — this is a clear correctness/testability
  fix. But it touches the streams every other item depends on, so it should be
  done first and then validated on-device that sensor data still flows.

### #2 — Session state can be lost (autoDispose vs. live trip)
`TripRecorderService`, `TripStateMachine`, and `TripDetectionCoordinator` are
`autoDispose` yet hold the entire in-progress trip in instance fields; all
callers use `ref.read(...notifier)` (no listener), so the providers can dispose
mid-trip and discard the active ride.

- **Decision needed:** what owns a trip session's lifetime? Options:
  1. `@Riverpod(keepAlive: true)` on the three providers (simplest, but they
     live for the whole app run).
  2. An explicit `ref.keepAlive()` link opened in `startRecording` / closed in
     `stopRecording` (scoped to an actual trip).
  3. A single long-lived "session owner" provider that the app watches.
- **Why blocked:** this changes app-wide memory/lifecycle semantics; the right
  choice depends on how you want the app to behave when backgrounded and must be
  validated on-device (does the trip actually survive?).

### #3 — Motion-gated GPS does not exist (dead code)
`GPSController._startGPS/_stopGPS` only flip a private enum;
`gpsControllerProvider` is read by nothing. The headline battery feature — GPS
only running when motion is detected — is not implemented. Real GPS lifecycle is
`locationStream()` running unconditionally.

- **Decision needed:** which architecture?
  1. Make `GPSController` actually own/cancel `Geolocator.getPositionStream` and
     route **all** location consumers through it; or
  2. Delete `GPSController` and implement gating inside the coordinator/recorder
     (don't subscribe to location until `MotionState` is moving/cycling; cancel
     after `gpsInactivityTimeout` of stationary).
- **Why blocked:** a design choice with no single right answer, and its success
  criterion (GPS demonstrably stops when stationary, battery drops) is only
  measurable on a device.

### #4 — Adaptive battery settings are inert
`AdaptiveLocationSettings` has zero consumers; GPS always runs high accuracy +
10 m filter. Sensor streams hardcode 50 Hz and never read the power mode.
`BatteryOptimizer` computes a `PowerModeConfig` nobody applies.

- **Decision needed:** confirm the per-mode accuracy/Hz/interval targets, and
  accept that the location/sensor streams must re-subscribe when the power mode
  changes (a behavioral change to the live stream).
- **Why blocked:** the entire deliverable is a **battery-drain number** that can
  only be measured on a real device over time. Depends on #3/#5.

### #7 / #8 — Background isolate is disconnected and non-adaptive
The background isolate emits via `service.invoke('update')` (surfaced only by
`LocationTracking`), while the recorder subscribes to a *separate* foreground
`locationStream`; they are never connected, and nothing starts/stops the
background service in lockstep with recording. The isolate also polls GPS on a
fixed 30 s timer with hardcoded accuracy, no motion gating, no battery adaptation.

- **Decision needed:** what is the single source of truth during a trip
  (foreground stream vs. background isolate), and how do the isolate and main
  isolate share state (Riverpod is unavailable inside the background isolate —
  data must cross via `service.invoke` / `shared_preferences` / a port)?
- **Why blocked:** background execution + OS suspension behavior is **the**
  thing that must be tested on-device; this is the hardest and riskiest item and
  is meaningless to validate without one. Depends on #3/#4.

### #11 — Automatic detection has no live entry point
`TripDetectionCoordinator.startListening()` is only ever called by the
coordinator restarting itself; nothing in `lib/` starts it, so auto-detection
never runs.

- **Decision needed (product):** when should auto-detection start? On app launch
  once permissions are granted? Only when a "background tracking" setting is on?
  Tied to the foreground service? This is a UX/product decision, not a code one.
- **Why blocked:** depends on #2 (a lifecycle owner to attach to) and #3, and on
  your answer to the product question above.

---

## Dependency order (when you're ready to proceed, with a device)

```
#5  (providerize streams — unblocks testing + dedups subscriptions)
  └─> #2  (decide session ownership / keepAlive)
        └─> #3  (implement motion-gated GPS — pick architecture)
              ├─> #4  (wire adaptive settings into the now-gated streams)
              ├─> #11 (start the coordinator from a real lifecycle owner)
              └─> #7/#8 (reconcile background isolate; one source of truth)
```

## What I need from you to move forward

1. The three product/architecture decisions above (#2 ownership, #3 architecture,
   #11 trigger).
2. Confirmation you (or someone) can run on a physical Android/iOS device to
   validate: GPS-stops-when-stationary, trip-survives-backgrounding, background
   recording continues, and battery drain ≤ ~5%/hr.

With those, the right approach is to take it one step at a time down the
dependency chain — implement, then validate on-device, then proceed — rather
than landing the whole cluster at once. I can drive each step (including writing
the device test checklist) once the decisions are made and a test device is
available.
