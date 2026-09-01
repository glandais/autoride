# T041 — On-Device Validation Checklist

Code complete on `develop` (`7afb833` → `529db42` → `da3ad62`, 245 tests green).
None of the items below are observable from `flutter analyze`/`flutter test` or on an
emulator — run them on a physical device in `--release` mode. T041 (and the reopened
halves of T006/T013) close only when this checklist passes.

## 1. GPS stops when stationary (T006 / L-004)
- Automatic detection ON, permissions granted, app open, phone at rest for
  ≥ `gpsInactivityTimeout` (30 s): the OS location indicator must go dark and stay dark.
- Shake/walk: the indicator returns within a sample or two.
- Repeat with the Trip tab open but no trip running: the map marker must **not** keep
  GPS alive (the marker only streams while recording).

## 2. Trip survives backgrounding and tab switches (#2 / L-005)
- Start a ride (manual button, and separately by riding until auto-start fires).
- Switch to the History tab, then to another app for 5+ minutes.
- On return: distance/duration advanced continuously, route has no gap.

## 3. Background recording under OS suspension (#7/#8 / L-007)
- Same ride, screen off, phone in pocket 15–20 min (Android: also with battery
  optimization enabled for the app).
- Recording continues; the trip's route points cover the whole window.

## 4. Battery drain ≤ ~5 %/hr (T006 / L-006)
- One hour of active tracking in release mode, screen off, per power mode
  (at least Normal and Low).
- Measure battery delta plus Android Studio Profiler → Energy / Xcode Energy Impact.

## 5. Notification behaviour
- No ongoing notification while merely detecting.
- Appears when a trip starts; content updates ~every 5 s with distance • duration.
- Pause/Stop actions work; it disappears on trip end via all three paths
  (auto-stop, UI stop, notification-action stop).
- Exactly one notification (id 888) exists — the foreground service owns it.

## 6. Toggle and permission semantics (#11 / L-001)

- Turn "Automatic detection" OFF mid-ride: the ride keeps recording and finishes
  normally; no new trip auto-starts afterwards.
- Turn it back ON: detection resumes without restarting the app.
- Grant location from system settings while the app is backgrounded: detection
  starts on resume.

## 7. iOS permission prompts (T039 finding — added 2026-09-01)
Flutter 3.47 resolves `permission_handler_apple` via Swift Package Manager, so the
Podfile's `PERMISSION_LOCATION/NOTIFICATIONS/SENSORS=1` post_install macros no longer
reach the plugin (the `cc1c088` fix is bypassed). On a physical iPhone, verify that
the location (when-in-use → always), notification, and motion permission prompts all
actually appear and that granted permissions report correctly. If prompts are missing,
the SPM package needs the compile-time flags supplied another way.
