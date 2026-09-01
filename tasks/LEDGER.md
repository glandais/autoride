# AutoRide — Project State Ledger

**Date**: 2026-08-31
**Branch**: `develop` @ `d6a53f7` (clean tree)
**Toolchain**: Flutter 3.47.2 / Dart 3.13.2
**Gates at time of audit**: `flutter analyze` → *No issues found!* · `flutter test` → *190/190 passed* · line coverage 869/1698 = **51.2%**

> **Remediation status (2026-08-31)**: steps 1–3 of §5 are done — see the **Remediation log** below. Sections 1–4 are the audit snapshot at `d6a53f7` and are intentionally left unmodified; consult the log for which findings are since closed.

## Remediation log

Executed the same day as the audit, one commit per step, each by an Opus subagent whose changes were reviewed and gate-checked before committing. Gates after step 3: `flutter analyze` clean, **191/191 tests** (+1 regression test).

| Step | Commit | Findings closed | Notes |
|---|---|---|---|
| — | `3cb0aad` | — | This ledger added. |
| 1 — tracker truth | `b84bc88` | L-019, L-020, L-036, L-037, L-041 (annotated), L-053 (annotated), L-054 | T041 added as ⚠️ Blocked with the three maintainer decisions; T006/T013 reopened. Honest count is `Blocked: 3` (T006, T013, T041), not the `Blocked: 1` §5 step 1 suggests. T029/T033 kept ☐ with status notes; the T033 dependency of T038/T039 recorded as a caveat, not silently dropped. |
| 2 — docs truth | `9fcfd6e` | L-021, L-028 (README side), L-038, L-039, L-040, L-052, L-055, L-056 | `docs/` needed no changes (L-065 re-verified). Corrections to this ledger's own claims: L-039's build_runner drift was in **10** places, not 5; L-055's "three map widgets" is two widgets plus one screen; L-021 omits that `tflite_flutter` *is* declared in pubspec (unused). README's false "Force start" line (L-001's doc surface) also future-tagged. |
| 3 — bounded code fixes | `11e74b7` | L-008, L-009, L-016, L-022, L-023, L-025, L-029, L-030, L-031, L-042, L-044, L-046; L-012/L-024 annotated (`TODO(T041)`, nothing deleted) | 34 files, +758/−150. L-042's strict modes surfaced one real bug (a `dynamic` `Trip` field), fixed. L-028's manifest side (undeclared `ACTIVITY_RECOGNITION` still modelled in the permission layer) and L-043 remain open — not on the step-3 list. **Caveat on L-008**: the retry path has no test; the buffer is only fillable through the un-injectable `locationStream(ref)` call (L-002), testable after T041 #5. |
| 4a — T041 #5+#2 | `7afb833` | L-002, L-003, L-005, L-010; L-015 and the L-008 test caveat closed (tests 191→219) | All six call sites providerized; trip-scoped `ref.keepAlive()`. Discovery contradicting the blocked doc's option list: Riverpod 3 deactivates `ref.listen` subscriptions when the last listener leaves even under keepAlive, so session streams are container-owned and closed by hand — option 1 (`keepAlive: true`) would have had the same silent-starvation defect. |
| 4b — T041 #3+#4 | `529db42` | L-004, L-006 (tests →227) | GPS gating in the coordinator (decision b), `GPSController` + test deleted; power modes drive location settings and sensor Hz; named `distanceFilterLowPower`/`CriticalPower` added, dead `distanceFilter` removed (part of L-024). |
| 4c — T041 #11+#7/#8 | `da3ad62` | L-001, L-007; L-025's follow-up (marker no longer defeats the gate); L-045 partially (`AutoDetectionState` is freezed) (tests →245) | `AutoDetectionController` + `automaticDetectionEnabled` setting (default ON, decision c); manual start button; coordinator no longer suspends mid-trip so auto-pause/stop is reachable; isolate reduced to notification-holder per decision (d), `location_tracking_provider` deleted. Replaced the unread `autoStartEnabled` tile (field kept for now). |

| 5a — unit-test recut | `a3dd31c` | L-014, L-026, L-011 (test side) | Database tests run the production schema (`onCreate`/`onUpgrade` made public — rename only; DDL helper reduced to zero SQL); real `CyclingPatternDetector` tests pin the layer-3 quirk **and a new consequence: hardcoded speedScore 0.5 also makes the walking/driving classification arms unreachable** (extends L-011); sensor/permission tests exercise their real units via platform-interface seams. Coverage: database 0→29/31, detector 0→80/89, sensors 19→41/43, permissions 0→58/58. Ledger correction: L-026's "0/37 on SensorService" was already stale after T041 part 1 (19/43 at start). |
| 5b — widget tests | `99eae4c` | L-013 (started) | 25 `testWidgets` (repo had zero): onboarding permission flow incl. POST_NOTIFICATIONS paths, tracking screen idle/active/pause/stop, HomeShell tab-switch session guarantee. Shared fakes in `test/helpers/widget/`. T030 stays ⏳ — settings/history/detail screens and map interactions remain. |

| 6a — T039 iOS release | `1857040` | L-017 (code side), L-049 | Modeled on ../tribly/mobile: ios/fastlane beta+release lanes (ASC API-key auth instead of tribly's interactive session), export compliance verified HTTPS-only, iPhone-only targeting, automatic signing, publish_beta.sh does iOS-then-Android with commit/tag only after both. One-time manual steps remain (App ID/ASC record, API key, first-signing repair). **New finding**: Flutter 3.47 resolves `permission_handler_apple` via SPM, bypassing the Podfile's `PERMISSION_*` macros (`cc1c088` fix inert) — iOS permission prompts must be re-verified on device (`T041-device-validation.md` item 7); plausible TestFlight blocker. Also stale: T039's D2 premise and its deployment-target claim (toolchain auto-raised to iOS 15). |

| 6b — ASC verification | (read-only) | L-017 manual half re-scoped | Chrome + asc CLI against app 6761954840 (2026-09-01): **three of the four "one-time manual steps" were already done** — ASC record (2026-04-09, bundle id matches), App ID `WF72C6G7CS`, distribution cert (valid 2027-04-07), ASC API key (in keychain/`~/.blitz`), and a first upload already happened (two expired TestFlight builds, group `Test`). What actually remains for TestFlight: wire `ASC_*` env vars to fastlane; bump build number ≥ `+3` (train 1.0.0 already holds builds 1 and 2); no App Store provisioning profile yet (automatic signing should mint one). For store submission: 33 `asc validate` errors, App Privacy questionnaire never started, pricing/availability unset, ASC version `1.0` vs pubspec `1.0.0`, name `Autoride` vs `AutoRide` (cosmetic). App ID capability oddity: `IN_APP_PURCHASE` present, spurious. |

| 6c — store blockers cleared | `0966a0c`, `856f7a8` + ASC mutations | L-017 closed; L-018/L-050 remain (CI) | Build number → `+3`; ASC credentials wired via `~/.secrets/autoride-asc.env`. **TestFlight build 3 uploaded and VALID** (existing April profile reused — no signing repair needed). ASC surface: `asc validate` 33 → 3 errors (name AutoRide, version 1.0.0, metadata, App Privacy published per data-safety.md, age rating 4+, content rights, free + 175 territories). Remaining: review-details **phone number** (user input), build attach, screenshots. First on-device iOS run validated the permission prompts (SPM concern allayed for location/notifications) and caught a real bug — manual start before the recorder's build completed → null-check crash, fixed in `856f7a8` (build 3 still carries it). iOS listing copy now lives only in ASC (no git source); minOS rose 13→15 with the toolchain. |

| 6d — review details + build 4 | ASC mutations | — | App Review contact details completed (name/email/phone — the number stays out of git — plus reviewer notes: no sign-in, "Always" rationale, manual start as the no-motion test path, OSM attribution). `asc validate` now shows **2 blocking errors**: build attach and screenshots (plus one info: App Privacy publish state unverifiable via API — it was published through the UI). The maintainer launched the first full dual-platform `publish_beta.sh` run (build `1.0.0+4`, carrying the `856f7a8` crash fix); the script commits its own bump on success. Build 4 is the one to attach — build 3 carries the manual-start crash. |

| 7 — FGS covers the detection phase | (this change) | **L-067** (new) | `AutoDetectionController` now starts the Android foreground service as soon as the coordinator starts listening, not only while a trip records, and stops it when listening stops (setting off / permission revoked). Two notification phases (`AppConstants.notificationTitleDetecting`/`notificationContentDetecting` vs the trip's distance • duration). Manual-ride-with-detection-off behaviour is unchanged. Tests 331 → 339. |

| 8 — trip lifecycle in the database | (this change) | **L-068** (new) | `trips.status` (`active`/`completed`/`discarded`) added in schema **v2** with an `onUpgrade` that backfills existing rows as `completed`; the recorder inserts `active`, snapshots distance/max speed/provisional end time onto the row on the existing 30 s flush, and on stop either completes it or *deletes* a sub-`minTripDurationSeconds` false start (no end-of-trip notification for those, via `stopTrip(discarded: true)`); a new `TripRecoveryService` + `tripRecoveryProvider` closes trips left `active` by a process death, recomputing metrics from the persisted route points; every history/stats query now filters `status = 'completed'`. Tests 339 → 365. |

| 9 — the end-of-trip notification tells the truth | (this change) | **L-069** (new) | `TripStateMachine.stopTrip` no longer reads `tripRecorderServiceProvider` for the numbers it announces: the recorder now hands it the finalized `Trip` (`stopTrip({discarded, finalTrip})`). The old path read the recorder's live `TripMetrics` *after* `_stopRecording` had zeroed them, so the "trip recorded" notification announced 0 m / 0 s / 0 km/h (or, on a different interleaving, a value up to one metrics tick stale) — and, being wrapped in `whenData`, it emitted nothing at all (foreground notification included) whenever that provider was loading or in error. `cancelForegroundNotification()` is now unconditional, and the duplicated `active:`/`paused:` bodies are factored into one `_finishRecording`. Tests 365 → 370. |

| 10 — auto-pause works with a carried phone | (this change) | **L-070** (new) | `TripStopDetector` decides "stationary" over a **1.5 s sliding window** (`StationaryWindow`: accelerometer-magnitude std-dev + mean gyroscope magnitude) instead of one instantaneous 50 Hz sample, and a fresh GPS fix now outranks the sensors in both directions. The hard-coded 2 km/h literal became `stationarySpeedMaxKmh`. While the trip is *paused*, intermittent movement no longer resets the pause (`analyzeForTripStop(..., tripIsPaused: true)` from the coordinator's paused branch). Dead code removed: `TripStateMachine.hasPauseTimedOut()` (+ its test) and `AppConstants.stationaryThresholdSeconds`. Tests 370 → 376. |
| 11 — the app says when background location is insufficient | `4559820` | **L-071** (new); L-030's iOS half | `backgroundLocationStatusProvider` reads the *real* OS grant (`locationAlways` via permission_handler **plus** geolocator's accuracy) as `BackgroundLocationState` with `issue ∈ {alwaysMissing, preciseMissing, none}`, re-read on app resume and after every request. A banner above `HomeShell`'s navigation bar and the settings "Background location" switch (now bound to the OS grant, not the stored preference) show the platform-specific fix and open app settings. Fixed on the way: `PermissionRationaleDialog.show` double-popped (answer always `null`, caller's route removed), so the settings toggle had never worked. `Info.plist` gains `NSLocationTemporaryUsageDescriptionDictionary` (not yet requested from Dart). Podfile `PERMISSION_*` macros confirmed dead under SPM but harmless — the plugin's `Package.swift` derives them from `Info.plist`. Tests 376 → 402. Verified on iPhone 13 Pro. |
| 12 — the app survives its own first launch | (this change) | **L-072** (new) | `BackgroundLocationService.initialize()` awaits `notificationServiceProvider.future` before `configure()`. The foreground-service notification posts on `AppConstants.tripTrackingChannelId`, but that channel is created by `NotificationService.build()`, which nothing awaited: on a device where the channel did not already exist, `startService()` raised `CannotPostForegroundServiceNotificationException: Bad notification for startForeground` and Android crash-looped the process until `AppStandbyController` restricted the app — it simply vanished. Notification channels persist across launches, so every dev and TestFlight/Play device that had ever run the app was immune; only a **first launch after a clean install** hit it, i.e. exactly what a new Play Store user gets. Found on Pixel 6a (Android 17) after uninstalling the Play build to sideload a local release APK. |

| 13 — a trip records how long it stood still | (this change) | **L-073** (new) | `trips.pause_duration` (seconds, `INTEGER NOT NULL DEFAULT 0`) added in schema **v3**. `duration` has always been the *moving* time — the recorder subtracts the pauses before writing it — but the subtrahend lived only in `TripRecorderService`'s memory, so "45 min moving, 8 min stopped" was unreconstructible and the startup recovery had to assume `duration = end − start`. The recorder now writes the pause total on the final update *and* on the 30 s snapshot, so an interrupted trip recovers as `(end − start) − pauseDuration` (floored at 0, clamped to the surviving span) instead of over-counting every stop as ride time. Rounding fixed while in there: `_totalPauseDuration` is a `Duration` (ms) rounded once at the write, not `+= pauseDuration.inSeconds` per pause — ten 200 ms stops used to round away to 0 s and inflate the moving time. `Trip` gains `pauseDuration` plus `movingDuration` / `pausedDuration` / `totalDuration`, and the detail screen shows **Moving / Stopped / Total** tiles when `pauseDuration > 0` (otherwise the grid is unchanged, down to the "Duration" label). Tests 408 → 423 (+15). |
| 14 — a trip cannot outlive its GPS, and a finished trip resets the detectors | (this change) | **L-074** (new) | The coordinator now runs a **GPS-loss watchdog** on its existing 1 Hz supervisor: a recording (active *or* paused) trip with no fix for `AppConstants.gpsLossStopTimeout` (**10 min**) is finalized through the same `_finalizeAndStopTrip` path as an automatic stop, with an explicit warning log. The reference instant is the *reception* time of the last fix, or the trip's own start while none has arrived yet, so a slow first fix cannot end a ride. Two detector-reset bugs closed in the same file: `TripStartDetector.reset()` was called only on the `startRecording` **error** path, so a finished trip left `consecutiveDetections ≥ 3` in place and a single strong sample arriving within `tripStartDetectionWindowSeconds` of the last positive detection started the next trip on **one** sample (the streak rule silently defeated after every ride); and `TripStopDetector.reset()` is now called when a trip *starts*, not only when one ends. `TripRecorderService.stopRecording()` returns `Future<Trip?>` and logs a warning instead of throwing `StateError` when nothing is recording. Tests 423 → 430 (+7 coordinator tests, each mutation-checked: removing the watchdog tick or either detector reset fails them). |

**Decision (2026-09-01) — L-071: the app reports the OS grant it actually has, and the fix is a settings link.**
Two facts about iOS drove this. First, "Always" is never offered in the first location prompt: the
system asks "While Using / Once / Don't Allow", and the "Change to Always?" upgrade dialog appears once
per install — `permission_handler` additionally records that it asked (`NSUserDefaults`) and never asks
again. A user who tapped "Keep Only While Using" therefore lives with an app whose stored
`backgroundLocationEnabled = true` preference, onboarding "✓" and settings switch all say background
tracking is on while automatic detection can never start with the app closed. Second,
`permission_handler` ignores *accuracy*: "Always" with "Precise Location" off (iOS 14+, or Android 12+
coarse-only) reads as granted while positions are kilometres off. Choices:

1. **One provider, one state.** `BackgroundLocationState { permission, accuracy }` with a derived
   `issue`; the permission outranks the accuracy because it is the thing to fix first, and the accuracy
   is only queried when the permission is granted (asking the OS otherwise buys nothing, and
   `getLocationAccuracy` is wrapped so a plugin error can never block the UI — it falls back to
   `precise`). Kept alive and re-read on `AppLifecycleState.resumed` unconditionally, because the grant
   can be *downgraded* in system settings as well as upgraded.
2. **Tell, then link — never re-prompt.** Both surfaces (home banner, settings switch) explain what to
   change in the OS's own vocabulary ("Always" / "Precise Location" on iOS, "Allow all the time" /
   "Precise" on Android) and open app settings. The settings toggle still tries a request first when the
   permission is missing — that is the one path Android < 11 can prompt on — but a permanently-denied
   result (what iOS reports once its one-shot upgrade prompt is spent) lands on the settings dialog
   instead of escaping as an uncaught exception, and a reduced-accuracy state skips the request
   entirely. Turning the switch off explains that revocation happens in system settings; the app
   persists nothing, because the preference had no consumer and lying about the OS is the bug.
3. **Banner placement.** Above the navigation bar, not the top of the body: each tab owns its app bar,
   so a top banner sat under the status bar and above the screen title (seen on the first device run).
4. **Not done, deliberately.** `requestTemporaryFullAccuracy` is not called; the plist key is in place
   so a later change can ask for precise location for the duration of a ride, but the permanent setting
   is what automatic detection needs and that can only be granted in Settings.

The `PermissionRationaleDialog.show` double pop was found because the settings switch never reached the
request: its buttons already pop, and `show`'s callbacks popped again, so the future resolved `null` and
the *settings screen* left the navigator. `show` now captures the answer from the callbacks.

**Decision (2026-09-01) — L-073: the stopped time is a stored column, not a re-derivation, and the individual intervals are not stored.**
`duration` was already the moving time, so nothing about how a ride reads had to change — the only
question was where the number that was subtracted goes. Four choices:

* **A total, not a table.** A `trip_pauses` table (one row per interval: start, end, whether it was the
  auto-pause or the user's button) would answer questions nothing asks today — where on the route the
  rider stopped, how the auto-pause behaved over a ride, a moving-time chart. Every display surface that
  exists wants one number, and the total is exactly recoverable from the intervals if that changes, so
  the table stays a **possible extension**, deliberately not built here. Whoever builds it should note
  the two write points (`_stopRecording` and `_persistPartialMetrics`) and that the recovery would then
  be able to close an interval left open by a process death, which the total cannot.
* **Stored, not derived.** `pauseDuration` could have been computed as `tripDuration − duration` instead
  of persisted. It cannot: `duration` is floored at 0 and rounded, `endTime` is provisional between
  snapshots, and the recovery *rewrites* `endTime` to the last route point — so the difference silently
  becomes "however much of the ride was lost", not "how long the rider stood still". A column that says
  0 for pre-v3 rows is honest; a subtraction that invents 4 minutes of stopping is not.
* **Rounded once, at the write.** `_totalPauseDuration += pause.inSeconds` truncated up to 999 ms *per
  pause*. Auto-pause fires at every stop of a commute, so the error accumulated in one direction: the
  moving time drifted upwards and the average speed with it. The total is now a `Duration` and the
  in-progress pause is added on demand (`_pauseTotalAt`), with `_movingSeconds` doing the single
  rounding — and clamping at 0, so a clock adjustment cannot produce a −3 s ride.
* **The recovery trusts the snapshot only as far as it goes.** A pause total larger than the span the
  surviving route points describe (the snapshot outlived the last point that reached disk) is clamped to
  that span rather than producing a negative duration. What is genuinely lost is at most one flush
  interval of an in-progress pause — 30 s — which is well inside the noise of a recovered ride.

On the UI: the fourth tile pair appears only when `pauseDuration > 0`, and the existing "Duration" tile is
relabelled "Moving" only in that case. A "Stopped: 0s" tile on every pre-v3 ride would be a worse lie than
silence, and renaming a label users already read costs more than it explains when there is nothing beside
it to confuse it with.

**Decision (2026-09-01) — L-067: the foreground service covers the whole listening window, not just recordings.**
The service was scoped to a recording (decision (d) of step 4c). That left the detection phase with no
foreground service and no wake lock, so with the screen off Android suspends the process under Doze,
`sensors_plus` stops delivering and automatic detection can never fire with the phone in a pocket — the
app's headline feature. The alternatives considered were a wake lock (`wakelock_plus` is declared but
unused) and `WorkManager`-style periodic wakeups; both are strictly worse (a wake lock without a
foreground service is still killable, and periodic wakeups miss the start of a ride). Cost: a permanent
ongoing notification and a continuously-running service while detection is on — the battery figure of
`tasks/T041-device-validation.md` item 4 must be re-measured, and item 8 was added to validate the
screen-off auto-start. No manifest change: the service is already `foregroundServiceType="location"` with
`FOREGROUND_SERVICE_LOCATION` declared, and both start paths run with the app in the foreground (Android
12+ forbids background FGS starts) with the location permission already granted (Android 14+ requires it
for a `location`-type service).

**Decision (2026-09-01) — L-068: a trip's lifetime is a database column, and false starts are deleted rather than kept.**
The `trips` row has always been inserted at *start* (route points need a foreign key), with `end_time =
start_time`, 0 m and 0 s, and nothing ever marked it unfinished — the `FIXME(T009)` in
`database_service.dart` had named the gap since T009. Two consequences were reachable in a shipped build:
an app kill mid-ride left that empty row in history forever as a phantom trip, and `Trip.isValidTrip`
(the ≥ 60 s rule) was never applied to anything, so a 3-second mis-tap on the manual start button became
a permanent entry too. Three choices were made:

* **Discarded vs deleted.** A rejected recording is *deleted*, not stored as `status = 'discarded'`.
  `route_points.trip_id` already carries `ON DELETE CASCADE` with `PRAGMA foreign_keys = ON`, so one
  delete removes the whole thing and leaves nothing for a later export, statistic or migration to trip
  over. The `discarded` value stays in the enum and the schema so that a row which ever acquires it is
  still hidden from history rather than silently reappearing there — and so that failing to delete can
  degrade to marking rather than to lying.
* **Where recovery lives.** `TripRecoveryService` is a plain class over `TripRepository`, wrapped in a
  keep-alive `tripRecoveryProvider` that `main.dart` reads once from the post-frame callback, before the
  auto-detection listener. It does **not** resume an interrupted recording: the sensor and GPS sessions
  are gone, and a trip stitched across an unknown gap would be worse than an honestly-closed one. It only
  closes the books — metrics recomputed from the route points that reached the database, `endTime` = the
  last point's timestamp (not "whenever the app was reopened"), `duration` = end − start because pauses
  are unknowable after the fact. That over-counts a ride with long stops, which is the safe direction: it
  keeps a real ride above the validity threshold instead of deleting it. Fewer than two points, or a span
  under the minimum, means delete.
* **Partial metrics are persisted.** Distance, max speed and the pause total lived only in memory, so
  recovery would have had nothing but the raw points. The existing 30 s flush timer now also writes them
  onto the `active` row (`_flushProgress`), which costs one extra UPDATE per flush — not one per point —
  and gives the recovery a floor to fall back on.

Not addressed here, deliberately: the end-of-trip notification still reports 0 m because `_stopRecording`
zeroes the in-memory metrics before `_stateMachine.stopTrip()` reads them (separate change in flight).
`AppConstants.minTripDurationSeconds` now holds the threshold `Trip.isValidTrip` used to hardcode; there
is intentionally **no** minimum-distance rule, since a slow ride is still a ride.


Gates after step 5: `flutter analyze` clean, **331/331 tests**. T029 and T033 closed in the tracker (T033's leftover — the CI format gate — is step 6's L-050; the T038/T039 dependency caveat L-053 is thereby resolved).

**Code-complete but pending on-device validation** (`tasks/T041-device-validation.md`): the entire step-4 cluster — GPS-stops-when-stationary, trip-survives-backgrounding, recording under OS suspension, ≤5 %/hr drain, notification behaviour. T041/T006/T013 stay ⏳ until it passes.

**Still open after steps 1–5 and 6a**: L-013 partially (T030 in progress: settings/history/detail screens uncovered); L-017's manual half (ASC app record, API key, first signing) and the new SPM permission-macro issue; the remaining release findings L-018, L-032…L-035, L-048, L-050, L-051 (step 6; L-049 closed in `1857040`); L-011's product half — `CyclingPatternDetector` is now fully tested but *still unwired*: `TripStartDetector` remains the live algorithm, and the detector cannot classify walking/driving until it gets a location source (maintainer decision: wire it or retire it); plus L-028 (manifest side), L-043, L-045 (TripMetrics), L-047, L-057.

**Decision (2026-09-01) — L-069: the stop notification is built from the saved trip, not from provider state.**
Two options were on the table: keep reading `tripRecorderServiceProvider` but reorder `_stopRecording` so
the reset happens after `stopTrip`, or pass the finalized data down. The reorder was rejected — it fixes
the zeroing but not the two other faults (the live metrics are a 1 s-granular ticker snapshot, not the
final computation that excludes pauses; and `whenData` still swallows everything on a loading/error
recorder) and it leaves the machine depending on the very provider that depends on it, an ordering hazard
one edit away from returning. Passing the `Trip` (rather than a `TripMetrics`) also lets
`trip_state_machine.dart` drop its `trip_recorder_service.dart` import entirely, so the notification now
reports exactly the row that reached the database. `finalTrip` is optional: the three call sites that stop
a trip from the *detecting* phase (the coordinator's failed-start and detection-timeout paths,
`AutoDetectionController.startTripManually`'s failure path) have no trip to report and take the
`detecting:` branch, which never notified; a `null` on the recorded branches degrades to "cancel the
foreground notification, announce nothing" instead of announcing zeros. Every stop of a *recorded* ride
still goes through `TripRecorderService.stopRecording()` — UI button, notification action, coordinator —
which is the only caller that can know the final metrics.


**Decision (2026-09-01) — L-070: the stop detector judges a window, and GPS outranks the sensors.**
The old `_isStationary` required, on a *single* 50 Hz sample, `|accel − g| ≤ 1.0 m/s²` **and**
`gyro ≤ 0.2 rad/s` **and** GPS speed `< 2.0` km/h (a literal). That is a description of a phone lying
on a table, not of a phone in a jersey pocket or a pannier: at a red light the carried device reads
0.1–0.5 rad/s on individual samples, so nearly every sample failed the test, the pause counter almost
never reached its three counted detections, "active" duration silently included every stop, and the
300 s auto-stop was unreachable in practice. Three changes, each deliberately narrow:

1. **Window, not sample.** A plain-Dart `StationaryWindow` (scratch state owned by the notifier, not
   part of `TripStopState`, so the UI-visible state is unchanged) keeps ~1.5 s of samples and exposes
   the accelerometer-magnitude **standard deviation** and the **mean** gyroscope magnitude. Std-dev
   rather than mean acceleration because the mean is gravity in every orientation, while the spread is
   exactly the road vibration that distinguishes rolling from standing. New thresholds
   `stationaryAccelerationStdDevMax = 0.8 m/s²` and `stationaryRotationAverageMax = 0.6 rad/s` sit
   between the two measured bands (standstill: std-dev < 0.5, gyro mean 0.1–0.5; rolling: std-dev > 1,
   gyro mean > 0.5). They are **new constants, not a relaxation of `stationaryAccelerationMax` /
   `stationaryRotationMax`**: those two keep their instantaneous meaning and their only remaining
   consumer, `MotionWindow.state`, which drives the coordinator's GPS gate. The gate's behaviour is
   therefore untouched by this change — deliberately, since it is a separate subject.
2. **A fresh fix outranks the sensors.** A fix younger than `stationaryGpsMaxAge` (10 s) reading
   ≥ `movingSpeedMinKmh` (6 km/h) means moving whatever the sensors say (phone wedged in a basket);
   one reading < `stationarySpeedMaxKmh` (3 km/h, replacing the 2.0 literal — a standstill GPS commonly
   reports 1–3 km/h of noise) means standing still with only the vibration criterion having to agree,
   because a pocketed phone rotates freely at a stop. In between, or with GPS missing or **stale**, the
   two windowed sensor criteria decide alone. Staleness matters: a stalled position stream must not
   keep asserting "0 km/h".
3. **No more zombie pause.** The movement hysteresis (`tripStopMovementHysteresisSamples`) exists so a
   single noisy reading cannot zero an accumulating pause, but while the trip was already *paused* it
   did the opposite of its intent: 3 counted non-stationary readings (~3 s) called `resetPause()`, while
   resuming needs 5 s of *uninterrupted* movement — so a rider nudging the bike every few seconds sat in
   a pause that could neither resume nor reach the 300 s auto-stop, with GPS and the foreground service
   up indefinitely. The detector now takes a `tripIsPaused` flag (passed only from the coordinator's
   `_analyzeForResume`) that disables the hysteresis reset: while paused, the pause clock only ever
   moves forward, and only a confirmed resume — which already calls `reset()` — clears it. The
   alternative, making the paused countdown a wall-clock delta from `pauseStartTime`, is what this
   effectively is, with one fewer piece of state to keep in sync. A paused trip is now guaranteed to end
   in a resume or a stop.

Also removed while in the area: `TripStateMachine.hasPauseTimedOut()` (no caller ever — `_evaluatePauseDuration`
owns that decision) and its test, plus `AppConstants.stationaryThresholdSeconds` (a TODO with no consumer;
`minPauseDurationSeconds = 30` remains the delay before a pause). Five scenario tests were added driving the
detector the way the coordinator does — several samples per second with injected timestamps: red light with a
pocketed phone (pauses at 30 s), steady riding (never pauses), calm phone in a basket at 15 km/h (never pauses),
paused with 2 s of movement every 10 s (auto-stops at 300 s), paused with 5 s of continuous movement (resumes).
On-device confirmation is item 9 of `tasks/T041-device-validation.md`.


**Decision (2026-09-01) — L-074: the watchdog counts silence, not staleness, and it lives in the coordinator.**
A trip could stay "active" for hours with the phone forgotten in a building: `locationStreamProvider`
re-subscribes forever with backoff (2 s → 30 s) and never signals defeat, and `TripStopDetector` treats a
fix older than `stationaryGpsMaxAge` (10 s) as *GPS absent* and falls back to the sensors — so any stray
gyroscope motion kept the ride alive. What was missing was not a better stop rule but an upper bound on
how long a recording may go with no positions at all. Choices made:

1. **Where.** In `TripDetectionCoordinator`, not in the location service or the recorder. The coordinator
   already owns the 1 Hz `_detectionTimer` and the GPS gate, and it is the only place that both sees
   every fix and can end a trip through the same path as an automatic stop (`_finalizeAndStopTrip` — so
   the end-of-trip notification, the L-068 sub-60 s deletion and the session restart all behave
   identically to a sensor-driven stop). The gate is pinned open for the whole recording, so "no fix"
   here provably means the OS is not delivering positions rather than that we stopped asking.
2. **What is measured.** Silence since the last *received* fix — not `LocationData.timestamp`, and not
   the fix's age. A position replayed from the plugin's cache, or one carrying a skewed device clock,
   still proves the stream is alive, which is the only property the watchdog cares about; the *quality*
   of a fix stays the stop detector's business (`stationaryGpsMaxAge`). While no fix has arrived at all,
   the clock runs from the start of the trip, which makes "a trip that never got a single fix" stoppable
   while giving the first fix a full `gpsLossStopTimeout` of grace.
3. **10 minutes.** It has to sit above every *recoverable* outage and below anything a user would call
   "stuck". The longest road tunnel a cyclist realistically rides is under 5 min, so 10 min leaves a 2x
   margin; the cost of waiting is bounded and cheap (the tail carries no route points anyway), while
   stopping too early loses the second half of a real ride. Note `maxPauseDurationSeconds` (5 min)
   already covers the case where the *sensors* also go quiet: this timeout only catches "motion
   continues, positions do not".
4. **Known gap, deliberately not closed.** The watchdog only supervises while a detection session runs,
   so a manual ride started with automatic detection *off* has no watchdog — exactly as it has no
   auto-pause and no auto-stop today. Giving the recorder its own watchdog would duplicate the stop
   path; the honest fix is the pre-existing question of whether a manual ride should start a coordinator
   session at all, which is out of scope here. Recorded as item 10 of `tasks/T041-device-validation.md`.

**Decision (2026-09-01) — L-074b: a finished trip resets the start detector.**
`_analyzeForTripStart` called `tripStartDetector.reset()` only when `startRecording` **threw**. On the
success path the streak survived the entire ride: after `_finalizeAndStopTrip` suspends and (100 ms later)
restarts listening, `TripStartState.consecutiveDetections` was still ≥ 3, so the very first sample scoring
≥ `tripStartConfidenceThreshold` within `tripStartDetectionWindowSeconds` of the last positive detection
started a *new* trip — the consecutive-detection rule, the whole defence against single-bump false starts
(L-022), applied to the first trip of a session only. Reset now happens on every stop path, and also
before `activateCooldown()` on the detection-timeout path (`reset()` returns the state to `initial()`, so
the two only compose in that order). `TripStopDetector.reset()` was symmetrically missing at trip
*start*: a new recording inherited whatever pause the previous one had accumulated. The scoring logic and
every threshold are untouched — this is purely about when the accumulators are cleared.

**Decision (2026-09-01) — L-074c: `stopRecording()` returns `null` instead of throwing, and an
unflushed buffer stays a documented risk.**
"Stop" arrives from three places — the tracking screen's button, the notification's Stop action and the
coordinator — and the first two race with the third and with themselves (a double tap, a notification
whose trip was auto-stopped a second earlier). The `StateError('No active trip to stop')` was already
meaningless to all of them: the notification path logged and swallowed it, the coordinator only reaches
it with a trip in flight, and the tracking screen let it escape into an *unhandled* async error. It is
now a warning log and a `null` return (`Future<Trip?>`; the existing test asserting `throwsStateError`
became one asserting a no-op). The route-point buffer is deliberately left as it is: if the final flush
fails all `routePointFlushMaxAttempts` times the points stay in memory, carry their own trip id and are
retried by the next `startRecording`, and are lost only if the process dies before then. Persisting them
elsewhere would mean a second write path with its own failure mode to guard a scenario — three
consecutive SQLite write failures *and* a process death — that is far rarer than the bug such a path
would introduce.


## Method

Six independent Opus dimension audits — **pipeline**, **architecture**, **quality-gates**, **platform**, **release**, **docs-tasks** — each followed by an adversarial verification pass that re-checked every claim against today's tree at file:line level and re-ran the gates. Every finding in this ledger carries verdict **confirmed**: no finding survived as merely plausible, and none was carried over from the prior audit without independent re-verification. Where a confirmed code defect is currently unreachable at runtime (because its consumer is itself dead code), the row is marked *confirmed (latent)*. Where closing a finding needs a physical device or a maintainer decision rather than more analysis, it is marked in the **Next actions** section, not in the verdict.

## Relation to the prior audit (2026-06-17)

Two documents from the June pass remain in the tree and were re-verified rather than assumed:

- `tasks/AUDIT-FINDINGS.md` — 42 findings; a fixed table (20 items) and a deferred cluster. **Still accurate.** Its quality-gate claim ("190 tests pass", analyze clean) reproduces exactly today, and every fix it records is still present and correct in the code.
- `tasks/BLOCKED-pipeline-refactor.md` — findings #2, #3, #4, #5, #7/#8, #11, the three architecture decisions they need, and a dependency order. **Every code-level assertion in it is still literally true 2.5 months later.** The document is not stale as a technical description; it is stale only as a *tracked work item* — nothing in `TASKS.md` or `CLAUDE.md` references it, and `TASKS.md` still reads `Blocked: 0`.

Nothing from the June pass regressed. Nothing from its deferred cluster was resolved.

---

## 1. Executive state summary

**Overall health**: the *surface* of this repo is in genuinely good shape — clean analyzer under a stricter-than-default lint set, 190 green tests with no flakes, perfect freezed/Riverpod conventions across all 12 model files, complete subscription/timer disposal, coherent platform declarations, a real Android release path, and a self-consistent legal/privacy artefact chain. The Flutter 3.47.2 / Dart 3.13 upgrade and 51 transitive bumps caused zero regressions.

**The core of the product does not run.** Underneath the green gates, the tracking engine that the app is named for has no entry point, its headline algorithms are dead code, and the task tracker says all of it is complete.

The five things that matter most:

1. **The shipped app cannot start a trip — automatically or manually.** `startListening()` is called only by the coordinator restarting itself; `startRecording()` has exactly one caller (that same coordinator); nothing in `lib/` constructs `tripDetectionCoordinatorProvider`. The tracking screen offers only pause/resume/stop, and the Active Trip tab is permanently disabled. There is no `Idle → Detecting → Active` path in the binary. This is finding #11 from June, and it is *broader* than that document states. (L-001)

2. **The June deferred cluster is unchanged, and the tracker hides it.** #2, #3, #4, #5, #7/#8, #11 are all present verbatim. Meanwhile `TASKS.md` marks T006 ("motion-gated GPS") and T013 ("automatic trip start detection") ✅ complete, contains no reference to either audit document, and reports `Blocked: 0`. A future session following the documented workflow ("check TASKS.md for the next pending task") cannot see any of this. (L-019, L-020)

3. **The documented cycling algorithm is not what runs, and nothing tests it.** `CyclingPatternDetector` — the 40/35/25 three-layer detector in CLAUDE.md and the README — has zero references anywhere in `lib/`, zero lines in `lcov.info`, and a 19-test file named after it that never imports it. What actually decides a trip start is an instantaneous single-sample accel+gyro fit with no frequency analysis. 17 providers in total are unreferenced, including the sole consumer of the background isolate's output. (L-011, L-012)

4. **Release readiness is asymmetric and premature.** Android is genuinely wired end-to-end (signing, fastlane, `publish_beta.sh` with guards, verified Play API auth, clean secret hygiene). iOS (T039) has **zero** in-repo work — no `ios/fastlane`, no export-compliance key, legacy signing identity, universal iPad targeting. CI never compiles either platform, so dependabot's AGP/Kotlin/Gradle bumps land unverified — a class of drift that already broke the release build once. And the release phase has overtaken its own declared test/quality gate: T029/T030/T031/T033 are all still ☐ while T038 lists T033 as a dependency. (L-017, L-018, L-027)

5. **The green gate measures a narrow and partly fictional surface.** Test count has not moved since June despite T036–T039 shipping. 87 of 137 `lib` files are never loaded by any test, including the entire presentation layer (zero `testWidgets` in the repo). Four test files (50 of 190 tests, 26%) are named for units they never import — `CyclingPatternDetector`, `DatabaseService`, `SensorService`, `PermissionHandlerService` — so their green ticks assert nothing about production code. The database tests validate a *duplicated* schema in a test helper, making prod/test DDL drift invisible. (L-013, L-014, L-015, L-026)

**Release readiness verdict**: **not ready for a public store release; arguably not ready for internal beta either.** The Android *mechanics* are ready. The *product* is not: a tester who installs the internal build can view history and settings, open a tracking screen whose map marker and re-center button are permanently inert, and never start a ride. Beyond that, `POST_NOTIFICATIONS` is declared but never requested at runtime, so on Android 13+ the notifications the whole background design depends on can be silently suppressed. The Play listing still lacks a feature graphic and screenshots (hard gate for production, not for internal), and the privacy/data-safety declarations were last verified against a pre-upgrade commit on a dead branch.

---

## 2. Per-dimension state

### 2.1 Pipeline

**Healthy.** Every fix from the June pass is still present and correct: gravity-relative stationary check (`trip_stop_detector.dart:93`), movement hysteresis (`:56-70`), peak-span cadence (`cycling_pattern_detector.dart:116-124`), weighted combined confidence (`activity_confidence.dart:60-63`), battery/GPS timer and subscription disposal, the coordinator `_disposed` guard and `startRecording` try/catch, the recorder's `onError` logging and 1 s metrics ticker, and the `keepAlive` database owner. Detector logic is internally consistent with `AppConstants` wherever it is actually used. `git log` since June shows only UI/release (T036–T039) and dependency work.

**Issues.** The entire deferred cluster is present verbatim. On top of it, three defects the June audit never recorded: the final route-point flush destroys the tail of a ride after logging that it failed to save it; the foreground location stream carries a 30 s `timeLimit` and is never re-subscribed after an error, so a trip can keep "recording" with a frozen distance for the rest of the ride; and the "consecutive detections" thresholds are evaluated per 50 Hz sample, so `tripStartMinConsecutiveDetections = 3` represents ~60 ms, not the ~5 s the neighbouring `tripStartDetectionWindowSeconds = 5` implies. A large block of `AppConstants` (12 sampled names, zero consumers) makes CLAUDE.md's "check AppConstants for all thresholds" advice actively misleading.

### 2.2 Architecture

**Healthy.** `flutter analyze` clean; all 12 freezed models follow the mandated `sealed class` → private ctor → factory → extension shape exactly; plain `Ref ref` everywhere with no generated-`Ref` types left; every `StreamSubscription` and `Timer` in `lib/` has a cancel path wired to `ref.onDispose`; the strict lint set (`cancel_subscriptions`, `close_sinks`, `sort_constructors_first`, …) passes clean; codegen is current with the upgraded toolchain.

**Issues.** All six direct generated-provider-function call sites remain, defeating overrides and spawning duplicate unmanaged 50 Hz sensor pipelines. This pass surfaced sharper failure modes than June recorded: `CurrentMotionState` calling another Notifier's `build()` runs two concurrent loops over one shared mutable buffer; `TripRecorderService` registers its teardown in a `build()` that also `ref.watch`es, so a dependency change silently kills an in-progress recording while `_activeTrip` stays non-null; and `HomeShell`'s single-child tab rendering makes the autoDispose session loss reachable by one tab tap. `locationServiceProvider` is never populated, so the tracking screen's map marker and re-center FAB are inert. `TripMetrics` is the lone model living in the data layer and imported by presentation.

### 2.3 Quality gates

**Healthy.** Gates are reproducible and fast (3 s plain, ~17 s with coverage, zero flakes across two runs). Generated files are gitignored (0 tracked, 44 on disk) and CI regenerates them with `--delete-conflicting-outputs` before analyzing, so June's critical stale-codegen incident is structurally prevented. CI pins Flutter 3.47.2 matching local, with concurrency cancellation. Where tests do reach production code they are substantive: `trip_stop_detector` 100% (32/32) with both June fixes as named regressions, `trip_start_detector` 91.7%, `trip_repository` 84.7%, `trip_state_machine` 74.1%, settings/platform models 100%.

**Issues.** The gate measures the wrong surface: 51.2% line coverage of which a slice is unreachable production code (`gps_controller` is covered only by its own test and referenced by nothing), four phantom test files, zero widget tests, 100% of the coordinator's decision routing (lines 46–256) and the recorder's entire location handler (306–431) uncovered — with the recorder tests visibly hitting the real geolocator and running only the `onError` arm. `analysis_options.yaml`'s `strong-mode` keys are inert on Dart 3, so the clean analyze is weaker than the config implies.

### 2.4 Platform

**Healthy.** Android declares the full required permission set with the background service correctly typed `foregroundServiceType="location"` and `exported="false"`; the `allowBackup="false"` hardening from June survives; `minSdk` 26 is pinned with a documented rationale. iOS carries all four location strings plus `NSMotionUsageDescription`, `UIBackgroundModes` location+fetch, and a privacy manifest whose `DeviceID` over-declaration has been removed. The privacy chain is coherent end to end — policy on GitHub Pages, `AppConstants` URLs, real in-app links, Play prominent-disclosure block, `data-safety.md`. Three earlier documented inconsistencies (OSM User-Agent, fictional privacy toggles, policy stub) are fixed in code.

**Issues.** The gap is functional rather than declarative: `POST_NOTIFICATIONS` is declared with a comment claiming it is requested during onboarding — it is not, anywhere. (iOS is fine: `DarwinInitializationSettings` prompts at initialize.) `ACTIVITY_RECOGNITION` is modelled in the permission layer and advertised in the README but undeclared in the manifest. The startup `PlatformConfigValidator` always prints "All configuration checks passed" and would print the same with an emptied manifest. Background-permission state is never re-read after the Android 11+ settings detour (no `AppLifecycleState` observer exists anywhere in `lib/`).

### 2.5 Release

**Healthy.** Dependency health is excellent — direct and dev dependencies all up to date, `json_annotation` correctly a direct dep, no lockfile diff, no git/path/`any` sources or overrides. Secret hygiene verified rather than assumed: nothing matching key/secret patterns has ever been committed on any ref, `android/.gitignore` covers the keystore artefacts, the Appfile reads the service account from `~/.secrets` with an env override, and `publish_beta.sh` refuses to build without `key.properties`. The Android path is real and guarded (clean-tree, keystore, bump-rollback).

**Issues.** iOS is at zero. CI compiles nothing. The Play listing lacks its required images. The version-controlled changelog is uploaded by no lane. `release_status: "draft"` is a one-time setting with no reminder, and leaving it produces silently successful runs that reach no tester. The release script's own comments name a Gradle/AGP pair the repo no longer uses, and its `git tag` has no existence guard, so the documented partial-failure recovery path aborts.

### 2.6 Docs & tasks

**Healthy.** All 13 paths in CLAUDE.md's Key Files table resolve; the three extracted skills exist; `docs/` is a small self-consistent legal site whose `_config.yml`, `index.md` and two legal documents agree with each other, with the README's privacy section, and with `store-metadata/data-safety.md`; CLAUDE.md's cycling thresholds/weights match `AppConstants` verbatim; the toolchain/target claims match `pubspec`, `Info.plist` and `build.gradle.kts`. `TASKS.md`'s summary block is internally consistent (25 done / 2 in-progress / 13 pending of 40, matching the actual markers).

**Issues.** The tracker is blind to the audit backlog and marks the broken pipeline complete. Per-task detail docs have drifted (T038 still "☐ Pending" after shipping; T037's checklist asks for an edit already made and cites a README version string that no longer exists). README advertises an ML/HAR product absent from `lib/`, contradicts itself in its own roadmap on the same page, claims a permission the app never declares, and documents a command (`flutter format .`) that hard-errors. CLAUDE.md's battery table is wrong in exactly the two rows a reader is least likely to check, and its mandated commit format is used by 0 of the last 30 commits.

---

## 3. Findings

All 66 findings below are **confirmed** — verified against today's tree. Overlapping findings across dimensions are merged into a single row; the *Dim* column lists every dimension that reported it.

### Critical

| ID | Dim | Area | Title | Verdict | Detail |
|---|---|---|---|---|---|
| L-001 | pipeline · arch · docs | `trip_detection_coordinator.dart` | No entry point at all — the app can never start a trip | Confirmed | `startListening()` is called only by the coordinator's own self-restart (:238, :256) and `startRecording()` only from :142; nothing in `lib/` starts the coordinator, and the tracking screen offers only pause/resume/stop, so no `Idle→Detecting→Active` path exists. |
| L-002 | arch · pipeline · gates | `data/services/` (6 sites) | Sensor/location consumed via generated provider *functions*, not `ref.watch` | Confirmed | `motionDataStream(ref)`/`locationStream(ref)`/`notifier.build()` at coordinator :51,:69, motion service :18, sensor service :46-47, recorder :283, gps_controller :33 — bypasses overrides (fakes cannot be injected) and opens a fresh unmanaged accel+gyro pair per call. |
| L-003 | arch | `motion_detection_service.dart:98` | `CurrentMotionState` runs a second `build()` loop over one shared mutable buffer | Confirmed (latent) | `ref.watch(motionDetectionServiceProvider.notifier).build()` starts a second `await for` on the same instance, both mutating `_buffer`, corrupting window spans; latent only because both extra consumers are themselves dead code. |

### High

| ID | Dim | Area | Title | Verdict | Detail |
|---|---|---|---|---|---|
| L-004 | pipeline · arch · gates · docs | `gps_controller.dart` | Motion-gated GPS is a no-op enum flipper with zero consumers (#3) | Confirmed | `_startGPS`/`_stopGPS` only assign `_gpsState` behind `FIXME(T006)`; `gpsControllerProvider` has no references in `lib/`; real GPS lifecycle is `locationStream()` subscribed unconditionally at high accuracy / 10 m. |
| L-005 | pipeline · arch | recorder / state machine / coordinator | Three session-owning providers are autoDispose while holding the live trip (#2) | Confirmed | All three are bare `@riverpod` with `_activeTrip`/`_routePointBuffer`/`_totalDistanceMeters` in instance fields; the recorder's only watcher is the tracking screen, and `HomeShell` renders one child, so a tab tap disposes an in-progress trip. |
| L-006 | pipeline · arch · gates | `adaptive_location_settings.dart` | Adaptive settings and power modes are computed but never applied (#4) | Confirmed | `adaptiveLocationSettingsProvider`'s only mention in `lib/` is a FIXME comment; every GPS subscription uses `kDefaultLocationSettings` and both sensor streams hardcode 50 Hz, so the per-mode table and the <5 %/hr target are unenforced. |
| L-007 | pipeline · arch | `background_location_service.dart` | Background isolate disconnected, fixed-interval, non-adaptive (#7/#8) | Confirmed | Polls `getCurrentPosition` on a hardcoded 30 s timer with no motion/battery gating and emits via `service.invoke('update')`; its only subscriber (`LocationTracking`) is itself unreferenced, and `start/stopBackgroundTracking` have no callers. |
| L-008 | pipeline | `trip_recorder_service.dart:210-242` | Final route-point flush discards the ride's tail after logging the failure | Confirmed | `_flushRoutePointBuffer` keeps the buffer "for retry" on failure, but `stopRecording` logs the error and then unconditionally `_routePointBuffer.clear()`s with no retry path — June's fix #9 made the loss loud, not survivable. |
| L-009 | pipeline | `location_service.dart:9-13` | 30 s `timeLimit` on the position stream, never re-subscribed after error | Confirmed | A tunnel, canyon or red light terminates the stream; the recorder's `onError` logs and returns while the 1 s ticker keeps advancing duration with frozen distance, and the coordinator's handler only nulls `_lastLocation`, degrading detection to motion-only for the rest of the run. |
| L-010 | arch | `trip_recorder_service.dart:97,106-110` | Teardown registered via `ref.onDispose` inside a `build()` that also `ref.watch`es | Confirmed (latent) | Riverpod fires `onDispose` on every recomputation, so a dependency change cancels the location subscription and both timers while `_activeTrip` survives — the trip looks active and records nothing; the permission-provider path is the plausible trigger. |
| L-011 | arch · pipeline · gates | `cycling_pattern_detector.dart` (+ its test) | The documented three-layer cycling detector is dead code *and* its test never imports it | Confirmed | `cyclingPatternDetectorProvider` has zero references in `lib/` or `test/` and 0 lines in `lcov.info`; its layer-3 `currentLocation` is declared and never assigned so `speedScore` is hardcoded 0.5; the 19 "CyclingPatternDetector" tests import only models. June's #23/#24 fixes live here, untested. |
| L-012 | arch | `lib/` provider graph | 17 providers have zero references anywhere | Confirmed | Includes `gPSController`, `locationTracking` (sole consumer of the isolate's output), `sensorService`, `accelerometer/gyroscopeStream`, all three settings providers and four trip-history query providers; three more are referenced only by the inert `adaptiveLocationSettingsProvider`. |
| L-013 | gates · arch | `test/` vs `lib/**/presentation` | Zero widget tests for the entire presentation layer | Confirmed | `grep -rl testWidgets test/` returns nothing; all 190 tests in 18 files are pure-Dart unit tests, while 42 presentation files (onboarding, settings, tracking, history, shared widgets) have no coverage at all — including the permission flow that gates all data collection. |
| L-014 | gates | `database_service.dart` | Production DB schema 0/31 covered; tests validate a duplicated schema | Confirmed | `database_service_test.dart` imports `test/helpers/test_database.dart`, which re-declares the trips/route_points DDL by hand; production `_onCreate`/`_onUpgrade` — the only migration path real users take — execute in no test, so prod/test DDL drift is invisible. |
| L-015 | gates | coordinator + recorder | Core decision logic is untested: coordinator 46–256 and recorder 306–431 uncovered | Confirmed | Coordinator at 14.3 % (15/105), recorder at 66.9 % with the entire `_handleLocationUpdate` + flush block uncovered; the recorder tests visibly reach the real geolocator and exercise only the `onError` arm. Root cause is L-002. Trip distance — the primary user-visible number — is asserted by nothing. |
| L-016 | platform | Android manifest / `notification_service.dart` | `POST_NOTIFICATIONS` declared but never requested at runtime | Confirmed | The manifest comment claims it is requested during onboarding; `NotificationService.requestPermissions()` has zero call sites and onboarding requests only the two location permissions, so on Android 13+ the foreground-service and trip notifications the background design depends on can be silently suppressed. |
| L-017 | release | `ios/` | T039 iOS release configuration entirely unimplemented | Confirmed | No `ios/fastlane`, no Gemfile, no `ITSAppUsesNonExemptEncryption` (every TestFlight build stalls on export compliance), `CFBundleDisplayName` still `Autoride`, `TARGETED_DEVICE_FAMILY = "1,2"`, retired `iPhone Developer` identity, no ipa/dSYM gitignore, and `publish_beta.sh` has an Android section only. |
| L-018 | release | `.github/workflows/ci.yml` | CI never compiles either platform, so Gradle-toolchain bumps merge unverified | Confirmed | The single ubuntu job ends at `flutter test`; dependabot's gradle ecosystem has already landed five AGP/Kotlin bumps (now AGP 9.3.2 / Kotlin 2.4.10 / Gradle 9.7.1), and this exact drift class already broke `flutter build appbundle --release` once during T038. **Closed by the tribly build alignment**: `ci.yml` now runs `build-android` (JDK 21 pinned, SDK platform 37 installed, heap capped for the runner) and `build-ios` (unsigned) after `analyze-and-test`. Neither signs nor uploads. |
| L-019 | docs | `TASKS.md`, `CLAUDE.md` | The audit backlog is invisible to the task tracker | Confirmed | Neither file mentions `AUDIT-FINDINGS.md` or `BLOCKED-pipeline-refactor.md`; `TASKS.md` reads `Blocked: 0` and no task carries ⚠️, so seven confirmed open defects and the three decisions they need have no slot in the documented workflow. |
| L-020 | docs | `TASKS.md:64,117` | T006 and T013 marked ✅ complete while the code they own is inert | Confirmed | "Battery-Optimized Location Strategy — motion-gated GPS" and "Automatic Trip Start Detection" are both ✅ although `gpsControllerProvider`, `tripDetectionCoordinatorProvider` and `AdaptiveLocationSettings` have no consumers; the file declares itself the single source of truth for progress. |
| L-021 | docs | `README.md` | Advertises an ML/HAR product that does not exist in the codebase | Confirmed | Features promise "ML-powered detection", "Adaptive learning", "Confidence scoring"; Tech Stack lists a "Custom HAR model"; FAQ claims ">90 % accuracy" — yet `tflite` is imported nowhere, no model asset exists, T016–T019 are all pending, and the README's own roadmap leaves the box unchecked on the same page. |

### Medium

| ID | Dim | Area | Title | Verdict | Detail |
|---|---|---|---|---|---|
| L-022 | pipeline | `trip_start_detector.dart`, `trip_stop_detector.dart` | Consecutive-detection and hysteresis thresholds are counted per 50 Hz sample | Confirmed | Every `MotionData` sample feeds the detectors, so `minConsecutiveDetections = 3` means ~60 ms, not the ~5 s the neighbouring window constant implies — a bump or hand movement can start a trip; the same arithmetic undercuts June's hysteresis fix, and `shouldResumeTrip` resumes on a single sample. |
| L-023 | pipeline | `motion_data.dart:172,178,222` | `MotionWindow.state` uses gravity-free literals on a gravity-inclusive magnitude | Confirmed | Bare `10.0`/`10.5`/`0.3` thresholds disagree with the fixed stop detector (`\|mag − 9.8\| ≤ 1.0`) and with `AppConstants`, so a resting phone at 10.1 m/s² is "stationary" to one half of the pipeline and "moving" to the other. |
| L-024 | pipeline | `app_constants.dart` | A large block of thresholds has zero consumers; `hasPauseTimedOut` is never called | Confirmed | 12 sampled constants unused, several contradicted by live values (`distanceFilter = 15` vs the 10 m actually used; `minConfidenceForDetection = 0.6` vs a hardcoded 0.6), making CLAUDE.md's "check AppConstants for all thresholds" misleading. |
| L-025 | arch | `trip_tracking_screen.dart` | `locationServiceProvider` is never populated — map marker and re-center are inert | Confirmed | `LocationService.build()` returns null and state is set only inside `getCurrentLocation`/`getLastKnownLocation`, neither of which is called anywhere in `lib/`; the screen binds `.value` for both the marker and the FAB. |
| L-026 | gates | sensor & permission tests | Two more test files never import the service they are named for | Confirmed | `sensor_service_test.dart` (0/37 lines on `SensorService`) and `permission_handler_service_test.dart` (file absent from lcov entirely); with L-011 and L-014 that is 4 of 18 files — 50 of 190 tests — asserting nothing about production code. |
| L-027 | gates · docs | `tasks/TASKS.md` Phase 8 | Test count flat at 190 since June while the release phase overtook its own gate | Confirmed | No commit has touched `test/` since 2026-06-17 despite T036 completing, T038 shipping and a major toolchain bump; T029/T030/T031/T033 are all ☐ while T038 (⏳, work shipped) declares T033 as a dependency. |
| L-028 | platform · docs | manifest vs permission layer & README | `ACTIVITY_RECOGNITION` modelled and advertised but never declared | Confirmed | `AppPermission.activityRecognition` has a display name, rationale and `permission_handler` mapping, and the README tells users to grant "Physical Activity" — the manifest declares no such permission, so a request would return denied with no dialog. |
| L-029 | platform | `platform_config_validator.dart` | Startup validator is a no-op that always reports success | Confirmed | Both platform validators return an empty issue list after printing hardcoded claims, so `printConfigStatus()` always prints "All configuration checks passed" — it would print identically with the manifest emptied, while L-016 goes unnoticed. |
| L-030 | platform | `permission_handler_service.dart:95-107` | Background-location status never re-checked after the Android 11+ settings detour | Confirmed | The service correctly opens app settings and returns the pre-detour status; onboarding treats that as final and advances, and no `AppLifecycleState`/`WidgetsBindingObserver` exists anywhere in `lib/`, so a user who *does* grant "Allow all the time" returns to an app that believes they refused. |
| L-031 | platform · release | `data_management_section.dart:118` | In-app version string hardcoded as `AutoRide v1.0.0 (build 1)` | Confirmed | True today only by coincidence; `publish_beta.sh` bumps the build number on every upload, so it goes stale from the first successful run — exactly when tester bug reports start arriving. `package_info_plus` is not a dependency. |
| L-032 | release | `android/fastlane/Fastfile` | The version-controlled Play changelog is uploaded by no automated lane | Confirmed | Both the `internal` and `metadata` lanes set `skip_upload_changelogs: true`; only the `deploy` lane (documented as called by no script) would push it, so internal testers see an empty "What's new". |
| L-033 | release | `fastlane/metadata/.../images/` | Play listing missing the feature graphic and all phone screenshots | Confirmed | Only `icon.png` exists; the in-repo README marks the 1024×500 graphic and ≥2 phone screenshots as missing. Not a blocker for internal testing, a hard gate for production, and the screenshots need a physical device — real lead time. |
| L-034 | platform · release | `store-metadata/data-safety.md` | The privacy source-of-truth was last verified against a pre-upgrade commit on a dead branch | Confirmed | Header says 2026-07-25 @ `cc1c088` (branch `wip`); since then Flutter 3.47.2 and 51 transitive bumps changed the native plugin set that drives Apple's ITMS-91053 required-reason check. Its §10 also still lists four already-fixed items, so a reader chases resolved work and misses L-016. |
| L-035 | release | `android/fastlane/Fastfile:16-18` | `release_status: "draft"` is a one-time setting with no reminder to flip it | Confirmed | Left as draft after the first upload, every subsequent `./publish_beta.sh` appears to succeed — consuming a build number, committing and tagging — while no internal tester ever receives the build. Failure is visible only in the Play Console. |
| L-036 | docs | `tasks/T038-android-release.md` | Detail doc still reads "Status: ☐ Pending" and describes the shipped work as broken | Confirmed | Its Overview still claims debug-keystore signing, no build number and no distribution mechanism — all three false since `a945fa3`. T036's doc correctly carries "✅ Complete", so the convention exists and only T038 broke it. |
| L-037 | docs | `tasks/TASKS.md:398` | "Last Updated: 2026-04-10" predates events recorded inside the same file | Confirmed | The file itself records T036 completing 2026-07-25 and the full T038 Play Console status written today; git says its last modification is 2026-08-31. The adjacent "in parallel with Phase 7 follow-ups" is also stale — Phase 7 is fully complete. |
| L-038 | docs | `CLAUDE.md` battery table | Wrong distance filters for Low and Critical power modes | Confirmed | Documented 20 m / 100 m; the code computes `distanceFilterMoving + 10` = 30 m and `distanceFilterStationary ~/ 2` = 50 m. Every other cell is right, so the table looks trustworthy and is wrong in the two rows least likely to be checked — and neither value is derivable from `AppConstants` by name. |
| L-039 | docs | `README.md`, `CLAUDE.md` | Documented commands fail or diverge from the CI that actually gates the repo | Confirmed | `flutter format .` no longer exists and hard-errors (README's Code Quality block); the single-file test example points at a path that does not exist; both files prescribe the legacy `flutter pub run build_runner` in five places while CI uses `dart run build_runner`. |
| L-040 | docs | `CLAUDE.md` vs git history | The mandated `T###:` commit format is used by 0 of the last 30 commits | Confirmed | The real convention is gitmoji + conventional commits with the task ID inside the subject (`🚀 feat(release): T038 …`), and README independently tells contributors to use conventional commits — so CLAUDE.md actively steers future sessions to break the established history style. |
| L-041 | docs | `tasks/TASKS.md` Phase 8 | Pending markers mis-describe reality in both directions | Confirmed | T029 (unit tests) and T033 (lint/analyze) are ☐ though 190 tests cover exactly T029's stated scope and the curated 20-rule lint set passes clean; meanwhile T030 is accurately ☐ — so the markers hide that the one genuinely missing layer is UI coverage for T022/T023/T024, all marked complete. |

### Low

| ID | Dim | Area | Title | Verdict | Detail |
|---|---|---|---|---|---|
| L-042 | gates · release | `analysis_options.yaml:14-16` | `strong-mode` keys are dead config on Dart 3 | Confirmed | `implicit-casts`/`implicit-dynamic` were removed from the analyzer and replaced by `language: strict-casts / strict-raw-types`; they are silently ignored, so the project's first mandatory gate is weaker than its config expresses. Cheap fix, may surface real issues. |
| L-043 | pipeline | `trip_recorder_service.dart:439` | Live `routePointCount` reports buffer occupancy, not points recorded | Confirmed | Sawtooths to zero on every flush; harmless only because no widget renders it today. |
| L-044 | arch | `lib/main.dart` | `HomeShell` mutates `_currentIndex` during `build()` | Confirmed | Assignment without `setState` makes build non-idempotent and can leave the NavigationBar's selected index disagreeing with the rendered body; the guard belongs in the tab handler or a `ref.listen`. |
| L-045 | arch | `trip_recorder_service.dart:18-70` | `TripMetrics` domain model lives in the data layer and is imported by presentation | Confirmed | Hand-written class with manual `copyWith` and formatting getters — the sole exception to the freezed/domain convention CLAUDE.md mandates, and two widgets import a data service purely to get the type. |
| L-046 | arch | `sensor_service.dart:79-80` | Stream merge silently swallows sensor errors | Confirmed | `listen(controller.add)` with no `onError`, so an accelerometer/gyroscope failure stops the merged stream without ever reaching the coordinator's error handler — detection goes quiet with no diagnostic. |
| L-047 | platform | iOS backup posture | Trip database still included in iCloud/device backups | Confirmed | Android sets `allowBackup="false"`; nothing on iOS sets `NSURLIsExcludedFromBackupKey`. Knowingly accepted and honestly disclosed in the privacy policy — a disclosed asymmetry, not a misrepresentation. |
| L-048 | release | `android/app/build.gradle.kts:65-71` | Release builds ship unminified and unobfuscated | Confirmed | `isMinifyEnabled`/`isShrinkResources` both false — a deliberate, well-argued T038 D6 deferral pending a physical-device smoke test; worth re-deciding before public release, not before internal beta. |
| L-049 | release | `publish_beta.sh` | Stale toolchain comments and a non-idempotent `git tag` | Confirmed | Comments name "Gradle 8.14 / AGP 9.3.0" against a 9.7.1 / 9.3.2 repo; `git tag "v$NEW_VERSION"` has no existence guard, so the documented keep-the-bump recovery re-run aborts *after* the upload. macOS-only by construction, so releasing is single-machine. |
| L-050 | release | `.github/workflows/ci.yml` | No formatting, coverage, or lockfile-integrity gate | Confirmed | No `dart format --set-exit-if-changed`, no coverage collection, and `flutter pub get` without `--enforce-lockfile` — with dependabot opening up to 5 pub PRs a week, lockfile enforcement is the cheap one to add. **Format gate closed** by the tribly build alignment: the 103-file backlog under `lib/`+`test/` was cleared in its own commit (`834451f`, listed in `.git-blame-ignore-revs`), and `check.sh` now runs `dart format --output=none --set-exit-if-changed lib test` ahead of analyze — so CI and `publish_beta.sh` both enforce it. **Still open**: coverage collection and `flutter pub get --enforce-lockfile`. |
| L-051 | release | `fastlane/Appfile` + `~/.secrets` | Play service account holds account-level Administrator across two apps | Confirmed | Correctly outside git and CI-overridable; the residual risk is blast radius — one leaked key publishes both Pedalons and AutoRide, and the scope exceeds what an internal-track upload needs. A per-app Release Manager account would shrink it. |
| L-052 | release · docs | `README.md` | Claims a closed beta that has never shipped | Confirmed | Tells users to ask for an internal-tester invite, but `git tag` is empty, pubspec is still `1.0.0+1`, and the Play Console prerequisites are listed as outstanding — step 1 of the README yields nothing today. |
| L-053 | docs | `TASKS.md`, T038/T039 docs | Release tasks declare a dependency on still-pending T033 | Confirmed | CLAUDE.md says "never start a task before its dependencies are complete" and TASKS.md repeats it; T038 (shipped) and T039 both list T033 (☐). Either the dependency is wrong or the rule is decorative — neither document acknowledges it. |
| L-054 | docs | `tasks/T037-privacy-policy.md` | Checklist stale: asks for an edit already made and cites a vanished version string | Confirmed | The DoD item "TASKS.md dependency changed from T034 to none" is unchecked though TASKS.md already says exactly that; §5.6's rationale for deferring the README Export claim quotes "Version: 0.1.0 (Early Development)", which the README no longer contains. Its genuinely open items are tracked accurately. |
| L-055 | docs | `README.md` roadmap | Checkboxes contradict the code in both directions | Confirmed | "Automatic trip detection" is checked though its coordinator has no live entry point; "Route visualization on maps" is unchecked though `flutter_map` ships and three map widgets are wired into the trip screens. |
| L-056 | docs | `CLAUDE.md` structure diagram | Lists empty `shared/` subdirectories and omits three live `core/` subtrees | Confirmed | `shared/models` and `shared/providers` hold no code; `core/permissions`, `core/platform` and `core/extensions` exist, are actively used, and are referenced elsewhere in CLAUDE.md but absent from the map a new session builds its mental model from. |

### Informational — including confirmed-healthy state

| ID | Dim | Area | Title | Verdict | Detail |
|---|---|---|---|---|---|
| L-057 | platform | Android manifest `<queries>` | No `<queries>` entry for web `ACTION_VIEW` despite `url_launcher` use | Confirmed | Works today because http/https browser visibility is automatic and the code does not call `canLaunchUrl`; adding such a gate or a non-http scheme would break the store-filed legal URLs silently on Android 11+. |
| L-058 | pipeline · arch · gates | repo-wide | Gates green and every June fix verified intact after the toolchain upgrade | Confirmed | `flutter analyze` clean, 190/190 tests, no deprecated-API fallout; gravity check, hysteresis, cadence span, weighted confidence, disposal fixes, `_disposed` guard, metrics ticker and keepAlive DB owner all still present and correct. |
| L-059 | gates | `ci.yml`, `.gitignore` | No stale build_runner output is possible — CI regenerates before every gate | Confirmed | 0 tracked `.g.dart`/`.freezed.dart` (44 on disk), CI runs `dart run build_runner build --delete-conflicting-outputs` on a pinned Flutter 3.47.2 before analyze and test. June's critical stale-codegen incident is structurally prevented. |
| L-060 | arch | `lib/` | Subscription and timer disposal is healthy across the codebase | Confirmed | Every `StreamSubscription` and `Timer` has a cancel path wired to `ref.onDispose` (or a `finally`); the only uncancelled `Timer.periodic` lives in the background isolate, torn down wholesale by `stopSelf()`. |
| L-061 | arch | `lib/` | Riverpod `Ref` typing, freezed conventions and codegen fully compliant | Confirmed | No generated `XxxRef` types remain; all 12 freezed files follow sealed-class → private ctor → factory → extension exactly; the strict lint set passes clean on the upgraded toolchain. |
| L-062 | gates | detectors / state machine / repository | Where tests reach production code, they are substantive | Confirmed | `trip_stop_detector` 100 % with both June fixes as named regressions plus realistic scenarios; `trip_start_detector` 91.7 %, `trip_repository` 84.7 % (incl. the batched IN-query test), `trip_state_machine` 74.1 %; no flakes, no skips. |
| L-063 | release | repo-wide git history | No secrets committed and no key material in history | Confirmed | Only `key.properties.example` (placeholders) is tracked; no `.jks`/`.keystore`/`.p8`/service-account JSON on any ref; `key.properties` and `local.properties` are ignored; `publish_beta.sh` refuses to build without the keystore. |
| L-064 | release | `pubspec.yaml` / `.lock` | Dependency health is good after the Flutter 3.47.2 upgrade | Confirmed | Direct and dev dependencies all up-to-date, only SDK-pinned transitives lag; `json_annotation` correctly direct; running the gates leaves the tree clean; all ordinary caret constraints, no overrides or git/path sources. |
| L-065 | docs | `docs/` | Legal site content is accurate and internally consistent | Confirmed | `_config.yml` (url + `/autoride` baseurl + relative-links), `index.md`, and the two legal documents agree with each other, with the README's privacy section and with `data-safety.md`; the README's published URLs match the configured base. No drift. |
| L-066 | docs | `tasks/AUDIT-FINDINGS.md`, `tasks/BLOCKED-pipeline-refactor.md` | Both prior-audit documents are still technically accurate | Confirmed | Their gate claims reproduce exactly and every code-level assertion re-verified true today, including the `#5 → #2 → #3 → #4/#11/#7/#8` dependency order. Their weakness is reachability, not accuracy — see L-019. |

---

## 4. Prior-audit reconciliation (2026-06-17 → 2026-08-31)

### 4.1 The blocked cluster — status: **all still open, none regressed**

| June # | Item | Status today | Ledger ID |
|---|---|---|---|
| #5 | Streams consumed via direct provider-function calls | **Still open**, unchanged; all six call sites verbatim. New: the shared-buffer double-loop mechanism (L-003) and the recorder's `onDispose`-in-`build` hazard (L-010) are sharper consequences than June recorded. | L-002 |
| #2 | Session state can be lost (autoDispose vs live trip) | **Still open**, unchanged; the only `keepAlive` in `lib/` remains `databaseProvider`. New: `HomeShell`'s single-child rendering makes the loss reachable by one tab tap. | L-005 |
| #3 | Motion-gated GPS is a no-op | **Still open**, unchanged; `FIXME(T006)` comments intact, `gpsControllerProvider` unreferenced. | L-004 |
| #4 | Adaptive battery settings inert | **Still open**, unchanged; only mention in `lib/` is a FIXME comment. | L-006 |
| #7/#8 | Background isolate disconnected and non-adaptive | **Still open**, unchanged. New: its only consumer (`locationTrackingProvider`) is itself unreferenced, so the isolate's output currently reaches *no* code at all. | L-007 |
| #11 | Automatic detection has no live entry point | **Still open and broader than documented** — not only is auto-detection unstarted, there is no manual start either, so no trip can begin by any route. | L-001 |
| #12/#13/#29 (partial) | Recorder/coordinator/isolate paths untestable | **Still open**; the coverage numbers now quantify it (coordinator 14.3 %, recorder's location handler wholly uncovered). | L-015 |

### 4.2 June's fixed table — status: **all 20 fixes verified intact**

Every entry in `AUDIT-FINDINGS.md`'s "Fixed in this pass" and "Completed in follow-up" tables was re-checked in situ and is still present and correct (#0, #1, #6, #9, #10, #14, #15, #16, #17, #18, #19, #21, #22, #23, #24, #26, #27, #28, plus the #12/#13/#29 test additions). The Flutter 3.47.2 / Dart 3.13 upgrade regressed none of them. **No regressions found.**

One nuance worth recording: fix #9 (loud logging on flush failure) is intact but does not achieve its intent — the final flush still discards the buffer (L-008). And fixes #23/#24 landed in `CyclingPatternDetector`, which no code path executes and no test loads (L-011), so they are correct but unexercised.

### 4.3 Net movement since June

- **Resolved**: nothing from the deferred cluster.
- **Still open**: 7 cluster items + both partial test items.
- **Regressed**: none.
- **Newly found**: 3 pipeline defects (L-008, L-009, L-022), 3 architecture failure modes (L-003, L-010, L-025), the whole quality-gate/phantom-coverage picture (L-011, L-013, L-014, L-026), the notification-permission gap (L-016), and the full release/docs dimensions, which the June audit did not cover at all.

---

## 5. Recommended next actions

Ordered. Steps 1–3 are cheap and unblock everything else; step 4 is the real work and needs a device.

**0 — Maintainer decisions (blocking, ~30 min of thinking).** `BLOCKED-pipeline-refactor.md` still asks for exactly three, unchanged and still correct: (a) what owns a trip session's lifetime (`keepAlive` on the three providers / a scoped `ref.keepAlive()` link / a single session-owner provider); (b) whether `GPSController` owns the position stream or is deleted in favour of gating inside the coordinator; (c) when auto-detection should start (app launch after permissions / a background-tracking setting / tied to the foreground service). Also confirm a physical Android device is available for validation. *Nothing below step 3 can be responsibly landed without these.*

**1 — Make the tracker tell the truth (docs, ~1 h).** ✅ *Done in `b84bc88` — see Remediation log.* Add a ⚠️ Blocked task — suggested **T041: Core tracking-pipeline refactor** — to `TASKS.md`, linking both audit documents and this ledger, and set `Blocked: 1`. Reopen T006 and T013 (or split their unfinished halves into T041). Fix the T038 detail-doc status, the `Last Updated` stamp and the Phase-10 wording. → L-019, L-020, L-036, L-037, L-041, L-053, L-054.

**2 — Correct the documentation that misleads the next session (docs, ~1–2 h).** ✅ *Done in `9fcfd6e` — see Remediation log.* Strip or clearly future-tag the README's ML/HAR claims, the ">90 % accuracy" FAQ line and the "Physical Activity" permission; fix the roadmap checkboxes and the closed-beta section; replace `flutter format .` and the dead test path; align the build_runner invocation with CI; fix CLAUDE.md's battery table, commit format and structure diagram. → L-021, L-028, L-038, L-039, L-040, L-052, L-055, L-056.

**3 — Bounded code fixes that need no device and no decision (~half a day).** ✅ *Done in `11e74b7` (except L-028's manifest side and the L-008 test — see Remediation log).* In rough value order: request `POST_NOTIFICATIONS` at runtime during onboarding (L-016); retry-or-persist the final route-point flush instead of clearing it (L-008); re-subscribe the location stream on error and reconsider the 30 s `timeLimit` (L-009); populate `locationServiceProvider` so the map marker and re-center work (L-025); reconcile `MotionWindow`'s literals with `AppConstants` (L-023); convert the per-sample detection counters to time- or window-based (L-022); forward `onError` in the sensor merge (L-046); move the `HomeShell` index guard out of `build` (L-044); re-read background-permission status on app resume (L-030); replace the `strong-mode` keys with `language: strict-casts/strict-raw-types` and fix whatever it surfaces (L-042); either make `PlatformConfigValidator` assert something real or delete it (L-029); wire `package_info_plus` into the About row (L-031). Then prune the dead constants and the 17 unreferenced providers, or annotate each with the task that will consume it (L-012, L-024).

**4 — The pipeline refactor, one step at a time with on-device validation (T041, depends on step 0).** ✅ *Code complete in `7afb833`/`529db42`/`da3ad62` per the four maintainer decisions of 2026-08-31 — on-device validation outstanding, see `tasks/T041-device-validation.md` and the Remediation log.* Follow the June dependency order, which is still correct: **#5** providerize the six stream call sites (unblocks injection and de-dups subscriptions) → **#2** implement the chosen session ownership → **#3** implement real motion-gated GPS → then **#4** adaptive settings, **#11** a real entry point (and a manual start control on the tracking screen), and **#7/#8** one source of truth for location. Validate after each step: GPS demonstrably stops when stationary, a trip survives backgrounding and a tab switch, background recording continues under OS suspension, drain ≤ ~5 %/hr. This closes L-001 through L-007, L-010 and L-011, and retires T006/T013/T032.

**5 — Rebuild the test surface around what actually ships (T029 recut, T030, T031).** ✅ *Done in `a3dd31c`/`99eae4c` (T030 partially — remaining screens tracked in TASKS.md) — see Remediation log.* Point `database_service_test` at the production `DatabaseService` and delete the duplicated DDL helper (L-014); rewrite or delete the three other phantom test files so a green tick means something (L-011, L-026); once step 4's #5 lands, add the coordinator-routing and recorder-distance/flush tests that overrides finally make possible (L-015); start T030 with the onboarding permission flow and the tracking screen (L-013). Then close T033 honestly or drop it as a dependency of T038/T039.

**6 — Release, after step 4 makes the app worth installing.** ⏳ *Largely done for iOS (rows 6a–6d: T039 shipped and proven with TestFlight builds 3–4, L-049 fixed, store surface cleared to 2 blockers). Still open from this step: L-018 (CI build job), L-050 (lockfile/format gate), L-032 (changelog lane), L-035 (release_status reminder), L-034 (data-safety re-stamp), L-033 (Play feature graphic + screenshots, now joined by the iOS screenshots), L-048 (R8), L-051 (service-account scope).* Add a build job to CI (APK/AAB, plus a macOS/Xcode job once T039 exists) so gradle bumps are verified (L-018); add `--enforce-lockfile` and `dart format --set-exit-if-changed` (L-050). Complete T038's manual Play Console items, un-skip the changelog upload, and set a reminder to flip `release_status` after the first upload (L-032, L-035). Fix `publish_beta.sh`'s stale comments and tag guard (L-049). Re-run `data-safety.md` §8 against `develop` and re-stamp it (L-034). Then **T039** as the single largest remaining release item (L-017), with the Play feature graphic and device-captured screenshots (L-033) in parallel since they have lead time. Re-decide R8 (L-048) and scope down the Play service account (L-051) before the public release, not before the internal one.
