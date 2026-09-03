# T048 — Trusting a GPS fix: a bad speed must not veto a real ride

Date opened: 2026-09-03. Status: ⏳ **implemented, awaiting the two device runs
of §5.** Owner findings: **L-087**, **L-088**, **L-089** (`tasks/LEDGER.md` §7).
Depends on T041 (the pipeline) and T043 (the log that decides it).

Diagnosis was complete and device-confirmed on two phones before any code was
written; §1–§3 are that diagnosis, unchanged. **§4 has since been corrected** by
a third log (the morning commute, with a Strava reference), **§8 records what
landed**, and **§9 records the defect in that first build** — a gap bound that
could not fire on Android — found by replaying the shipped code over the logs.
Nothing here is closed until §5's pair of runs has been done: the whole point of
this task is a trade-off that only a device can settle.

---

## 1. What happened

2026-09-03, 17:19→17:47 CEST, one 7.4 km ride, both phones in a pocket, both on
1.0.0+9, verbose log.

| | iPhone 14,3 | Pixel 6a |
|---|---|---|
| Trip recorded | 1, **3 min / ~1.3 km late** | **none** |
| Departure detected | 17:22:06 (back-dated 3 s / 0 m) | never |
| Real departure | ~17:19:00 (sensors `cycling`, positions moving) | same |
| Highest start confidence | crossed 0.7 once, on one fix | **0.586**, threshold 0.7 |
| Fixes reading `sp` 0 | 192 / 219 (88 %) | 40 / 40 (100 %) |
| Median fix accuracy | 23 m | 300 m |

The iPhone's ride is otherwise sound: 7 372 m, 24 min 27 s, three legitimate
pauses totalling 82 s, FIT export with 164 points, no error, background survival
with the screen off confirmed by an unbroken heartbeat series at 49.7 Hz.

## 2. Why — the arithmetic

`trip_start_detector.dart:151-169`:

```dart
if (location == null) {
  return motionScore;                        // up to 1.0
}
final speedScore = _getSpeedScore(location); // 0.0 when speedKmh < cyclingSpeedMin (8)
return motionScore * 0.6 + speedScore * 0.4; // ceiling 0.60
```

A fix present and reporting a speed below 8 km/h caps the confidence at **0.60**,
below the 0.7 threshold, no matter what the sensors report. §6 of the ledger
derived exactly this cap from the 2026-09-02 *walking* run, where suppressing a
start was the desired outcome and the cap read as useful damping. On a real ride
it is a veto.

The Pixel is the clean proof: motion score 0.586 / 0.6 — 98 % of the available
motion weight, the pedalling recognised perfectly — and a departure that was
**arithmetically impossible for 25 minutes**.

The asymmetry that follows is the part worth keeping in mind while fixing this:
**no fix scores higher than a bad fix.** The Pixel's only threshold crossing of
the whole day is at 17:52:55, bike already parked, one jolt (`mag` 17.3,
`gyr` 1.8) evaluated with `_lastLocation` null → `c` 0.754, a `detecting` window,
and a `dto {el:30, n:0}` thirty seconds later. The single crossing was a false
positive at a standstill, and it happened *because* the GPS was absent.

## 3. Scope — three fixes

### 3.1 Derive speed from consecutive positions (L-087)

When `LocationData.speed` is 0 or invalid, compute it from the previous fix
(distance / Δt) instead of trusting it. `location_data.dart:26` copies
`position.speed` straight through with no fallback; iOS delivered 0 on 88 % of
the fixes of a 19 km/h ride.

Sanity of the idea on this log: 17:21:56 → 17:22:03 is 61 m in 7 s = 31 km/h,
available three minutes before the trip actually started, on fixes that were
already in the pre-trip buffer.

Applies to the start confidence **and** to the pre-trip buffer's riding-tail cut,
which is why the back-date recovered 3 s instead of 1.3 km: the cut looks for the
first buffered fix at or above `cyclingSpeedMin`, and all 14 buffered fixes read
0.

### 3.2 An unusable fix must be treated as no fix, not as zero speed (L-088)

A fix whose accuracy exceeds `rpAcc` (50 m) carries no speed information worth a
veto. In `_calculateStartConfidence` it should take the `location == null` path
rather than contribute `speedScore` 0.

On the Pixel, 30 of the 40 fixes of the ride exceeded 50 m, 29 of them on the
round values 100/200/300/500/600/700/800 m — the fused provider's cell/wifi
ladder. With this rule the ride would have been evaluated motion-only and
detected.

Note that `rpAcc` is currently the *route-point* filter; reusing it here is a
proposal, not an established constant. The threshold that matters is "accurate
enough for its speed to be believed", and it may not be the same number.

### 3.3 Apply the 10 s freshness rule on the start path too (L-089)

`AppConstants.stationaryGpsMaxAge` (10 s) is applied only by
`trip_stop_detector.dart:279`. The coordinator hands `_lastLocation` to
`analyzeForTripStart` at any age (`trip_detection_coordinator.dart:847`); the
field is cleared only when the gate closes or GPS errors.

On the Pixel, with fixes 30.7 s apart, **80 % of the 1 942 evaluations that
carried a fix were scored against one older than 10 s**, mean age 33.6 s.

3.2 and 3.3 are the accuracy arm and the age arm of one question — "is this fix
fit to vote?" — and should land as **one predicate in one place**, not two
conditions in two files. They are listed separately because they were found
separately and because each closes a different half of the evidence.

## 4. What was checked, so it need not be re-derived

**The three fixes compose; they are not one per phone.** This section first
said the opposite — "neither phone is saved by the other's fix" — reasoning from
the two evening logs alone, which was all that existed when it was written:

- **iPhone**: 22 of the 25 fixes of the three lost minutes were within 50 m *and*
  fresh (mean age 4.1 s, 7 % stale). Good fixes that simply reported no speed, so
  3.2 and 3.3 change nothing there. Only 3.1 saves the iPhone. *(Still true.)*
- **Pixel, evening**: the positions walk backwards (47.2185/-1.5977 at 17:36:36 →
  47.2141/-1.5870 at 17:37:07 → 47.2185/-1.5977 at 17:37:37), far too noisy to
  derive a speed from. *(Still true — of that ride.)*

**The morning commute of the same day corrects the conclusion.** Its GPS was
excellent (19 fixes at 14–43 m, a median 11 m from the Strava track, clocks
agreeing to +1.5 s) and `sp` was still 0 on all 23 — see the reframed L-088.
Replayed over it, **16 consecutive pairs of accurate fixes out of 16 yield a
derived speed in the cycling band**, 15.2 to 31.8 km/h against Strava's own 12.7
to 34 at the same points. So 3.1 does save the Pixel, on any ride where the
receiver works.

What the evening ride actually shows is that the **order** matters, not that the
fixes are device-specific. Derivation alone would still have been vetoed there:
the network fixes interleaved among the good ones produce 93.5, 121.3 and
124.2 km/h — above `cycMax`, hence `speedScore` 0 again. The accuracy arm alone
puts every evaluation on the motion-only path L-079 describes as broken.
Accuracy first, derivation on what survives: 16 of 16.

**Ordering against L-079.** Ledger §6 sequenced the freshness gap *behind* L-079
(the single-sample fit) on the grounds that removing a stale fix pushes 100 % of
evaluations onto the motion-only path, which L-079 describes as broken. That
reasoning stands for L-083 (the GPS gate). It no longer holds as stated here:
§6 assumed the cap only ever suppressed *false* starts, and the 2026-09-03 run
shows it suppressing a genuine ride. The trade-off is two-sided.

T048 therefore goes ahead of L-079 — **and inherits its risk in full.** Every one
of the three fixes moves evaluations onto the motion-only path, which is the path
that scored a jolt at a standstill 0.754.

## 5. Acceptance

Both runs, not one:

1. **The 2026-09-02 shopping run repeated** (walking + transport, no bike):
   zero trips in History, zero `active` rows, and the `trip discard` lines with
   `n: 0` counted (the open half of L-081).
2. **This ride repeated**: exactly one trip on each phone, starting within one
   minute of the real departure, and the back-date placing the start at the first
   fix genuinely at riding speed (T041 item 11).

Run 1 alone would pass by doing nothing. Run 2 alone would pass by deleting the
speed layer. Only the pair shows whether a missed ride was traded for a false
one.

Both runs at `lvl: verbose`, on a build **after** the T047 throttle — the
1.0.0+9 logs that produced this task emitted `win` and `stop` every 20 ms
(81 047 + 72 876 lines in 41 minutes on the iPhone), which is L-085 and already
fixed on `develop`.

## 6. Out of scope

- **L-079** — the single-sample cycling fit, and the dead three-layer detector
  behind it (L-011). T048 makes the motion-only path matter more; it does not
  make it better. This is the reason T048 must not be read as closing T044.
- **L-083** — the GPS gate a carried phone keeps open. Unchanged by this task,
  and still sequenced behind L-079 for the reason §6 gives.
- **Why the Pixel's GNSS never engaged** (L-088's cause, as opposed to its
  handling). Whether Android was asked for the right accuracy, or the receiver
  simply never got a cold-start lock, is a separate investigation:
  `adaptive_location_settings.dart` and the `LocationAccuracy` actually requested
  in `normal` power mode. T048 only ensures such a fix cannot cast the deciding
  vote. Worth doing, because a ride recorded from 300 m network fixes would be
  worthless even once it is detected.
- **The `win`/`stop` flood** — L-085, closed by T047, present in these logs only
  because the phones ran 1.0.0+9.

## 7. Loose end found on the way

`autoride-audit-20260903-1759.ndjson.gz`, 11:13:28, Pixel:

```
err TripRecorderService "Failed to delete discarded trip 8"
    TripRepositoryException: Trip not found: 8
    trip_repository.dart:332 ← trip_recorder_service.dart:435
```

A discarded recording tries to delete a row that was never written. Harmless
here — the session restarted normally on the next line — but the discard path
gained importance with T044's L-081 half, which now deletes rather than saves,
so it should tolerate an absent row instead of throwing. Not part of T048's
scope; recorded so it is not lost.

---

## 8. What landed (2026-09-03)

All three fixes, plus the two log fields that make the next pair of runs
readable. `./check.sh` green: 701 tests, `flutter analyze` clean.

### The pieces

| Where | What |
|---|---|
| `app_constants.dart` | `speedTrustMaxAccuracyMeters` (50 m) and `speedTrustMaxAge` (= `stationaryGpsMaxAge`, 10 s) — the two arms of §3.2/§3.3; `derivedSpeedMinGap` (1 s) and `derivedSpeedMaxGap` (30 s) for §3.1 |
| `location_data.dart` | `hasReportedSpeed` — a 0 is the *absence* of a measurement, not a measurement of standstill; `speedIsTrustworthyAt(now)` — the single predicate §3 asked for, both arms in one place |
| `gps_speed_estimator.dart` (new) | §3.1. Plain Dart, like `PreTripLocationBuffer`, owned by the coordinator |
| `trip_start_detector.dart` | `_calculateStartConfidence` takes the motion-only path when the fix is present but unfit, instead of scoring it `speedScore` 0 |
| `trip_detection_coordinator.dart` | Refines every fix at ingestion, before `_lastLocation` and the buffer see it; resets the estimator when the gate closes or GPS errors; passes its injected clock to `analyzeForTripStart` so the age arm is testable |

### The two decisions §3 left open

**The accuracy threshold is its own constant, not `rpAcc`.** §3.2 flagged that
reusing the route-point filter was a proposal. `speedTrustMaxAccuracyMeters`
starts at the same 50 m — the Pixel's ladder sits at 100 m and above, so the two
values are indistinguishable on the evidence available — but it answers "is this
speed worth believing?" where `rpAcc` answers "is this point worth drawing?".
They can now move apart when a run says one of them should.

**Deriving happens at ingestion, not in the detector.** §3.1 requires the derived
speed in two places (the confidence *and* the riding-tail cut), and the iPhone's
failure is exactly what applying it to one of them looks like: the departure was
detected and still back-dated by 3 s instead of 1.3 km. One correction, applied
once, before anything reads the fix. The stop detector consequently sees it too
— a mid-ride `sp` 0 no longer reads as evidence of a standstill, which is the
same defect seen from the pause side.

The estimator refuses far more often than it derives: both fixes accurate,
1–30 s apart, displaced further than their own accuracy, and the quotient below
`maxCyclingSpeedKmh`. The Pixel's backwards-walking 300 m fixes produce nothing,
which is the intended answer — §4 says only §3.2/§3.3 can save that phone.

### Reading the next logs

Two new fields, because the acceptance runs have to be judged on the arithmetic
and not on the outcome:

- `fix.dsp` (m/s) — present only where a speed was derived. `count(dsp)/count(fix)`
  is how much of the run's speed evidence the provider failed to supply (88 % on
  the 2026-09-03 iPhone).
- `start.vt` — whether the fix was allowed to vote. `c` is motion-only when it is
  false, weighted when it is true. Without it, a post-T048 log cannot be told
  from a pre-T048 one by inspection.

`k.spAcc`, `k.spAge`, `k.dspMin`, `k.dspMax` travel in the header.
`.claude/skills/autoride-audit-log/SKILL.md` is updated for all six.

### What is still open

§5, unchanged and unweakened. Every one of these fixes moves evaluations onto
the motion-only path, which is the path that scored a jolt at a standstill 0.754
— the unit tests pin the arithmetic (a walk with an untrusted fix still does not
start a trip), but a unit test cannot answer whether a real pocket, on a real
bus, produces cycling-shaped motion for three seconds. Only the 2026-09-02
shopping run repeated can.

---

## 9. Correction the same evening — the bound could not fire on Android (L-090)

Found by replaying the shipped estimator over the two Pixel logs rather than by
reading it again. `derivedSpeedMaxGap` was a fixed **30 s**, against an
`AppConstants.locationUpdateNormal` of exactly **30 s**. `intervalDuration` is a
request the OS serves with jitter, so every Android gap lands just above it —
30.7 and 30.8 s in these files — and the estimator derived a speed **0 times
across both Pixel rides**. Fourteen pairs of the morning commute, accurate to
14–43 m and a median 11 m from the Strava track, were refused for **0.7
seconds**. The other modes are further above a 30 s bound still: 40, 60, 90.

§3.1 was therefore, as first shipped, an **iOS-only fix by accident** — iOS
ignores `intervalDuration` and delivers on the distance filter, 6–15 s apart,
which is why the same replay derives 7 speeds in the iPhone's three lost minutes
and 97 during its trip.

The unit test pinning `maxGap + 1` passed throughout. It encoded the bound
faithfully; the bound was the defect. That is the kind of error a unit test
cannot reach, and the reason §5 is written the way it is.

**Fix**: the bound is scaled from the interval the power mode itself requests —
`PowerModeConfig.derivedSpeedMaxGap` = `locationUpdateInterval ×
AppConstants.derivedSpeedMaxGapFactor` (1.5) — which is what makes it a bound
rather than a coincidence. A regression test asserts, for all four modes, that
the bound clears the mode's own interval, and reproduces the Pixel's 187 m / 31 s
pair. The header carries `k.dspFac` in place of `k.dspMax`, since the effective
value is now `pwr.ui × k.dspFac`; the audit-log skill gained a trap saying so,
because a run with no `dsp` at all has to be read as a finding rather than as a
healthy provider. `./check.sh` green: **702 tests**, analyze clean.

**After the fix**, re-replayed: the Pixel morning ride derives **14 speeds, 14 of
14 in the cycling band**; the evening ride still derives essentially nothing
(1 — the accuracy arm keeps the cell ladder out, as intended); the iPhone is
unchanged at 7 and 97.

### What the replay settles in advance, and what it cannot

Replaying the whole start decision — motion score recomputed from each `start`
line's `mag`/`gyr`, threshold 0.7, one detection per second, three inside five —
over the Pixel's morning commute (real ride 08:27:17 → 08:46:42):

| | departure |
|---|---|
| before T048 (every present fix votes) | **none** — 0 of 1 302 evaluations reach 0.7 |
| T048 as first shipped (fixed 30 s bound) | 08:31:48, 68 crossings — derived speed contributing nothing |
| T048 with the scaled bound | **08:31:05**, 95 crossings |

T048 turns "never detected" into "detected", which is the point. The corrected
bound buys 43 seconds and 27 more crossings on this particular ride — a smaller
gain than L-090's headline, because on Android the *freshness* arm is what does
the work (fixes 31 s apart against a 10 s bound leave the motion-only path in
force ~68 % of the time). It matters more than 43 seconds suggests: without a
derived speed no buffered Android fix ever reaches `cycMin`, so the riding-tail
cut has nothing to find and the back-date stays at 0 on that platform for ever.

**The four-minute lateness belongs to L-079, not to T048.** Mean `mag` over the
commute is 10.49 m/s² against a cycling band centred on 15
(`cyclingAccelerationMin`/`Max` = 10/20), giving `accelScore` ≈ 0.10 — a phone in
a pocket on a bike lives near 1 g, and the band was calibrated for something
else. The threshold is crossed only on outlying samples.

**And the phantom survives**: replayed over 08:48–08:56, the walk after arrival
still fires at **08:52:52**. §5 is unchanged and unweakened by any of this — a
replay can show that a real ride is now caught, it cannot show what a bus does to
a pocket. That is still the 2026-09-02 shopping run's job.
