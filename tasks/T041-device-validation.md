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

**2026-09-01, Pixel 6a (Android 17 / API 37, release APK)** — first Android device
run. Sideloading required uninstalling the Play build (upload key vs Play signing
key), which is what exposed L-072: on a clean install the app crash-looped at launch
with `Bad notification for startForeground` until the OS restricted it, because the
foreground service's notification channel did not exist yet. Fixed by awaiting
`notificationServiceProvider` in `BackgroundLocationService.initialize()`; the app
then launches and reaches the "Always"/precise-location settings prompt of item 6.
The checklist items below are still unrun on Android.

Code complete on `develop` (`7afb833` → `529db42` → `da3ad62`, 245 tests green).
None of the items below are observable from `flutter analyze`/`flutter test` or on an
emulator — run them on a physical device in `--release` mode. T041 (and the reopened
halves of T006/T013) close only when this checklist passes.

## 0. Before you start — turn the diagnostic log on (T043)

Most of the items below cannot be settled by watching the phone. Several say "log line to look
for", and until T043 those lines existed only in a debug build with a cable attached. They are now
recorded on-device and exportable.

**Settings → Diagnostic log → on**, pick the level from the table, ride, then
**Export log…** and send the `.ndjson.gz`. Analyse it with the `autoride-audit-log` skill, which
carries the event schema, the jq recipes and a per-item verdict procedure.

| Item | Level | Events that decide it |
|---|---|---|
| 1 — GPS stops when stationary | normal | `gate sched` → 30 s with no `fix` → `gate close`, then **no** `fix` |
| 4 — battery drain | **normal, never verbose** | `bat` every 5 min, `pwr`, and the summed `gate open`→`close` time |
| 8 — detection with the screen off | normal | `perm k:background` (`alw` must be true), `fgs a:start` with its `plat` — never `a:fail` —, then `app paused`, `hb` with `mn > 0` and no `app resumed`, then `trip start` |
| 9 — auto-pause/stop, phone carried | **verbose** | `win` (`sd`/`gy`/`sta`/`src`/`spk`), `stop`, `res`, `st` |
| 10 — trip ends on GPS loss | normal | `gpsw arm` → `gpsw fire` → `log` warning → `trip stop` |
| 11 — trip starts where riding started | verbose | `bdate` plus the `fix` lines preceding it |

Two things to keep in mind when reading a log:

- **The log is not a free observer.** It writes to its own database, so item 4 must be measured at
  *normal* level, and a control run with the log off is worth doing before quoting a drain figure.
- **Read the header first.** Its `k` block holds the thresholds of the build that produced the
  file. Interpreting an old log against today's `AppConstants` is how you reach the opposite
  conclusion.

Item 1 keeps one irreducible gap: the OS location indicator is not observable from Dart, so the
log proves the app stopped *asking* for positions, not that the OS switched the chip off. It does
give the exact instant the indicator should go dark, which turns a vague observation into a
checkable one.

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

**The foreground service is Android-only.** On iOS `flutter_background_service` merely
spins up a second FlutterEngine and holds no notification, so an `fgs start` there says
nothing about the process surviving. What keeps an iOS process alive in the background is
`UIBackgroundModes: location` (present) **plus** an "Always" authorisation — the two OSes
therefore fail this item for different reasons and must be judged on different evidence.
`BGTaskSchedulerPermittedIdentifiers` is now declared (2026-09-02) so the plugin's BGAppRefresh
submit no longer throws, but that path is *not* how this item passes: a 15-minute app-refresh
window cannot catch the start of a ride, and `onIosBackground` is still a stub.

**2026-09-02, iPhone 14,3 / iOS 26.6.1 and Pixel 6a (release, 1.0.0+8) — iOS FAILED,
Android unrun.**

- iPhone: not one `fgs` line in the whole log. Both session starts (14:26:37, 15:09:59)
  end in `err AutoDetectionController "Failed to start the foreground service"` with
  `Cannot use the Ref of backgroundLocationServiceProvider after it has been disposed`.
  Root cause: the provider was autoDispose and only ever reached through a bare
  `ref.read(...notifier)`, so it was destroyed inside `await initialize()` and the
  `state =` at the end of `startTracking` threw — swallowed by the controller's catch.
  Fixed by making it `keepAlive`; the failure is now journalled as `fgs a:fail`. It is a
  race, so Android was one scheduler tick from the same outcome.
- iPhone, and this is the item-8 verdict proper: the process ran fine backgrounded
  (`app paused` 14:27:20) for 2 min 20 with seven clean heartbeats (`n` 31, `mn` ~3084 —
  sensors at ~100 Hz), then stopped dead at 14:29:42. The next line is 40 min 17 s later
  and is a **cold start**, not a resume: no `hb` came back carrying a large `dt`, so iOS
  *terminated* the process rather than suspending it. That is the signature of "While
  Using" rather than "Always" — and nothing in the log said which was granted. `fn` is 0
  on every one of those heartbeats: the GPS gate was nominally open but stationary, so no
  fix flowed.
- Pixel 6a: `fgs {"a":"start"}` 23 ms after its `sess start`, 31 heartbeats — the service
  path works. But no ride was taken screen-off in that log, so item 8 itself is **still
  unrun on Android**.
- Instrumentation added for the next run: a `perm` line with `k` = background reporting
  `alw` (Always granted), `acc` (precise/reduced) and `issue`, emitted on every session
  start and on every change, plus `plat` on every `fgs` line. Reading it settles the
  question above in one grep instead of a second field session.

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

## 10. Trip ends when GPS is lost for good (L-074, added 2026-09-01)
A recording trip is now stopped by the coordinator when no GPS fix has been received for
`AppConstants.gpsLossStopTimeout` (10 min), counted from the last fix or, while none has
arrived yet, from the start of the trip. Before this, a trip could stay active for hours
on stray gyroscope motion alone — the phone forgotten indoors, location services turned
off mid-ride — because `locationStreamProvider` re-subscribes forever with backoff and
the stop detector falls back to sensors when the fix is stale.

**To validate:**

- **Terminal loss**: start a trip (manual start is enough), ride a few minutes, then turn
  **Location services off** at the OS level and keep the phone moving (walk with it). The
  trip must finalize ~10 min after the last fix, appear in History with the distance
  recorded up to the outage, and the foreground notification must return to the
  "detecting" phase. Log line to look for: `No GPS fix for …s (limit 600s) — stopping the
  trip`.
- **Recoverable outage must NOT stop the trip**: ride through a tunnel / underground car
  park for 2–4 min. The trip must survive and resume accumulating points on the far side.
- **Slow first fix**: start a trip indoors (manual start) and step outside within a couple
  of minutes. The trip must not be stopped while waiting for the first fix.
- **Sub-60 s case**: the L-068 rule is unchanged — a trip stopped this way that lasted
  less than `minTripDurationSeconds` is deleted, not saved, and shows no end-of-trip
  notification.

**Known gap**: the watchdog lives in the coordinator, so it only supervises a trip while a
detection session is running. A manual ride started with *automatic detection off* has no
coordinator session at all, and therefore no GPS-loss stop (it has no auto-pause or
auto-stop either — same pre-existing limitation).

## 11. The trip begins where the riding began, not at confirmation (L-076, added 2026-09-01)
The coordinator now buffers the GPS fixes it receives during the detection phase and
replays them into the recorder when a trip is confirmed, back-dating `startTime` to the
first replayed point that survives the recording filters. Before this, a ride's first
50–200 m and 10–40 s were silently dropped: the gate opens on movement, confirmation takes
seconds, and the recorder started counting from its own second fix.

**To validate:**

- **The head of the trip is there**: from a cold stop, set off on a straight, recognisable
  stretch (a long street, a canal path) with automatic detection on. When the trip appears
  in History, its route must start at or very near where you actually set off — not one
  street further on. Compare against the same departure recorded with the **manual** start
  button, which deliberately prefixes nothing.
- **The walk is not in it**: carry the phone on foot for 100–200 m to where the bike is
  parked, then ride off. The recorded route must begin at the bike, not at the front door,
  and the distance must not include the walk. Only fixes at ≥ `cyclingSpeedMin` (8 km/h)
  open the prefix. Log line to look for: `Trip N back-dated to … from K pre-trip fixes
  (D m already covered)`.
- **Duration and average speed agree**: the trip's moving time must cover the back-dated
  start (so a trip confirmed 30 s after departure reads ~30 s longer than before), and the
  average speed must stay plausible — a back-dated start with the distance missing would
  show as an implausibly low average.
- **Nothing is prefixed after a long stop**: stand still long enough for the GPS gate to
  close (`gpsInactivityTimeout`, 30 s), then set off. The buffer is emptied when the gate
  closes, so the trip starts at the new departure and carries nothing from before the stop.
- **Sub-60 s interaction (L-068)**: the rule is unchanged, and the duration it judges now
  *includes* the prefix. A genuine short ride that was previously deleted because
  confirmation ate most of its length should now survive; a real false start (a bump, a
  mis-tap) still has no fixes above 8 km/h to prefix, still measures only the seconds it
  lasted, and is still deleted with its points.

---

## Appendix — the intended three-layer cycling detector

Moved out of `CLAUDE.md` (2026-09-02): it described a target design, not current
behaviour, and cost 36 lines in the always-loaded file. `CyclingPatternDetector`
implements it; nothing in `lib/` calls it. See `tasks/LEDGER.md` L-011.

**Multi-layer approach**

1. **Motion pattern analysis** (layer 1)
   - Acceleration range: 10–20 m/s² (cycling range)
   - Rotation range: 0.5–3.0 rad/s (pedaling motion)
   - Score: 0–1 based on how well values fit the cycling profile

2. **Pedaling frequency analysis** (layer 2)
   - Detect peaks in acceleration (pedaling cycles)
   - Expected frequency: 0.5–2.0 Hz (30–120 RPM)
   - Typical: 1.2 Hz (72 RPM)

3. **GPS speed validation** (layer 3, when available)
   - Cycling speed range: 8–40 km/h — typical 18 km/h
   - Too slow (< 8): likely walking · too fast (> 40): likely driving
   - **Not reachable today**: `currentLocation` is never assigned, so `speedScore`
     is a hardcoded 0.5.

**Final confidence score**: motion 40 % + speed 35 % + frequency 25 %, with a
minimum of 0.6 for detection. All thresholds live in
`lib/core/constants/app_constants.dart`.
