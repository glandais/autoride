# T051 — A car shakes like a bicycle: the drive that was recorded as a ride

Date opened: 2026-09-07. Status: ⏳ **the three changes are written and green (794 tests);
the device run is outstanding.**
Owner findings: **L-100**, **L-101** (`tasks/LEDGER.md` §10).
Depends on T050, whose fix it completes and whose calibration it corrects.
Fourth in the line T048 → T049 → T050 → T051, and the first one that is not about
the detector being wrong.

---

## 1. What happened

2026-09-07, the rider drove to the shops. One verbose log,
`autoride-audit-20260907-1337.ndjson.gz`, iPhone 14,3, **1.0.0+13** — the first
build carrying T050, launched at 11:12:48.

**T050 works, and this run says so twice.** Ninety-three minutes of a phone
lying still produced 4 370 evaluations with a median `asd` of **0.01** and
**zero false starts**; the departure was confirmed **three seconds** after the
first shaken second, `pre: 0`, no `bdate` — there was nothing to back-date.
§9's defect is closed.

**And the trip is a car**: `trip {a:"stop", id:14}` — 3 137 m, 1 629 s,
`avg` 6.9 km/h, `max` 39.3, `n` 74, `net` 16 m, `act: "cycling"`.

---

## 2. Why nothing could refuse it

**2.1 Not the motion (L-100).** Replaying the T050 score over the `win`
statistics of this drive and of the 2026-09-06 ride:

| | mean motion score | windows ≥ `k.conf` | std(\|a\|) p50/p75 | mean\|gyro\| p50/p75 |
|---|---|---|---|---|
| the ride | 0.331 | 23.0 % | 0.81 / 2.33 | 0.51 / 1.35 |
| the drive | 0.298 | 22.6 % | 0.81 / 2.15 | 0.27 / 1.25 |

A car with a phone in it shakes like a bicycle with a phone on it. **No
accelerometer threshold refuses one without refusing the other**, and this is
measured, not argued.

**2.2 Not the speed, because nothing was listening.** The one axis that *does*
separate them was in the log the whole time:

| | measured fixes (`sp > 0`) | max | longest run > 30 km/h |
|---|---|---|---|
| the ride | 11 | 31.6 | 1 |
| the drive | 37 | 39.3 | **11** |

The GPS said "car" from **+243 s** — 57.0, 54.5, 51.4, 55.0, 49.3 km/h. Nothing
in the app reads a speed after the start decision: `cyclingSpeedMax` (40) only
feeds `speedScore` while *evaluating a start*, and `maxCyclingSpeedKmh` (60)
only rejects route points, which a 57 km/h peak passes under.

**2.3 Not the discard rule.** All three arms passed: it lasted 27 minutes, it
had 74 points, and it went somewhere.

**2.4 And it could not have been refused at the start.** At 12:45:58 the car was
stationary. Only a rule that runs *during* the ride can decide this.

---

## 3. What shipped

### 3.1 A vehicle veto, on measured speed only (L-100)

`VehicleSpeedWatch` — plain Dart, owned by `TripRecorderService`, fed from every
fix the recording sees (not only the ones kept as route points: how fast a fix
says the phone was going is independent of whether the point is worth keeping).
One statistic, two arms:

* **live** — four of the last six pieces of evidence at or above
  `vehicleSpeedKmh` (35), spanning at least `vehicleSustainSeconds` (5 s). Ends
  the ride there and then. On this drive it fires at **+339 s**, on the fourth
  of 38.0 / 38.0 / 37.9 / 39.3 — five and a half minutes into a twenty-seven
  minute recording.
* **end of ride** — four fast fixes *and* at least `vehicleSpeedMinShare` (25 %)
  of the evidence. Catches a drive whose bursts arrived too far apart for the
  rolling window. This drive: 10 of 37.

`Trip.discardReason` gains a fourth arm, `vehicle`, between `pts` and `still`.

**Only provider-measured speeds are evidence, and that is the load-bearing
decision.** Every reading above 40 km/h during the *bicycle* ride is a `dsp`
derived from a fix accurate to 23–38 m — 55.7, 54.6, 52.4 km/h on a night ride
that averaged 16.8. A watch fed those would throw real rides away on GPS noise,
which is worse than recording a drive. The recorder subscribes to
`locationStreamProvider` directly, so what it sees *is* the provider's own
number; `GpsSpeedEstimator` lives in the coordinator's ingestion path and never
touches it. **If that ever changes, this rule silently starts eating
inferences** — that is the one invariant to protect here.

The span is measured on the fixes' **own** timestamps, unlike
`PreTripLocationBuffer`, which ages by reception time so a replayed cache cannot
evict a window. The question is different: over what period were these speeds
*measured*. A fix carrying a measured speed and an accuracy under
`speedTrustMaxAccuracyMeters` is a real GNSS fix, and a burst served from a
cache shares old timestamps, which shrinks the span and is refused.

### 3.2 A longer cooldown after a vehicle discard

`vehicleCooldownPeriodSeconds` (300) against the false start's 30. A car's
motion *is* a bicycle's, so the detector starts again within seconds of the veto
and would keep doing so for the length of the drive — a string of discarded
trips, each with its own "trip started" notification.

`TripStartState` now carries the armed period, so one mechanism serves both, and
the coordinator asks the recorder for the reason (`lastDiscardReason`) rather
than re-deriving it: `vehicle` and `still` leave no trace in a `Trip`'s own
fields, unlike `dur`.

### 3.3 The calibration correction (L-101)

T050 set the ramps from the 1 Hz `sens` series — a series of *instants*, which
overstates the spread within a second by roughly 2×. The true 50 Hz figures:

| | std(\|a\|) | mean \|gyro\| |
|---|---|---|
| phone lying still, 93 min (median / p99) | 0.01 / 0.34 | 0.005 / 0.23 |
| a real ride (median / p75 / p90) | 0.81 / 2.33 / 5.34 | 0.51 / 1.35 / 1.76 |

So the published justification was wrong even though the numbers landed well.
Re-derived on the true scale, the shipped values are the **best of the
candidates** — false starts across 93 minutes of a phone at rest, against the
share of a real ride's windows clearing the threshold:

| asd min/ideal | gav min/ideal | false starts | ride windows ≥ 0.7 |
|---|---|---|---|
| **2.0 / 3.0** | **0.4 / 0.9** | **0** | **23.0 %** |
| 1.2 / 2.0 | 0.3 / 0.7 | 2 | 36.0 % |
| 0.8 / 1.5 | 0.25 / 0.6 | 3 | 42.5 % |
| 0.4 / 1.0 | 0.15 / 0.4 | 3 | 54.1 % |

Loosening buys coverage a ride does not need — one three-second streak starts
it, and 12:45:58 took three seconds — and pays in exactly the currency T049 was
opened over. **Values unchanged; the reasoning replaced**, because the wrong
reasoning would otherwise be re-used on the next log.

### 3.4 The log says which

New event `veh`: `a: "fire"`, `spk` the measured speed that tipped it, `lim` the
threshold, `n` fast fixes of `m` measured ones. At most one per recording (the
watch latches), always followed by `trip {a:"discard", why:"vehicle"}` — a
`vehicle` discard with no `veh` above it was the end-of-ride arm.

`trip` endings carry `vfx`/`vmf` — fast and measured fixes — on **every** ending
rather than only on a vehicle discard: a ride that was *nearly* refused is the
one worth seeing before the threshold is next moved. The six thresholds travel
in the header's `k` (`vehKmh`, `vehWin`, `vehMin`, `vehSec`, `vehShare`,
`vehCool`).

---

## 4. What the tests settle, and what they cannot

Green: 794 tests (was 782). The two real traces are pinned verbatim in
`vehicle_speed_watch_test.dart` — if a threshold moves, that test says which of
the two rides moved with it.

Pinned:

- the drive fires the live arm, at the fourth fast fix rather than at the end;
- the night ride does not, on either arm;
- a fix with no measured speed is not evidence *either way* (counting those as
  slow would let a drive through every rule that reads a share);
- a coarse fix is not evidence however fast it claims to be;
- four fast fixes 200 ms apart do not fire the live arm;
- one artefact in a long ride is not a vehicle;
- at the recorder: the drive ends four fixes after it reaches speed, and a ride
  whose provider reports no speed is kept;
- at the coordinator: a `vehicle` discard arms `vehicleCooldownPeriodSeconds`, a
  false start still arms the default.

**Not settled: whether a real ride ever trips it.** No ride on 1.0.0+13 exists.
There is no threshold on this axis that separates a town car from a fast
cyclist; 35 km/h sits between *this* drive and *this* ride, and one of each is
what the evidence amounts to.

---

## 5. Acceptance

Still T048 §5 / T049 §5's two runs — T051 adds a second thing run 2 must show.

1. **An ordinary indoor hour.** Pass: zero trips. (The 93 minutes of 2026-09-07
   are a strong signal but not this run: the phone was lying still, not being
   carried around a kitchen.)
2. **A real ride.** Pass: **one trip within a minute of the real departure, and
   no `veh` line in it.** Read `vfx`/`vmf` on the ending even when it passes: a
   ride that ends with `vfx` 2 or 3 is one descent away from being thrown out,
   and that is the signal to move `vehicleSpeedKmh` before it costs a ride.

A third run would settle it faster and is worth doing if a car is to hand: **a
drive**, pass is `veh {a:"fire"}` followed by `trip {a:"discard", why:"vehicle"}`
and `cool {a:"arm", why:"vehicle"}`, with no more than a couple of discarded
trips for the whole drive.

---

## 6. Cross-references

- **T050 is confirmed by this run, not weakened by it.** Zero false starts in
  93 minutes and a three-second departure are the two things §9 could not
  settle. L-101 corrects how its thresholds were justified, not what they are.
- **L-098's trade-off is visible here**: `vt` is absent throughout the departure
  window (`sp: 0`), so the score was motion-only as designed — and the veto T050
  removed would have had nothing to veto with, the car being stationary at
  12:45:58.
- **L-099 was not exercised** (`pre: 0`, no `bdate`), which is what §9 predicted
  for its own fix: with a detector that fires on time there is nothing to
  back-date.
- **L-011** — a frequency layer is the one thing that *might* separate a car
  from a bicycle on motion alone (a bicycle has a pedalling cadence; a car does
  not). This run is the strongest argument yet for wiring
  `CyclingPatternDetector`, and the weakest possible argument for doing it
  inside T051, where it would make the device run unreadable.
