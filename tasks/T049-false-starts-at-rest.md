# T049 — Three gestures are not a ride: false starts while standing still

Date opened: 2026-09-03. Status: ⏳ **the four fixes are written and green (772 tests);
the two device runs of §5 are outstanding.** What shipped, and the two open choices §3 left,
are recorded in ledger §8 → *Remediation*; the §5 sequencing decision was taken and is in
ledger §6.
Owner findings: **L-093**, **L-094**, **L-095**, **L-096** (`tasks/LEDGER.md` §8).
Depends on T041 (the pipeline) and T043 (the log that decides it).
Sibling of **T048**, which it inverts: T048 is the ride that could not start,
T049 is the kitchen that did.

**Read T048 §5 before touching anything here.** Every fix below tightens the
start path, and T048's own acceptance is still outstanding on two device runs
that need it *loose*. Sequencing the two is the first decision of §5.

---

## 1. What happened

2026-09-03, 19:38→21:27 CEST, 109 minutes. Both phones on 1.0.0+10 at verbose,
lying in the kitchen. **The rider cooked a meal and did nothing else.** The only
correct outcome is zero trips on each phone.

| | Pixel 6a / Android 17 | iPhone 14,3 / iOS 26.6.1 |
|---|---|---|
| Log | `autoride-audit-20260903-2125.ndjson.gz` (104 796 lines) | `autoride-audit-20260903-2127.ndjson.gz` (93 556 lines) |
| False starts | **4** | **6** |
| Discarded | 0 | 6 (`dist` 0, `n` 0) |
| **Persisted as cycling trips** | **2** | 0 |
| GPS gate open | — | **42.8 min of 109 (39 %)** |

The Pixel saved two rides that never happened: **183 m over 930 s (avg 0.71 m/s
= 2.5 km/h)** and **68 m over 617 s (1.4 km/h)**, both `act: "cycling"`.

The difference between the two phones is not detection quality — both detectors
fired, at the same instants, on the same arithmetic. It is that the iPhone
happened to receive no fix at all during its false trips, so the L-074 watchdog
discarded them for having nothing in them. The Pixel received drift, and drift
looks like distance. **The iPhone passes this run by accident, and a run it
passes by accident is not a pass.**

The rider's own report — *« heure très souvent bleue »* — is §2.4, and it is
this task's most legible symptom.

---

## 2. Why

### 2.1 The detection window slides, so the streak is not consecutive (L-093)

`tripStartMinConsecutiveDetections` (3) is documented, at
`trip_start_detector.dart:28`, as meaning "seconds of sustained cycling". It
does not. `lastDetectionTime = now` is reassigned on **every positive
detection** (`trip_start_detector.dart:97`), and `isWithinDetectionWindow`
compares with `.inSeconds <= 5` — integer truncation, so the real bound is
5.99 s. The window therefore *slides forward on each hit* instead of bracketing
a fixed interval, and a low-confidence sample only resets the streak once the
window has fully expired.

The requirement is not "3 detections in a row", nor even "3 detections in 5
seconds". It is **3 detections each within 6 s of the previous one** — up to
18 s of wall clock, with any number of near-zero samples in between.

Every one of the ten false starts is that signature. The clearest is Pixel
trip 3, where five consecutive sub-threshold seconds leave the streak untouched:

```
21:33:22  c=0.834  n=2      ← mag 14.3, gyr 1.98
21:33:23  c=0.203  n=2
21:33:24  c=0      n=2
21:33:25  c=0      n=2
21:33:26  c=0.273  n=2
21:33:27  c=0.156  n=2
21:33:27  c=0.803  n=3  go  ← 5.35 s after n=2. Streak never reset.
```

iPhone trip 4 is the same shape with a 4.68 s gap. Measured across the ten
starts, the intervals between the streak's own positive detections run **1.03 s
to 5.35 s**, mean 2.1 s. Three firm gestures inside twelve seconds of cooking
are enough.

### 2.2 The speed layer never votes (L-088, confirmed at rest)

`vt: false` on **100 %** of evaluations, on both phones. Every fix carries
`sp: 0` (29/29 on the Pixel), and `dsp` is derived only 5 times in 109 minutes —
the fixes are 30 to 120 s apart, beyond `pwr.ui × dspFac`.

So `c` is **motion-only on every single evaluation of this run**, the `wSpd`
weight (0.4) is inert, and a 0.7 threshold is being crossed by wrist movement:
`mag` 12.8–16.2 m/s², `gyr` 1.4–2.0 rad/s against a standing baseline of
9.82 / 0.005.

This is L-088 unchanged — Pixel `Position.speed` is always 0 — now observed
with the rider stationary rather than riding. It matters here because T048's
whole remedy moves *more* evaluations onto the motion-only path. **The motion
path is now the only path, and it is the one that produces false starts.** That
is the tension §5 has to resolve, and it is why T048 and T049 cannot be judged
apart.

### 2.3 GPS drift becomes distance (L-094)

`maxLocationAccuracyMeters` (50) admits fixes whose own uncertainty is 19–35 m,
while `minRoutePointDistanceMeters` (15) is the threshold that turns a fix into
a route point (`trip_recorder_service.dart:706` and `:722`). A fix accurate to
±30 m therefore clears a 15 m gate **mechanically**, on noise alone.

The nine points of the 183 m "ride" all sit inside a ~40 m square around the
house (47.22965–47.22988, −1.61437 −1.61387):

```
rp keep d=18.2  ac=33.5     18 m "travelled", 33 m of uncertainty
rp keep d=62.8  ac=28.7
rp keep d=117.6 ac=35.1
rp keep d=182.9 ac=19.3
```

Nothing compares the displacement to the confidence in it. The two constants are
independent today, and one is three times the other in the wrong direction.

### 2.4 The blue indicator is the cost of §2.1, not a gate defect

The iPhone held the GPS gate open **42.8 of 109 minutes**. The breakdown says
where it went:

```
0.7 min   close: inactivityTimeout   ← the gate working correctly
0.8 min   close: inactivityTimeout
0.6 min   close: inactivityTimeout
0.9 min   close: inactivityTimeout
0.8 min   close: inactivityTimeout
12.8 min  close: session   ┐
8.7 min   close: session   │  the five false trips: 39.0 min of continuous GNSS,
6.4 min   close: session   │  no inactivity close, because a trip was active
5.5 min   close: session   │
5.6 min   close: session   ┘
```

A trip legitimately holds the gate open — that is the design, and it is not in
question. The finding is arithmetic: **the gate is behaving correctly and still
costs 39 minutes of GNSS, because it is being told a ride is in progress.**
Fixing §2.1 removes 91 % of the open time on this run without touching the gate.

Battery is **not** measurable here and must not be quoted: iPhone 55 % → 50 %
over the period is a single 5 % step of iOS's own resolution, and the log ran
verbose. T041 item 4 is unaffected by this run.

### 2.5 A ride is kept without ever looking at how fast it went (L-095)

`Trip.isRideWorthKeeping` (`trip.dart:172`) is:

```dart
duration >= AppConstants.minTripDurationSeconds &&      // 60
routePointCount >= AppConstants.minTripRoutePoints;     // 2
```

Duration and point count, nothing else. The two Pixel trips clear both (930 s /
9 points, 617 s / 4 points) and are written to the database as cycling. Neither
average speed nor net displacement is consulted, though `cyclingSpeedMinKmh` (8)
exists and both trips average under 2.6 km/h. A 183 m trip whose start and end
are 20 m apart is kept because it lasted a quarter of an hour.

This is the last line of defence, and on this run it was the only one that could
still have fired. It did not.

### 2.6 The `stop` throttle does not cover a repeated `pauseTrip` (L-096)

**32.3 `stop` lines per second** where `evalMs` is 1000: 88 208 lines on the
Pixel (83 % of the file), 77 401 on the iPhone (83 %), all of them `pauseTrip`.

`_emitStopEval` (`trip_detection_coordinator.dart:1119`) exempts from the
throttle any decision that is not `continueTrip`:

```dart
if (throttled &&
    decision == StopDecision.continueTrip &&   // ← the hole
    stationary == _lastStopEvalStationary &&
    movement == _lastStopEvalMovement) {
  return;
}
```

The reasoning in the docstring above it is sound for an *active* trip, where a
non-continue decision is a transition worth keeping. But once the trip is
**paused**, the repeated decision is `pauseTrip`, never `continueTrip`, so the
exemption lets every motion sample through at 50 Hz for as long as the pause
lasts. L-085 closed this class for the active case and left the paused one.

Counts: Pixel 1 693 `continueTrip` / **88 208 `pauseTrip`** / 1 `stopTrip`;
iPhone 881 / **77 401** / 4.

---

## 3. Scope

Five fixes. §3.1 is the one that matters; §3.2 and §3.3 are the defences that
should have caught it and did not; §3.4 makes the log readable and §3.5 —
added from a later export of the same session — is the race §3.4's throttle
was hiding.

### 3.1 Bracket the detection window instead of sliding it (L-093)

The streak must mean what its name and its docstring already claim. Two
candidate shapes, and §5 has to pick one on evidence rather than taste:

- **Fixed window** — stamp the window's start on the *first* detection of a
  streak and never move it; the streak dies when `now - windowStart` exceeds
  `tripStartDetectionWindowSeconds`, whatever happened inside.
- **True consecutiveness** — reset `consecutiveDetections` on the first
  evaluation interval that scores below threshold, making the window redundant
  for this purpose.

The second is stricter and matches the docstring exactly ("seconds of sustained
cycling"); the first tolerates one dropped sample mid-pedal-stroke. **The second
is the recommendation**, because the run that motivates T048 shows real cycling
producing *sustained* confidence and the false starts producing isolated spikes
— the discriminant is continuity, not peak height.

Fix the truncation either way: `.inSeconds <= 5` must become a `Duration`
comparison, or the 5 s window silently means 6.

### 3.2 A displacement must beat its own uncertainty (L-094)

Reject a route point whose distance from the previous one does not exceed the
accuracy of the fix producing it. The `dist` drop reason gains a sibling, or
takes a qualifier — the audit line must say which of the two bounds rejected the
point, otherwise the next log cannot tell a stationary rider from a coarse one.

`maxLocationAccuracyMeters` (50) and `minRoutePointDistanceMeters` (15) both
stay as they are; the point is that neither is meaningful without the other.

### 3.3 Keep a ride only if it went somewhere (L-095)

Extend `isRideWorthKeeping` with a movement test. Candidates, to be settled in
§5: average speed against a floor derived from `cyclingSpeedMinKmh`, net
displacement (start to end) against a multiple of the median fix accuracy, or
both. Average speed alone would discard a legitimate ride with a long pause —
`avg` is computed over `dur`, and T048's own commute had 82 s of stops — so a
net-displacement arm is likely the safer of the two.

Whatever lands, `trip {a:"discard"}` must carry the reason, the way `n` was
added for L-081. A discard the log cannot explain is a bug report nobody can
answer.

### 3.5 One decision, one ending (L-097)

Found after the fact, in a log exported an hour later on the same session, and
it is §3.4's other half. The throttle was the *line*; this is the evaluation
underneath it.

Pixel trip 4, 21:31:03: three `pauseTrip` decisions 17 ms apart, then **two**
`stopTrip` at `.265` and `.281`, each running the whole teardown —

```
21:31:03.265  trip discard id=4 dur=124 n=1
21:31:03.282  trip discard id=4 dur=124 n=1     ← the same ride, again
21:31:03.296  err  Failed to delete discarded trip 4
                   TripRepositoryException: Trip not found: 4
```

`stopRecording`'s only guard is `_activeTrip == null`, and `_activeTrip` is
cleared at the *end* of `_stopRecording` — after the final flush, the audit line
and the delete. Every caller arriving in that window passes the check. This is
**L-080 exactly, on the other end of the ride**.

Benign on a discarded trip; on a kept one the second pass writes `updateTrip`
twice, emits a second `trip stop` and calls `TripStateMachine.stopTrip` again —
a second "trip recorded" notification for one ride.

Claim the ending synchronously, before the first `await`, at **both** levels:
the coordinator (so the ending stays one decision — one detector reset, one
session restart) and the recorder (which the Stop button and the notification
action reach without going through the coordinator).

### 3.4 Throttle a repeated decision, not just `continueTrip` (L-096)

Key the exemption on the *previous* decision rather than on a hardcoded one:
keep the line when `decision != _lastStopEvalDecision`, or when either counter
moved. A transition stays visible; a decision repeating 50 times a second does
not. Same treatment for `_emitResumeEval` if the same hole exists there —
check, do not assume.

Cheap, isolated, and it makes every subsequent log of this task readable.

---

## 4. What was checked, so it need not be re-derived

- **The four Pixel starts and six iPhone starts are all §2.1**, not a mix of
  causes. Every `start` line with `n >= 2` was extracted from both logs; the
  intervals between the streak's positive detections are 1.03–5.35 s in all ten
  cases, and no start has three detections in three consecutive seconds.
- **No `pwr` event in either log**, so the power mode in force during the run is
  unknown and `pwr.ui` could not be checked against the fix cadence. That is why
  §2.2 states the `dsp` scarcity as a fix-spacing observation rather than a
  bound violation — do not read it as L-090 regressing.
- **The Pixel's trip 1 was not lost.** It has no `trip stop`/`discard` line
  because the process restarted under it; `TripRecoveryService` finalised it on
  the next launch (`Deleted interrupted trip 1: 0 point(s), 0s — below the
  minimum`). Recovery worked. The gap is that a recovery deletion emits a `log`
  line and no `trip` event, so a reader counting trips in the log misses it —
  noted, not scoped here.
- **`fgs {a:"start"}` present on both** (`plat: android` / `plat: ios`),
  `perm {k:"background"}` with `alw: true, acc: precise` on both, no `err` line
  in either file, heartbeats unbroken. Nothing in this run is a permissions or a
  survival failure, and T046's keepAlive cycle is visible working across both
  gate closes of the idle period.
- **The iPhone's zero-distance discards are the L-074 watchdog**, firing at
  `el: 600` with `ref: lastFix` — correct behaviour on a trip with no fixes, and
  the reason the iPhone's failure is invisible in the trip list.
- **Two `cool {a:"arm", why:"falseStart"}`** on the iPhone (trips 4 and 5, both
  31–32 s). The cooldown works and is doing its job; it is armed by the
  *duration* floor, so it never sees the Pixel's 930 s false trip. L-081's
  reading is unchanged.

---

## 5. Acceptance

**Two runs, on a build carrying all four fixes, at verbose:**

1. **This run repeated** — an hour of ordinary indoor activity, phone on a
   counter, cooking or equivalent. Pass is **zero trips started on both
   phones**. Also record the gate-open fraction: it should fall to the five
   short `inactivityTimeout` cycles, i.e. under 5 % of wall clock, and that
   number is the answer to the blue indicator.
2. **A real ride** — pass is **one trip per phone, starting within a minute of
   the real departure**, with the route points matching a parallel Strava
   recording.

Run 1 alone passes by refusing to start anything. Run 2 alone passes by
reverting to today's behaviour. **Neither is evidence without the other**, which
is the same trap T048 §5 sets out and the reason the two tasks share a device
session.

**Sequencing decision — taken 2026-09-03: one build, both tasks.** T048 is already shipped in
1.0.0+10, so separate builds would have meant reverting shipped code rather than sequencing it,
and run 2 below already *is* T048's ride run while run 1 already *is* its control run. The
attribution traded away, and how to recover it from a failed run 2, is in ledger §6. The
original framing follows.

**Sequencing decision, to be taken before any code is written:** T048's
acceptance is outstanding and its fixes loosen the start path; T049's tighten
it. Running them on separate builds costs two device sessions and tells us which
change owns which outcome. Running them together costs one session and confounds
them. The recommendation is **one build, both tasks, both runs** — because
run 2 already exercises T048's acceptance in full and run 1 is the control run
T048 §5 asks for — but that is a trade of attribution for time, and it is the
rider's call, not the code's. Record the choice in ledger §6's decision
paragraph either way.

---

## 6. Out of scope

- **L-088's cause** — why Android's `Position.speed` is always 0. T048 owns it,
  and this run adds evidence, not a remedy.
- **L-079 and the single-sample fit.** `cyclingAccelerationMin/Max` (10/20)
  centred on 15 m/s² is why a hand gesture scores as well as pedalling, and it
  is the deeper reason §2.1's window can be exploited at all. Narrowing the
  streak makes false starts rarer without making the fit better. L-079 stays
  where it is, ahead of L-083, and T049 does not pre-empt it.
- **`CyclingPatternDetector`** (L-011), still unwired. A frequency layer would
  separate cooking from pedalling on its own, which is exactly why it is not a
  fix to be smuggled in under a false-positive task.
- **Battery.** Not measurable from this run (§2.4). T041 item 4 unaffected.
- **The recovery-deletion audit gap** (§4). Real, one line, unassigned.
