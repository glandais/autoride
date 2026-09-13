# T054 — Five seconds of a pocket is not a ride: the corroboration window, and the axis that never votes

Date opened: 2026-09-13. Status: ⏳ **diagnosis, plus the §4 replay, which refutes §3.1.**
Nothing written in `lib/`; the harness is `scripts/t054-replay/`.
Owner findings: **L-108**, **L-109**, **L-110**, **L-111**, **L-112** (`tasks/LEDGER.md` §13).
Depends on T050 (the windowed fit this task extends) and T053 (the build that produced the log).
Sibling of **T049**, which it supersedes in scope: T049 answered a kitchen with a sliding streak
made truly consecutive; this is the same kitchen answered again on a build that already carries
that fix, and it says the streak is the wrong *length*, not the wrong *shape*.

**Read §12 first.** The speed axis is closed by decision. Nothing in this task reopens it —
L-109 is not "make speed decide", it is "the 40 % weight the code already gives speed is silently
zero, and the threshold everyone reasons about is not the threshold in force".

---

## 1. What happened

2026-09-12 16:08 → 2026-09-13 18:05 CEST, 26 h, iPhone 14,3 on **1.0.0+16** at verbose.
`autoride-audit-20260913-1805.ndjson.gz`, 201 145 lines, cross-referenced against two Karoo FIT
files. Clock offset 36 ms over 2 170 fixes.

| | |
|---|---|
| Trips started | **26** |
| Endings | 27 — **4 kept**, **23 discarded** (11 `still`, 11 `pts`, 1 `dur`) |
| Phantom recording time | **3 h 44** |
| `st idle→detecting` | **91**, of which 65 timed out before a start |
| GPS gate open | **8.1 h of 26**, against ~3.2 h of riding |
| Battery | **55 % at 20:16 → 1 % at 11:06**, no ride between 03:16 and 16:47 |

Between **18:33 and 03:16** the app opened **22 recordings** while the rider was not riding, at a
cadence of about seven minutes — the length of `noProgressStopTimeout`, which is what ended 19 of
them. The rider cooked, went out, came home. The only correct outcome was **two** trips in that
window (22:44 and 02:56, both plausible short night rides), not twenty-four.

**The long ride was measured correctly and bracketed wrongly.** Against the Karoo:
`trip 123` = 35 735 m against the FIT's 35 669 m *from the same instant* — 66 m over 35 km — but it
**started 22 min 34 s and 5 526 m late** and **ended 11 min 26 s late** at the same coordinates.

## 2. The four things the log says

### 2.1 The corroboration window is three seconds, and rest supplies three seconds (L-108)

Every false start has one shape: ~18 s of `asd ≈ 0.03–0.4`, then a burst.

```
22:12:10..27   asd 0.03–0.4    gav 0.04–0.4    c 0        (18 s of quiet)
22:12:28       asd 2.667  gav 1.538  c 0.834  n=1
22:12:30       asd 2.415  gav 2.902  c 0.707  n=1
22:12:32       asd 2.599  gav 2.850  c 0.800  n=2
22:12:33       asd 3.512  gav 1.306  c 1.000  n=3   → trip start "cycling"
```

The distributions are why a threshold cannot fix this:

| segment | `win.sd` p50 / p90 / p99 | `win.gy` p50 / p90 / p99 |
|---|---|---|
| trip 123 — real, 35.7 km | 3.46 / 12.10 / 23.55 | 0.85 / 2.05 / 3.68 |
| trip 148 — real, 7.5 km | 1.71 / 4.55 / 6.29 | 0.79 / 1.45 / 1.85 |
| the evening, at rest | **0.47 / 2.13 / 5.22** | **0.59 / 1.40 / 2.15** |

The medians separate by 4–7×. **The tail of rest covers the median of riding**: 31 700 s of evening
puts over 300 s above the p99, and the detector asks for **three consecutive seconds**. That is not
a rare coincidence, it is a guaranteed event several times an hour — the detector is a
max-statistic, and the longer the phone sits still the more certain it is to fire.

T050 closed L-079, the per-sample coin toss. `tripStartMinConsecutiveDetections` 3 /
`tripStartDetectionWindowSeconds` 5 is the same coin toss at 1 Hz.

### 2.2 The speed half of the confidence has never voted (L-109)

`vt:false` on **26 of 26** starts; `vt:true` on **247 of 55 269** evaluations — **0.45 %**, or 2.2 %
of the 11 209 that had a fix at all — **none** of which started a trip. So `c = mot` always, `tripStartSpeedWeight` (0.4) is dead weight, and
`tripStartConfidenceThreshold` (0.7) is in force as a *motion-only* threshold — which is not what
0.7 was chosen to mean.

The cause is not `k.spAge`. It is the gate: eleven seconds before trip 133 opened the log reads
`gate {a:"sched", why:"stationary"}`. There is no fix to judge because the app has switched the GPS
off, by design, precisely while it is deciding. Through the whole 420 s of that trip **no `fix`
arrived**; the next one carries `ac` 14.246, the same frozen cached value repeated since 19:15.

On the rides themselves the provider is healthy — 1 253 measured fixes at 25.7 km/h mean on
trip 123, 361 at 20.3 km/h on trip 148. **The axis is fully available five minutes after the
decision and never at it.**

### 2.3 The back-date is dead on iOS (L-110)

**No `bdate` in 26 h and 26 starts.** Trip 148 opens with `buf {a:"tail", n:3, kp:0}` — the
riding-tail cut kept none of three buffered fixes, because every fix from 16:40:20 to 16:51:05
carries `sp:0` and the cut tests `sp` against `cyclingSpeedMin` (8 km/h). The first non-zero speed
of that ride is a **`dsp`**, four minutes after the trip opened.

So the prefix is always empty and a trip always starts where the *detector* fired. **T041 item 11
fails on this build.** This is also the most likely reading of trip 123's missing 22 minutes,
though that stretch was purged and cannot be proved here.

### 2.4 A pause that will not hold (L-111)

After the Karoo stopped at 17:41:18, trip 123 flapped four times before dying at 17:52:44:
pause 17:41:49 → resume 17:42:12 (23 s), pause 17:45:36 → resume 17:45:48 (**12 s**),
pause 17:46:20 → resume 17:47:02 (42 s), pause 17:48:14 → `maxPause` at 17:52:44.

`resumeMovementThresholdSeconds` is **5**. It is the same 5 s of motion-only corroboration as §2.1,
applied to resume, and a rider standing over a bike supplies it repeatedly. **Fix it in one place
or fix it twice.**

## 2bis. What the replay says — and it refutes §3.1

Run 2026-09-13 over **seven pooled `sv:3` corpora** (2026-09-07 → 09-13, builds
1.0.0+13 → +16, every start-path constant identical across them): **299 890 evaluations,
83.6 h of evaluated time, 21 real journeys and 72 phantom recordings.** That is 27× the
corpus §4 assumed. Harness and method: `scripts/t054-replay/`.

### The method trap, first, because it inverts the answer

**A log written by a 3-second rule truncates every positive run at 3 seconds.** The instant
the streak reaches 3 the trip opens and the start detector stops being evaluated, so seconds
4..N were never written. The first run of this replay scored `streak 5s` at **0.6 false
starts per 24 h against the baseline's 20.1** — a 97 % cut, and pure artefact: the evidence
that would have convicted it had been blacked out.

The seconds are recoverable from `win`, which the *stop* path emits at 1 Hz throughout a
recording, and whose `sd`/`gy` are the same `StationaryWindow` statistics (1.5 s rather than
1 s; validated at the seam — median 2.97 against the `asd` 2.92 that fired it). Following
every truncated run into the recording it opened, `streak 5s` scores **42 against 52**.

### The result

| rule | journeys started | median added latency | p90 | false starts / 24 h |
|---|---|---|---|---|
| **streak 3s** (today) | **21/21** | — | — | **15.6** |
| streak 5s | 21/21 | 5 s | 58 s | 12.6 |
| streak 8s | 21/21 | 24 s | 278 s | 8.4 |
| streak 10s | 20/21 | 90 s | 390 s | 6.3 |
| streak 15s | 16/21 | 179 s | 465 s | 4.2 |
| streak 30s | 11/21 | 440 s | 518 s | 1.2 |
| duty 28 %/60 s | 21/21 | 59 s | 212 s | 9.6 |
| duty 18 %/120 s | 21/21 | 117 s | 163 s | 8.7 |
| duty 28 %/300 s | 16/21 | 300 s | 609 s | 1.5 |

**No candidate keeps the departures and loses the false starts.** The best rules that still
start all 21 journeys cut false starts by **38–45 %**, for one to two minutes of median added
latency. Halving them costs rides.

### Why — the premise was wrong

§3.1 assumed "the burst is 5 s; a ride is minutes". Measured on `win`, over 7.6 h of real
journeys against 10.3 h of phantom recordings:

| | duty cycle above 0.7 | median burst | p90 | p99 | max |
|---|---|---|---|---|---|
| real journeys | **23.4 %** | 2 s | 11 s | 46 s | 85 s |
| phantom recordings | **7.0 %** | 2 s | 9 s | 25 s | 37 s |

**A bicycle does not hold the threshold either.** Riding is 23 % duty with a *median
two-second burst* — the same shape as standing still, three times as dense. Requiring ten
consecutive seconds throws away 96 % of genuine riding seconds, which is exactly why
`streak 30s` finds eleven journeys out of twenty-one.

So the discriminant that exists in these two features is the **density**, not the length —
L-104, offered in ledger §11 and still unimplemented, is the right instinct. But 23.4 %
against 7.0 % is a 3.3× separation between *whole recordings*, and at the decision instant,
on a 30–120 s window, it buys the 38–45 % above and no more.

**This does not make the work pointless, it re-prices it.** A 40 % cut in phantom recordings
is ~1.5 h of GPS a day on the §13 corpus. It is worth having, it is not a fix, and it must
not be sold as one.

## 3. What to change

Nothing here is written. The order is by evidence, not by ease.

### 3.1 Score the density, not the length — and expect 40 %, not a fix (L-108, L-104)

**The longer-streak option is dead** (§2bis): a ride's own bursts have a median length of two
seconds, so any rule that asks for a long run refuses the rider before it refuses the pocket.

What is left is the duty cycle, and the replay prices it honestly. Two settings keep every one
of the 21 journeys:

* **duty ≥ 28 % over 60 s** — 9.6 false starts a day against 15.6, median added latency 59 s.
* **duty ≥ 18 % over 120 s** — 8.7 a day, median 117 s, and a *tighter* p90 (163 s) than the
  60 s rule's 212 s, which is the argument for the longer window.

Either is a **~40 % cut for one to two minutes of latency**, and that latency is only acceptable
if it is back-dated away — so **3.3 stops being a companion fix and becomes the prerequisite**.
Ship 3.3 first, verify a `bdate` appears on a device, then take the duty cycle.

Re-run `scripts/t054-replay/` on any new corpus before moving either number. Two things the
harness will tell you that a device run will not: whether the candidate still starts every
journey, and whether the apparent win is the truncation artefact §2bis describes.

### 3.2 Make the speed weight honest (L-109)

Either the weight votes or it goes. Three options, in order of increasing ambition:

1. **State it.** If the start is motion-only in practice, delete `tripStartSpeedWeight` and set the
   threshold on the motion score explicitly, so 0.7 means what a reader thinks it means. Cheapest,
   changes no behaviour, and stops the next maintainer reasoning about a 60/40 blend that has never
   existed on this platform.
2. **Open the gate to decide.** Let a streak that reaches the threshold open the GPS gate and
   *hold* the start pending a recent fix, with a bounded wait. Costs battery in exactly the
   situation where 3.1 is trying to save it, so it only makes sense on top of a corroboration long
   enough to be rare.
3. **Confirm rather than gate.** Start permissively (as today) and let the already-shipped
   `noProgressStopTimeout` be the speed test it effectively already is — it is what caught 19 of
   the 23 discards. This is the cheapest *behavioural* option and arguably what the pipeline is
   already doing by accident; the work would be to say so and to shorten the 420 s now that the
   start is rarer.

**None of these is a recalibration of the vehicle thresholds** (§12) and none makes speed a
classifier. It is a decision about honesty and about which stage of the pipeline carries the test.

### 3.3 Give the tail cut a speed it can actually read (L-110)

The cut must accept a **derived** speed the way the start path learned to in T048. `dsp` exists on
these fixes; `sp` does not. Until it does, no start is ever back-dated on an iPhone and every ride
begins late by however long the corroboration takes — which is exactly the cost 3.1 proposes to
add. Keep the load-bearing rule of §12 in view: a `dsp` is an inference, so it belongs in the
*back-date* (which only moves a timestamp) and not in anything that discards.

### 3.4 Resume needs the same evidence as start (L-111)

Whatever 3.1 settles on, `resumeMovementThresholdSeconds` inherits it. A resume is a start with
history; today it is cheaper than a start.

### 3.5 `sensorSamplingRateMedium` (L-112)

40 Hz requested, **24 Hz** delivered, on 1 138 of 2 565 heartbeats — the mode in force whenever the
battery sits between 20 % and 50 %. The other three modes lose 1 Hz. Either pick a rate iOS honours
(the 50/25/20 ladder all round-trips cleanly) or accept it and stop calling it 40. The fit sees a
40 % shorter window than it believes it has in that mode; whether that changed any decision in this
log is **not established** and should not be asserted without measuring it.

## 4. Acceptance

~~An offline replay first~~ — **done, 2026-09-13, see §2bis.** It was worth doing and it changed
the task: the corpus is seven logs and 83.6 h rather than the one log §4 first named, the
longer-streak candidate is refuted, and the duty cycle is priced at ~40 % rather than assumed to
be a fix. The 2026-09-03 kitchen logs turned out to be `sv:2` and cannot be replayed at all — the
windowed fit did not exist when they were written.

What remains for a re-run: `scripts/t054-replay/extract.sh` over whatever corpus exists then,
and the pass to beat is **21/21 journeys at 15.6 false starts a day**.

Then, on a device:

3. **An idle evening**, verbose, phone carried normally, no riding. Pass = **zero** `trip {a:"start"}`.
   This is T049 §5's run 1 and it has never yet passed on any build.
4. **A real ride with a Karoo alongside.** Pass = one trip, start within 60 s **and** back-dated
   (`bdate` present, `k` > 0), end within 60 s of the FIT's last point. Read `bdate` explicitly:
   its absence is the 3.3 failure and it will hide behind a "good enough" start time.
5. Re-read T041 **item 11**, which this task is the blocker for.

## 5. Not changed

* `vehicleSpeedKmh` / `vehicleSpeedMinShare` — closed by §12, by evidence and by decision.
* `noProgressStopTimeout` and the loop-distance proof — both held over 26 h and 19 fires, none of
  them on a real ride.
* The T046 iOS survival machinery — 2 565 heartbeats, not one `dt > 35 s`. It is finished.
* The T053 flag behaviour — no `veh` line in the corpus, nothing to judge.

## 6. What this does not solve

Nothing in this task classifies anything. A longer window and a duty cycle make the detector
*harder to fool by a phone at rest*; they do not make a bicycle distinguishable from a car, a bus
or a brisk walk, which remains the T034 capture's job and still has no task. All it buys
is a start path that costs the battery less and lies less often — worth having, and not the thing
the project is actually missing.
