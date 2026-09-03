# T046 — iOS Background Survival

**Status**: implemented, **awaiting device validation**. The five runs of §5 are what close it —
and with it T041 item 8 on iOS.

**Findings**: ledger L-084 (closed pending the runs), decision paragraph in ledger §6.
**Cross-refs**: L-067 (the Android half of the same problem), L-078, T041 item 8, T048 (whose
start-confidence work this must not undo), `platform-config` skill.

---

## 1. The two failures

**(a) The app stops tracking as soon as the rider does.** The GPS gate is motion-driven
(audit #3): `_closeGpsGate` cancels the location subscription when the rider has been
stationary for `gpsInactivityTimeout`. On Android that costs nothing — the foreground service
holds the process regardless (L-067). On iOS the location session **is** the process's reason
to be scheduled, so closing the gate removes the last one. Measured 2026-09-02, with `alw:true`
and `fgs start plat:ios` both present: gate closed on `inactivityTimeout` at 16:04:51, the
process suspended 40 s later, heartbeats returning at 16:21, 16:36 and 19:07 with `dt` up to
2 h 31. `sensors_plus` does not deliver to a suspended process, so the motion that was supposed
to re-open the gate never arrived — the state is absorbing. The whole outing is invisible.

**(b) Nothing can bring the app back.** After a kill (OS memory pressure, a crash) or a reboot,
no path existed by which the process could run again without the user opening the app. iOS
relaunches a terminated app for exactly three things: significant location changes, region
monitoring, and visits. **geolocator exposes none of them.**

---

## 2. What shipped

| Job | Owner | Mechanism |
|---|---|---|
| Keep the process alive while idle | Swift | `CLLocationManager`, 3 km accuracy / 3 km distance filter |
| Relaunch after kill or reboot | Swift | significant-change + visits, armed while detection is on |
| Record a ride | Dart | `locationStreamProvider` via geolocator — **unchanged** |
| Decide a ride has started | Dart | coordinator + detectors — **unchanged** |

- `ios/Runner/AutoRideBackgroundSession.swift` — the native manager. `bootstrap` runs
  synchronously from `didFinishLaunchingWithOptions` (before `super`, before any Dart), reads
  the persisted `autoride.detectionArmed` flag and re-arms monitoring: the event that relaunched
  the process is delivered only to a manager already monitoring by the time launch returns.
  Holds a `CLBackgroundActivitySession` on iOS 17+.
- `lib/features/trip_detection/data/services/ios_background_session.dart` — the channel wrapper.
  A complete no-op off iOS, so no caller branches on the platform.
- `trip_detection_coordinator.dart` — hands the native session the **complement** of the gate,
  including at `startListening`, where a session starting with the gate closed makes no
  transition at all and that is exactly the window that was being lost.
- `auto_detection_controller.dart` — arms and disarms the relaunch monitoring with
  `_appliedShouldListen`, the iOS counterpart of `_syncForegroundService`.
- `main.dart` — the audit log, trip recovery and `AutoDetectionController` no longer wait for a
  frame. A process relaunched into the background may never produce one.

**Native fixes are never positions.** Coarse, significant-change and visit deliveries cross the
channel as `ios` audit lines and stop there. A 3 km fix reaching `_lastLocation`, the pre-trip
buffer or `GpsSpeedEstimator` would cap the start confidence exactly the way L-087's bogus
0 km/h did.

---

## 2b. Xcode / privacy — what T046 needed, and what it did not

Checked against Apple's documentation on 2026-09-03, not from memory.

- **`Info.plist`: nothing to add.** `UIBackgroundModes` already contains `location`, and
  `NSLocationAlwaysAndWhenInUseUsageDescription` is present. `allowsBackgroundLocationUpdates`
  requires only that key; setting it *without* the key is a fatal error that terminates the app,
  which is why `applyBackgroundFlags()` is written the way it is.
- **No entitlement, no capability.** `startMonitoringSignificantLocationChanges`,
  `startMonitoringVisits` and `CLBackgroundActivitySession` need none. Ticking Background Modes →
  Location updates in Xcode does nothing but write the `Info.plist` key already present.
- **`PrivacyInfo.xcprivacy`: nothing to add for CoreLocation.** There are exactly five
  required-reason API categories — `FileTimestamp`, `SystemBootTime`, `DiskSpace`,
  `ActiveKeyboards`, `UserDefaults` — and no CoreLocation API is in any of them. Location is
  covered by `NSPrivacyCollectedDataTypes`, already declared.
- **One thing *was* wrong, and it predates T046.** The manifest declared the User Defaults reason
  as `1C8F.1`, which is the **App Group** case. AutoRide has no App Group — the project carries no
  `.entitlements` file — so the declaration asserted something untrue. Corrected to `CA92.1`
  ("only accessible to the app itself"). T046 is what made it worth finding: the native session
  writes `autoride.detectionArmed` to `UserDefaults` directly, so the category is now reached from
  two places rather than one.
- **The blue indicator is now permanent while idle.** `showsBackgroundLocationIndicator = true` is
  deliberate: it is honest, and during runs 1–5 below it is the only signal visible from outside
  the app that the session is really running. If it proves too intrusive in daily use it is one
  line in `applyBackgroundFlags()`.

---

## 3. Reading the log

New event `ios` (see the `autoride-audit-log` skill). The three lines that matter:

```
ios {a:"keepAlive", on:true}     # right after a `gate close` — the process is being held up
ios {a:"arm"}                    # relaunch monitoring is on; the iOS peer of `fgs start`
ios {a:"bootstrap", lr:"location"}  # iOS relaunched a TERMINATED process. The only proof.
```

A `gate close` with no `keepAlive` after it, followed by a heartbeat carrying a large `dt`, is
failure (a) happening.

---

## 4. Assumed limits

iOS properties, not defects, and there is no API for any of them:

- **Force quit by the user** (swipe up in the app switcher): iOS stops all background delivery
  until the app is opened again.
- **Reboot**: nothing runs until the first unlock (data protection), then nothing runs until the
  first significant change. A ride begun straight after a reboot loses its first ~500 m.
- **Low Power Mode / precise location off**: tracking continues, degraded.

---

## 5. Device validation — the protocol that closes this task

iPhone, **release** build, "Always" + precise granted, automatic detection on, audit log at
**verbose**. Export and read with the `autoride-audit-log` skill. Nothing but these runs closes
T046 or T041 item 8 on iOS.

| # | Run | Passes when |
|---|---|---|
| 1 | Idle survival — app backgrounded, screen off, phone at rest 30 min | Heartbeats continuous, no `dt` above a couple of minutes, and an `ios {a:"keepAlive", on:true}` after the `gate close`. This is the run that failed for 2 h 31 on 2026-09-02. |
| 2 | Departure after a long stop — ride off straight after run 1 | A trip auto-starts without the screen ever waking. **This is T041 item 8 proper.** |
| 3 | Kill — `xcrun devicectl device process terminate`, then move > 500 m | A new launch header followed by `ios {a:"bootstrap", lr:"location"}`. |
| 4 | Reboot — restart, unlock once, do **not** open the app, move > 500 m | Same as run 3. |
| 5 | Disarm — turn detection off in Settings, kill the app, move > 500 m | **No** relaunch at all. This is what proves `disarm` works; without it iOS keeps waking an app whose feature the user switched off. |
| 6 | Battery — re-measure T041 item 4 over a full day | The permanently-held coarse session is precisely the risk this change adds. |

Run 5 is the one most likely to be skipped and the one whose failure is least visible: a missing
disarm costs battery silently, for ever, on a feature the user believes is off.
