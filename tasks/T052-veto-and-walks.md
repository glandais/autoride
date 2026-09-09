# T052 — A descent is not a car, and a walk is not a ride

Date opened: 2026-09-09. Status: ⏳ **the three changes are written and green (806 tests); the
device run is outstanding.**
Owner findings: **L-102**, **L-103**, **L-104**, **L-105** (`tasks/LEDGER.md` §11).
Depends on T051, whose live arm this corrects, and on T050, which it does not touch.
Fifth in the line T048 → T049 → T050 → T051 → T052.

---

## 1. What happened

2026-09-09, two bicycle commutes on **1.0.0+14** — the first build carrying T051 — and a working
day between them. Two verbose logs, `autoride-audit-20260909-0928.ndjson.gz` and
`-1802.ndjson.gz` (the second contains the first), iPhone 14,3 / iOS 26.6.1, schema 3. All times
local (CEST).

**Most of the build works.** The evening commute is a single clean recording — 8 803 m, 26.8 min
moving, `avg` 19.7, `max` 28.1, 159 points, one pause, an automatic stop on `maxPause`,
`vfx: 0 / vmf: 38`. T050's departure took four seconds. T048 back-dated three starts. The
GPS-loss watchdog fired once and was right.

**Two things are wrong, and §10 predicted one of them by name.**

1. The morning commute was **cut in two** and its first 1 561 m deleted, because a descent at
   39.9 km/h tripped the vehicle veto.
2. **Thirteen** false starts filled the working day, and **two of them are in History as cycling
   rides** — 545 m at 6.5 km/h and 219 m at 4.0 km/h, both walks.

---

## 2. Why the veto could not have been right (L-102)

At 08:40:03, `veh {a:"fire", spk:39.096, lim:35, n:4, m:11}` → `trip {a:"discard",
why:"vehicle", id:30}`.

These are not derived speeds. Every one is `sp > 0` from the provider, at 4.3–14 m accuracy:

| | 08:39:57 | 08:39:59 | 08:40:01 | 08:40:03 | 08:40:05 | 08:40:07 | 08:40:09 |
|---|---|---|---|---|---|---|---|
| km/h | 35.6 | 37.6 | 39.1 | 39.1 | 39.5 | 39.9 | 34.5 |
| `ac` m | 14.0 | 14.0 | 4.7 | 4.7 | 4.7 | 4.7 | 4.7 |

Six measured fixes at or above `vehicleSpeedKmh`, spanning 10 s. Now §10's drive, on the same
statistic:

| | fixes ≥ 35 | span | max | `ac` |
|---|---|---|---|---|
| the descent (bicycle) | 6 | 10 s | **39.9** | 4.3–14 |
| the drive, burst 1 | 5 | 8 s | 39.3 | 3.5–14 |
| the drive, burst 2 | 5 | 8 s | 37.7 | 3.5–4.7 |

**The cyclist is faster than the car and holds it longer.** There is no pair
(`vehicleSpeedKmh`, `vehicleSustainSeconds`) that refuses the drive and keeps the descent — the
live arm is not miscalibrated, it is *measuring the wrong thing*. The 2026-09-06 ride reached 38.4
measured and survived only on `vehicleSpeedMinFixes` (2 fast fixes, not 4); it was luck, not
margin.

### 2.1 What does separate them

The **share** of a recording's measured evidence that is fast, over the whole ride:

| recording | measured fixes | ≥ 35 km/h | share |
|---|---|---|---|
| 09-09 evening commute (44) | 38 | 0 | **0.0 %** |
| 09-06 evening ride (12) | 43 | 2 | **4.7 %** |
| 09-09 morning commute (30+31 recombined) | 42 | 6 | **14.3 %** |
| 09-07 drive to the shops (14) | 37 | 10 | **27.0 %** |

`vehicleSpeedMinShare` is already 0.25 and already sits in the gap. **The end-of-ride arm was
right about this morning and never got to answer**, because the live arm discarded the ride first
— and worse, truncating the recording at the descent leaves `vfx 4 / vmf 11` = 36 %, so the ride
*looks* like a car precisely because it was cut. **The live arm destroys the evidence the
end-of-ride arm needs.**

---

## 3. What to change

### 3.1 The live arm stops guessing at town speeds

Two constants where there is one. `vehicleSpeedKmh` (35) stays as it is and keeps feeding the
**end-of-ride share arm**, which the table above vindicates. A new `vehicleLiveSpeedKmh` — proposed
**50** — feeds `VehicleSpeedWatch.isVehicleNow` alone.

* At 50 km/h neither today's descent (39.9) nor §10's town drive (39.3) fires. **Zero false vetoes
  on the whole corpus**, and the drive is still refused, at the end, on its share.
* The live arm keeps its point: a road or motorway drive is stopped in seconds rather than
  recorded for half an hour, which is what it was for.
* `_fired` may keep short-circuiting `looksLikeVehicle`. At 50 km/h measured it is overwhelming
  evidence, which is exactly what the short-circuit assumes and what 35 did not justify.

**Honest limits, to be written into the constant's comment.**
* The share arm's margin is **14.3 % against 27.0 %**, on *one* drive and four rides. It is the
  best separation the evidence supports and it is thin. A cyclist who spends more than a quarter of
  their measured fixes above 35 km/h — a long descent, a paceline — still loses the ride, at the
  end instead of in the middle.
* At 50 the live arm becomes **untested on real data**: no measured speed above 39.9 exists
  anywhere in the corpus. It is a guard against a case not yet observed, and must be labelled as
  one rather than as a calibrated value.

### 3.2 The speed arm of the discard rule needs a distance proof (L-103)

`Trip.discardReason`, today:

```dart
if (netDisplacementMeters >= AppConstants.minTripNetDisplacementMeters) return null;
if ((avgSpeed ?? 0) >= AppConstants.minTripAvgSpeedKmh) return null;
return 'still';
```

The OR is right and stays (L-095: a loop ride comes home with `net` 0). But the `avg` arm exists
**for the loop ride**, and a loop ride has *distance*. A walk that returns near its start has
neither:

| trip | dist | `net` | `avg` | verdict today |
|---|---|---|---|---|
| 39 (a walk) | 545 m | 52 m | 6.51 | **kept as a cycling ride** |
| 43 (a walk) | 219 m | 45 m | 4.01 | **kept**, clearing the threshold by 0.01 |
| every genuine ride on record | 2 750 – 11 567 m | 904 – 7 940 m | 6.9 – 19.7 | kept, on `net` |

Proposed:

```dart
if ((avgSpeed ?? 0) >= AppConstants.minTripAvgSpeedKmh &&
    distance >= AppConstants.minTripLoopDistanceMeters) return null;
```

with `minTripLoopDistanceMeters` = **1 000 m**. The largest false trip of the day is 597 m; the
smallest genuine ride is 2 750 m; 1 000 sits 1.7× above the one and 2.75× below the other.

This is narrowly scoped on purpose, and answers the objection the existing doc comment raises
("Total distance is deliberately not consulted, because drift accumulates into it"):

* the `net` arm is **untouched**, so a straight 800 m ride to the bakery still passes on
  displacement and never reaches the distance test;
* distance is consulted **only** on the branch where displacement has already failed — where
  drift is the hypothesis being tested, not the measurement being trusted;
* replayed over all 40 recordings in the corpus, **exactly two verdicts change**, and both are
  walks. No genuine ride moves.

### 3.3 The thirteen false starts themselves — decide, do not silently accept

Every one has `spk 0` and `vt` absent: the gate has just opened, no fix has arrived, `c` is
motion-only, and motion does not separate walking from cycling (L-100 in the third direction —
`gav` is *higher* on foot, 1.4–3.8, than on the morning commute, 0.77–1.84).

§3.2 makes them harmless in History. It does not make them free: **~2 h 30 of GPS held open**
across the day (L-105). Three options, none costless, and this task should pick one rather than
leave the question implicit:

1. **Do nothing more.** The discard rule now catches them. Accept the battery cost; it is the
   price of T050's four-second departure.
2. **Require a fix to have voted** before a trip may start (`vt` true). Cheapest on battery,
   directly reverses the delay T048 and T050 were opened over. Probably wrong.
3. **A deadline, not a precondition**: allow the motion-only start, but end the recording if it
   runs *N* seconds without ever saying a bicycle is involved. Costs a genuine departure nothing.

**Chosen: option 3, and the calibration reshaped it.** "No fix has *voted*" turned out to be the
wrong test — measured on the corpus, a genuine commute went **256 s** before a fix voted and
another **204 s**, so a deadline tight enough to catch a walk cuts real rides, and one loose
enough to spare them (300 s, a 44 s margin on one sample) recovers only 14 % of the wasted GPS
and catches none of 2026-09-09's thirteen. Restricting the test to a **measured cycling speed**
sharpens the *discriminant* enormously — 19 of 21 false recordings never see one, while all nine
genuine rides eventually do — but not the *timing*: the slowest real ride waits 423 s, because the
iPhone reports `sp` 0 through the start.

So the rule carries **two terms**, and the second is what removes the dependence on how generous
the provider is being: at the deadline, no measured cycling speed **and** less than
`minTripNetDisplacementMeters` travelled. At 420 s that slowest commute had already covered
**271 m**, and the nine genuine rides read 271 / 964 / 1 277 / 1 536 / 1 943 / 2 146 / 2 426 /
2 462 / 2 810 m against the false recordings' **0–63 m** — 2.7× above the line on one side, 1.6×
below it on the other.

Measured over the corpus: **11 recordings cut, ~62 min of GPS recovered, both walks of §3.2 caught
a second time, and no genuine ride touched.**

Ending is all it does. `Trip.discardReason` then answers what it would have answered at any other
ending, so the deadline creates no discard reason of its own and can only ever cost a ride its
tail, never its existence.

---

## 3bis. What shipped

| | |
|---|---|
| `vehicleLiveSpeedKmh` = 50 | new; `isVehicleNow` alone. `vehicleSpeedKmh` (35) keeps the end-of-ride share arm |
| `minTripLoopDistanceMeters` = 1 000 | new; ANDed onto `discardReason`'s **speed** branch only |
| `noProgressStopTimeout` = 420 s | new; the deadline, with its displacement term |
| `AuditEvent.noProgress` (`prog`) | new line — `a` = arm/fire/disarm, `el`, `lim`, `net`, `cyc` |
| `k.vehLiveKmh`, `k.minTripLoop`, `k.noProg` | added to the log header |

`flutter analyze` clean, **806 tests** (779 → 806). The `veh` tests that encoded T051's behaviour
were rewritten rather than deleted: the drive to the shops is now asserted to be refused *at the
end*, and the 2026-09-09 descent is pinned as a trace that must not fire.

One interaction is worth naming: `gpsLossStopTimeout` (600 s) and the deadline (420 s) both cover
a recording that never receives a fix, and the shorter one now wins. That branch of the GPS-loss
watchdog is unreachable in practice, deliberately — 600 s of a phone left indoors is what L-105 is
about. What the watchdog still owns is a ride that *had* fixes and lost them, which the deadline
disarms itself for.

---

## 4. Acceptance

Not a test suite — a build and the next commutes.

1. **One trip per commute**, morning and evening, with **no `veh` line** in either. This is §10's
   unmet acceptance criterion, restated; it is now the second run to carry it.
2. A descent above 35 km/h **appears in `vfx` on the ending and does not end the ride**.
3. A working day with **zero** false trips in History. False *starts* may remain (that is §3.3
   option 1); a `trip {a:"stop"}` under 1 km that came home is a failure.
4. A drive, if one occurs, still ends as `trip {a:"discard", why:"vehicle"}` — at the end of the
   recording rather than at +339 s, which is the accepted regression.
5. ~~Unit tests~~ — **done**: `VehicleSpeedWatch` at both thresholds (the 39.9 descent, the
   recombined commute at 14.3 %, the drive at 27.0 %, a road drive that still fires live),
   `Trip.discardReason` on both walks and on a loop that must survive, and the deadline's five
   cases including the one that matters — a recording that went somewhere is not ended, and a
   derived speed is not a measured one.

---

## 5. Held in reserve — the duty cycle (L-104)

Measured on this log and not implemented: the **fraction of a recording spent being shaken**
separates the corpus more cleanly than anything else in it.

| | median `win.sd` | `sd ≥ 1` share |
|---|---|---|
| the three real rides | 0.86 / 1.38 / 2.28 | 47.2 % / 54.8 % / 70.4 % |
| all thirteen false trips | 0.01 – **0.22** | 3.4 % – **35.1 %** |

A 4× gap on the median with nothing in it. It is *not* about peaks — the false trips reach `sd`
p90 5.31, above the morning commute's 4.92 — but about continuity: a bicycle shakes the phone
without stopping, a desk does not.

Deliberately not the first fix: it needs the `win` statistics plumbed from the stationary window
into the recorder and into `Trip`, and a ride held at a level crossing or walked up a hill would
lower it. Take it only if §3.2 proves insufficient on the next logs.

---

## 6. Not changed, and why

* **`vehicleSpeedMinShare` (0.25), `vehicleSpeedMinFixes` (4), `vehicleSustainSeconds` (5),
  `vehicleSpeedWindowFixes` (6)** — the share arm is the one thing in T051 the evidence
  vindicates; leave it alone until a second drive exists.
* **T050's ramps** (`cyclingAccelStd*`, `cyclingGyroMean*`) — L-101 settled these on a proper
  replay, and nothing here contradicts it. The false starts are not a ramp being too loose; they
  are walking having the same signature as cycling.
* **`minTripNetDisplacementMeters` (100) and `minTripAvgSpeedKmh` (4)** — both correct; only their
  conjunction was missing a term.
* **The battery figure.** 100 % → 65 % in 10 h reads 3.5 %/h, but the log ran verbose and wrote
  219 376 lines. It is not a T041 item-4 measurement and must not be quoted as one.
