# T050 — A window, not an instant: the ride that started ten minutes late

Date opened: 2026-09-06. Status: ⏳ **the three fixes are written and green (782 tests);
the device run is outstanding.**
Owner findings: **L-079** (open since 2026-09-02, now measured on a ride), **L-098**,
**L-099** (`tasks/LEDGER.md` §9).
Depends on T041 (the pipeline) and T043 (the log that decides it).
Third in the line T048 → T049 → T050, and the one that answers the question the
first two kept deferring: *what should a second of cycling look like?*

**Read ledger §9 first.** The numbers below are all from one log and none of them
are settled by a test suite.

---

## 1. What happened

2026-09-06, the rider cycled home from an evening out. One verbose log,
`autoride-audit-20260906-2345.ndjson.gz`, iPhone 14,3 / iOS 26.6.1, **1.0.0+12** —
after T048 and after all five T049 fixes. The only correct outcome is one trip
covering the whole ride.

One trip was started, and it is **9 min 50 s and ≈ 2.9 km short at the front**.

| | |
|---|---|
| Real departure | ~23:20:50 |
| `trip {a:"start", id:13}` | **23:30:38**, `conf` 0.721 |
| `bdate` reached back to | 23:29:12 — 86 s, 595 m, 13 fixes |
| Ridden before the start | **3 459 m**, of which 595 m recovered |
| `start` evaluations in between | **751** |
| Streak `n` | 0 × 501, 1 × 222, 2 × 27, **3 × 1** |

The rider's own report — *« il manque le début du tracé »* — is the whole of it.

---

## 2. Why

Three things, in a chain.

**2.1 The score is a coin toss (L-079).** `_getMotionScore` scored the single
20 ms sample it was handed, against bands written for an instantaneous
magnitude: `cyclingAccelerationMin/Max` = [10, 20] m/s² peaking at 15, and
`cyclingRotationMin/Max` = [0.5, 3.0] rad/s peaking at 1.75. On a bicycle \|a\|
swings between 4 and 24 m/s² from one sample to the next while its *mean* barely
leaves gravity — 9.81 standing, 10.2 pedalling. So the band scores noise, and
whichever sample happened to land on the evaluation boundary decided the
interval.

Measured on the ride: 250 of 751 evaluations above `k.conf`, 501 below, mean `c`
0.489. The `start` lines are emitted preferentially on streak changes, so the
unbiased figure is the 1 Hz `sens` series — **6.5 %** of sampled instants above
0.7. L-093's three-consecutive-intervals rule then multiplies a low per-sample
probability into a 590 s wait, and the streak distribution is exactly the
geometric law that predicts.

What actually separates a bicycle from a pocket, per phase of this same log:

| phase | std(\|a\|) | mean \|gyro\| |
|---|---|---|
| phone still on a table | 0.56 | 0.16 |
| carried, walking about | 1.86 | 0.65 |
| the ride that was missed | 3.90 | 1.32 |
| the ride once it started | 3.39 | 1.08 |

Both are properties of a **window**. A 6× separation from a still phone, and a
2× one from a walk, against a fit that was measuring neither.

**2.2 A fix with no speed vetoes anyway (L-098).** `speedIsTrustworthyAt` tests
accuracy and age and never asks whether there *is* a speed. iOS reports exactly
0 on fixes taken at 20 km/h; where `GpsSpeedEstimator` can derive a replacement
it does, and where it cannot, the detector receives a fresh, accurate fix
reading 0, scores `speedScore` 0, and caps the confidence at 0.60 under a 0.70
threshold. **155 of the 751 evaluations** were in that state.

**2.3 The safety net is shorter than the failure (L-099).**
`preTripLocationBufferDuration` was 90 s, sized on the *intended* confirmation
delay. `bdate` did its job and reached back 86 s; the other 2.9 km had aged out.

---

## 3. What shipped

### 3.1 The fit is windowed (L-079)

`TripStartDetector` keeps a `StationaryWindow` over
`detectionEvaluationInterval` and scores:

* `accelerationStdDev` on the ramp `cyclingAccelStdMin` 2.0 →
  `cyclingAccelStdIdeal` 3.0, flat to `cyclingAccelStdMax` 12.0, 0 outside;
* `averageRotation` on `cyclingGyroMeanMin` 0.4 → `cyclingGyroMeanIdeal` 0.9,
  flat to `cyclingGyroMeanMax` 3.0, 0 outside;
* half each, and **0** while the window holds fewer than
  `tripStartMotionWindowMinSamples` (5) — a standard deviation over two samples
  is noise.

Three decisions worth recording:

- **The ramp is asymmetric**, where the bands it replaces were triangular around
  a midpoint. There is no "too much vibration for a bicycle" short of something
  that is not a bicycle, so the plateau runs to the maximum: a rough road must
  not score *lower* than a smooth one, which is what a peak at a midpoint does.
- **The window is `StationaryWindow`**, the stop path's own class, read for the
  opposite question — with its duration and sample cap moved to constructor
  parameters. One implementation of the statistics, one buffer shape. The start
  path builds it over the evaluation interval rather than the stop path's 1.5 s,
  so that "this second was cycling" is a statement about that second and nothing
  before it; a longer window would carry the previous second's motion across the
  boundary the streak is counting.
- **The instantaneous bands are left alone.** `cyclingAcceleration*` and
  `cyclingRotation*` still have three consumers (`MotionData`,
  `CyclingPatternDetector`, the stationary classifier's neighbours); what
  changed is that **no start decision reads them any more**.

### 3.2 A fix with no speed is no fix (L-098)

`speedIsTrustworthyAt` gains `hasReportedSpeed` as its first arm. The predicate
now answers one question — may this fix's speed vote — with the three reasons it
might not: absent, too coarse, too old.

This is the arm that **loosens** the start path, and it is only safe shipped
with §3.1: it moves 155 evaluations of this ride onto the motion-only path,
which is precisely the path ledger §8 showed starting trips on hand gestures.
A windowed fit is what makes that path trustworthy. **Neither change should be
shipped without the other.**

### 3.3 The back-date window covers the worst case (L-099)

`preTripLocationBufferDuration` 90 s → **10 min**,
`preTripLocationBufferMaxPoints` 64 → **256** (~40 kB at the bound). Safe
because the buffer is cleared on every `gate close` — 30 s stationary — so its
span is always one continuous stretch of movement, and `ridingTailOf` still cuts
the walk to the bike off the front.

A net, not a fix: with §3.1 working it should never be reached.

### 3.4 The log says which (schema 3)

`start` carries `asd` (window std of \|a\|), `gav` (window mean \|gyro\|) and
`wn` (samples held). `mag`/`gyr` stay, as the instantaneous sample the line was
emitted on: the gap between them and `asd`/`gav` is L-079 visible in one line.
The new ramps travel in the header's `k` (`asdMin`/`asdIdeal`/`asdMax`,
`gavMin`/`gavIdeal`/`gavMax`, `wnMin`).

`AuditSchema.version` → **3**. `c` keeps its name, range and weights and changes
what its motion half *is*, so reconstructing it from `mag`/`gyr` — the recipe
every earlier reading of these logs used — would silently reproduce the old
arithmetic. The skill's procedure now branches on `hdr.sv`.

---

## 4. What the tests settle, and what they cannot

Green: 782 tests (was 772). The start detector's suite was rewritten around the
change — a single `MotionData` is no longer a scenario, so every test drives a
*second* of samples, as the 50 Hz stream does.

Pinned by tests:

- a constant sample dead centre of the old bands scores **0** on the
  acceleration arm and cannot start a trip (the regression this task is about);
- an unfilled window scores 0 rather than an accident;
- three consecutive seconds of cycling still start a trip, and five flat seconds
  still break the streak (L-093 replay, unchanged);
- a fix reporting no speed no longer vetoes, and an untrusted fix still does not
  raise a *walk* to a departure;
- a departure confirmed ten minutes late still finds its first cycling fix in
  the buffer.

Not settled by any of it: **whether the thresholds are right.** They are read off
a 1 Hz series and the fit runs at 20–50 Hz, where the within-second spread is at
least as large. Erring low starts rides on walks; erring high repeats this very
ride. Only a device run says which.

One test was dropped rather than adapted: `should reset consecutive count if
detection window exceeded`, which asserted only that a first detection registers
and said so in its own comment. Its subject is covered by *a gap in which
nothing was evaluated starts a new streak*.

---

## 5. Acceptance

**The same two device runs T048 §5 and T049 §5 already ask for**, on a build
carrying all three fixes, at verbose. T050 does not add a run; it changes what
run 2 has to show.

1. **An ordinary indoor hour.** Pass: **zero trips**, gate-open fraction under
   5 %. This is the run §3.2 puts at risk, and the one that says whether the
   windowed fit really refuses a kitchen.
2. **A real ride.** Pass: **one trip per phone within a minute of the real
   departure**, route matching a parallel Strava recording, and the back-date
   reaching the first fix at cycling speed. This ride would have failed it by
   ten minutes.

Read run 2 on `start`'s `asd`/`gav`/`wn` against `k.asd*`/`k.gav*`:

- `asd` on the plateau and a trip starting in ~3 s — the fix works;
- `asd` on the plateau and no trip — look at `gav` and the streak, not the fit;
- `asd` below `k.asdMin` while the rider is pedalling — the ramp is set too
  high for this phone's placement, and the constant is the knob;
- a kitchen run producing `asd` above `k.asdMin` for three consecutive seconds —
  set too low, and §3.2 has to be reconsidered with it.

---

## 6. Cross-references

- **L-093 is not the cause and must not be loosened on this evidence.** The
  streak dies on the first sub-threshold interval exactly as designed; the 501
  zeros are what it was fed. Ledger §6 named the discriminator in advance: `n`
  reaching 2 and dying is L-093's cost, `n` never reaching 1 is the confidence.
  Here `n` reached 2 twenty-seven times in 751 evaluations.
- **L-011** — `CyclingPatternDetector` stays unwired. T050 gives the start path
  a windowed fit; it does not add the frequency layer, and smuggling one in here
  would make the device run unreadable.
- **L-083** (the gate never closes while the phone is carried) was sequenced
  behind L-079 and is now unblocked.
- **T041 item 11** (the trip starts where the riding started) is what §3.3 and
  the back-date serve; it is still blocked on the same device run.
