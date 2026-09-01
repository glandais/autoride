# T041 — On-Device Validation Checklist

## Validation log

**2026-09-01, iPhone (dev build)** — first on-device run:
- Onboarding completes; the iOS **location prompt appears with the correct usage
  string**, and the notification permission is granted (setup-complete shows
  Location ✓ / Trip Notifications ✓) → item 7 is validated for location and
  notifications; the motion prompt is still unverified. The SPM concern is
  largely allayed for these two.
- "Automatic Tracking ✗" reflects the user choosing "While Using" instead of
  "Always" — expected; foreground detection runs anyway (badge "Detecting",
  "Analyzing motion…").
- **Bug found**: "Start ride now" crashed with *Null check operator used on a
  null value* — the manual start fired before the recorder's async build had
  opened the database. Fixed in `856f7a8` (lazy init + regression test).
  **Retest manual start on the next build**; TestFlight build 3 still carries
  the bug.

**2026-09-01, iPhone 13 Pro (release, `4559820`)** — background-location status:
- "While Using" instead of "Always" shows the banner above the navigation bar and
  the settings switch off with `Location is not set to "Always"`; choosing "Always"
  in Settings and returning clears both without a restart. Item 7's SPM concern is
  closed: "Always" appears in Settings, so `requestAlwaysAuthorization` did run
  (the plugin's `Package.swift` derives `PERMISSION_LOCATION` from `Info.plist`;
  the Podfile macros are dead but harmless).
- "Precise Location" off shows the precise-location banner and subtitle; on again
  clears them.

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
- An ongoing notification is present for the whole time automatic detection is on
  ("AutoRide - Auto detection" / "Waiting for a bike trip") — since the foreground
  service now covers the listening phase too, see item 8.
- Its content switches to distance • duration when a trip starts, updating ~every 5 s,
  and switches back to the waiting text when the trip ends (detection still on).
- With automatic detection OFF, no notification exists until a manual ride starts, and
  it disappears when that ride ends.
- Pause/Stop actions work; it disappears on trip end via all three paths
  (auto-stop, UI stop, notification-action stop).
- Exactly one notification (id 888) exists — the foreground service owns it.

## 6. Toggle and permission semantics (#11 / L-001)

- Turn "Automatic detection" OFF mid-ride: the ride keeps recording and finishes
  normally; no new trip auto-starts afterwards.
- Turn it back ON: detection resumes without restarting the app.
- Grant location from system settings while the app is backgrounded: detection
  starts on resume.
- Downgrade to "While Using" (iOS) / revoke "Allow all the time" (Android), or
  turn off precise location, then return: the home banner appears and the
  settings switch turns off; reverting clears them (L-071). ✅ iOS 2026-09-01;
  Android pending.

## 7. iOS permission prompts (T039 finding — added 2026-09-01)
Flutter 3.47 resolves `permission_handler_apple` via Swift Package Manager, so the
Podfile's `PERMISSION_LOCATION/NOTIFICATIONS/SENSORS=1` post_install macros no longer
reach the plugin (the `cc1c088` fix is bypassed). On a physical iPhone, verify that
the location (when-in-use → always), notification, and motion permission prompts all
actually appear and that granted permissions report correctly. If prompts are missing,
the SPM package needs the compile-time flags supplied another way.

**Resolved 2026-09-01 for location** (see the validation log): `permission_handler_apple`'s
`Package.swift` reads the `NSLocation*`/notification keys from `Info.plist` at manifest
evaluation, so the flags are supplied by the plist itself. The Podfile macros are dead
code. Still to confirm on device: the motion prompt (`NSMotionUsageDescription`).

## 8. Automatic detection with the screen off (added 2026-09-01)
The foreground service used to run only during a recording, so with the screen off the
process was Doze-suspended during the detection phase and `sensors_plus` delivered
nothing — auto-start could never fire with the phone in a pocket. The service now runs
for the whole listening window.

**To validate:** automatic detection ON, permissions granted, app backgrounded and the
screen **off**, phone in a pocket; ride off. A trip must auto-start (and be visible in
History afterwards) without ever waking the screen. Repeat on Android with battery
optimization enabled for the app. Then re-measure item 4's drain — the detection phase
now holds a foreground service continuously, which is the main risk this change adds.

## 9. Auto-pause / auto-stop with the phone carried (L-070, added 2026-09-01)
The stationary verdict is now computed over a 1.5 s sliding window (accelerometer
std-dev ≤ 0.8 m/s², mean gyroscope ≤ 0.6 rad/s) with a fresh GPS fix overriding it in
both directions (≥ 6 km/h ⇒ moving, < 3 km/h ⇒ standing still). The previous
instantaneous test made auto-pause practically unreachable with the phone in a pocket.

**To validate**, phone carried the way it normally is (pocket or pannier, *not* mounted
on the bars), automatic detection ON:

- **Red light**: stop for ~40 s mid-ride. The trip must switch to *paused* at ~30 s
  (notification/UI), and the recorded active duration must exclude the stop.
- **Resume**: ride off again. The trip must return to *active* within ~5 s and keep the
  same trip (History shows one ride, not two).
- **Auto-stop after 5 min**: stop and stay put for >5 min, shuffling the bike or walking
  a couple of steps every ~10 s (the "zombie pause" case). The trip must finalize at
  ~300 s of pause and appear in History; it must NOT stay paused indefinitely.
- **False pause check**: 20 min of normal riding including rough surfaces and slow
  climbs (< 8 km/h) must produce no unintended pause.
- **Basket case**: phone lying flat and still in a basket/pannier while riding — no
  pause must occur (GPS speed must win over the calm sensors).
