# T055 — The phone already knows: journal the OS activity classifier

Date opened: 2026-10-11. Status: ⏳ **step 1 written** (journal only, iOS and Android), device run
outstanding. Nothing reads the new lines.
Depends on T043 (the audit log it writes into) and T046 (the iOS session that keeps the process
alive to receive the updates).

**Read T053 §12 and T054 §6 first.** Speed cannot separate a bicycle from a car, the start fit was
never meant to, and the plan has been the inertial unit ever since. This task notices that both
platforms already ship an inertial classifier — CoreMotion's `CMMotionActivity` and Play services'
Activity Recognition — and starts recording what it says. It does not let it decide anything.

---

## 1. What prompted it

`autoride-audit-20261009-1827.ndjson.gz` — 2026-10-03 18:50 → 10-09 18:27, iPhone 14,3,
iOS 27.0.1, **1.0.0+19**, verbose — cross-referenced against a `WhereIWas` export from the same
phone, which records CoreMotion's activity stream (33 178 `motion.activity` events over the same
six days).

| | |
|---|---|
| Trips started | **97** (351 `idle→detecting`) |
| Kept | **21** |
| Discarded | 74 — 33 `pts`, 26 `still`, 15 `dur` — 8.7 h of recording, against 12.1 h kept |

Reading each recording against the CoreMotion activity inside it:

| CoreMotion says | Kept trips | |
|---|---|---|
| **cycling** (≥ 8 updates each) | 537, 546, 560, 562, 567, 581, 584, 585, 598, 599, 609, 611 | the 12 real rides |
| **automotive** (67 and 75 updates, 3 and 0 cycling) | **550**, **552** | two town drives — 550 carries the T053 badge, **552 does not** (25/191 fast fixes) |
| **walking**, nearly nothing else | 541, 545, 561, 571, 572, 589, 591 | seven walks, avg 1.8–2.9 km/h, kept by `net` ≥ 100 m |

No discarded recording held a real ride (the most cycling any of them saw was 4 updates, on 529).
So on this corpus the OS classifier separates every case the pipeline gets wrong — and the two
kinds of error it gets wrong are exactly the ones T053 (speed) and T054 §6 (motion fit) say it
cannot fix.

Its limit is latency: CoreMotion first said `cycling` **30 s to 8 min after** AutoRide's own start
(median 3 min; the outlier is the night trip 609, whose first `cycling` came 79 min in), and its last
`cycling` typically came 6–12 min before AutoRide's ending. It cannot start a
trip. It may be able to confirm one.

The T054 replay was re-run on the same log the same day: duty cycles still cut false starts by
36–40 % for 12/12 rides, and **every rule starts all seven walks and both drives** — no start
corroboration touches this half of the problem.

## 2. What was written (step 1)

**Journal only.** The activity becomes an `act` line and goes nowhere else.

| Piece | File |
|---|---|
| iOS — `CMMotionActivityManager.startActivityUpdates`, normalised to the shared vocabulary | `ios/Runner/AutoRideActivityRecognition.swift`, registered in `AppDelegate.swift` |
| Android — `ActivityRecognitionClient.requestActivityUpdates` (10 s) → manifest receiver | `android/…/ActivityRecognitionChannel.kt`, `ActivityRecognitionReceiver.kt`, `MainActivity.kt` |
| Dart session: start/stop with automatic detection, dedupe, journal | `lib/features/trip_detection/data/services/activity_recognition_session.dart` |
| Wiring — beside `IosBackgroundSession.arm()/disarm()` | `auto_detection_controller.dart` `_applyAutomatic` |
| Permission row — the only place that prompts | Settings → Diagnostic log → *Recognised activity* (`audit_log_section.dart`) |
| Permission mapping — iOS `sensors` (= Motion & Fitness), Android `activityRecognition` | `permission_handler_service.dart` |
| Constant `activityRecognitionInterval` (10 s, Android only), in the header as `k.actMs` | `app_constants.dart`, `audit_schema.dart` |
| Event `act` | `audit_event.dart`; reading guide in the `autoride-audit-log` skill |

Decisions taken, and why:

- **Never prompts from the session.** A session can start from a background relaunch (T046); a
  Motion & Fitness prompt there is either invisible or absurd. The session journals
  `act {a:"start", st:"notDetermined"}` instead, and the settings row asks.
- **Runs with automatic detection, whatever the log level.** The classifier runs on the motion
  coprocessor (iOS) or inside Play services (Android); step 3 will need it with the log off, and
  a lifecycle tied to the log would have to be rewritten then. With the log off, nothing is stored.
- **One vocabulary for both platforms.** `k` ∈ bike|car|run|walk|foot|still|tilt|unknown; iOS
  raises several flags at once (car + still at a red light), so the primary is picked by priority
  (bike > car > run > walk > still > unknown) and the rest travel in `o`. Android's percentage is
  banded into iOS's low/medium/high (≥ 75 / ≥ 50) and kept raw in `pc`.
- **Dedupe in Dart on (`k`, `cf`, `o`).** Android reports every interval whether anything changed.
- **Manual trips with automatic detection off are not covered.** The session follows the
  detection lifecycle, not the recorder's.

Not changed: no detector, discard rule, badge or threshold reads `act`.

## 3. What comes next

**Step 2 — a device run on each platform.** Pass:
- iOS: the settings row prompts once, then `act {a:"start", st:"granted"}` on every session start,
  `upd` lines during a ride (`k:"bike"` within minutes), none of them before the grant.
- Android: the same, with `pc` present and updates roughly every 10 s while moving, and **silence
  while still** — Play services stops reporting, which must not be read as a dead subscription.
- Both: no `act {a:"fail"}`. On Android, check the Play Console pre-launch report does not flag the
  receiver.

**Step 3 — decide what the classifier may do, on logs that carry it.** Candidates, cheapest first:
1. **A badge**, like the T053 vehicle flag: "walking" / "in a vehicle" on a kept trip. No risk.
2. **A confirmation**: a recording stays pending until the OS says `bike`, then becomes a trip
   back-dated to its start. This would remove phantoms, walks and drives in one move — and it
   touches the T053 rule (evidence may label, never silently discard). Measure first: how many
   real rides never get a `bike` verdict, on which platform, and how late it comes.

Do not decide step 3 on the single corpus in §1.

## 4. Release consequences

- iOS: the Motion & Fitness prompt now exists for real; `NSMotionUsageDescription` rewritten to
  say what it is for. No required-reason API involved.
- Android: `ACTIVITY_RECOGNITION` declared and requested — the Play listing's promise (R-11) is
  now true, and the permission model R-35 called dead has a caller.
- Privacy policy §2.4/§2.5/§4/§10 updated (2026-10-11). The activity stays on the device unless
  the user exports the diagnostic log, so the Data safety answers do not change; `data-safety.md`
  records the new row.
