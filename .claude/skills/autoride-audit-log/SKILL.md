---
name: autoride-audit-log
description: Read, filter and cross-reference an AutoRide audit log (.ndjson.gz) exported from a device — event schema reference, jq recipes, clock alignment against a Strava FIT/GPX recorded in parallel on a second device, and a per-item verdict procedure for the T041 device-validation checklist. Use when a maintainer supplies an audit log file, asks why a trip did not start / pause / stop / end, or wants to close a T041 checklist item.
---

# Reading an AutoRide audit log

A user turned on **Settings → Diagnostic log**, rode, and exported
`autoride-audit-YYYYMMDD-HHMM.ndjson.gz`. One JSON object per line, gzipped.

## 1. Always read the header first

```bash
gzcat log.ndjson.gz | head -1 | jq .        # zcat on Linux
```

The header's **`k` holds the thresholds of the build that wrote the log**. Read
those, never today's `lib/core/constants/app_constants.dart` — explaining a
decision an older build took with the current constants is how you conclude the
opposite of what happened.

Also in that first line: `lvl` (normal or verbose — several verdicts below
depend on which), `cap` (whether this file is the **training capture** rather
than the journal — see §2b), `app`, `os`, `dev`, `tz` (offset to apply to every
`t`), `tzn`, `n`, `from`/`to` and `exp` (when the file was written).

A file with `lvl: "off"` and `cap: true` is a capture exported while the
diagnostic log was off. It is not an empty file, and it is not a bug: capture
and the journal are two independent axes (T034), and the export writes one or
the other, never both.

There are **two kinds of `hdr` line** and they carry different fields:

| | Written by | Fields |
|---|---|---|
| File header | the exporter, once, always the first line | `sv` `lvl` `app` `os` `dev` `tz` `tzn` `n` `from` `to` `exp` `k` |
| Launch header | the app, once per process, at the off→on transition and after "Clear log" | `sv` `lvl` `clk` = `{wall,mono}` `k` |

Counting launch headers is how the number of process launches is bounded (item
8 below): one per process, so a second one mid-file means either a relaunch or
the user toggling the log off and on again. `set {k:"auditLog"}` tells the two
apart. Early T043 builds emitted a launch header on *every* settings change, so
if the `hdr` lines outnumber what the `app` lifecycle events can account for,
suspect that rather than a string of process deaths.

## 2. The line format

Every line is `{"t":<epoch ms UTC>,"e":"<type>",…}`. **`t` is the moment the
event was *emitted*, not necessarily the moment it describes.** Field names are
short; the table below is the whole vocabulary.

| `e` | Meaning | Key fields |
|---|---|---|
| `hdr` | Header — file or launch, see above | `sv` `lvl` `k` (+ the columns above) |
| `app` | Lifecycle | `st` = resumed/inactive/paused/hidden/detached |
| `perm` | Permission / auto-detection inputs | `k` = autoDetection: `en` `loc` `onb` `go`. `k` = background (L-078): `why` = session/change, `alw` (OS granted "Always" / "Allow all the time"), `acc` = precise/reduced, `issue` = alwaysMissing/preciseMissing (absent when all is well) |
| `set` | A setting changed | `k` = automaticDetection/batteryMode/backgroundLocation/auditLog/auditLogLevel, `o` (old) `n` (new) |
| `clk` | Wall/monotonic pair, re-emitted when they drift > 2 s apart | `wall` ms, `mono` ms since launch, `drift` ms |
| `aud` | The log about itself | `a` = overflow (`n` lines dropped by the buffer backstop) / purge (`n` rows deleted by retention, `why` = age/rows/bytes — L-085) |
| `sess` | Coordinator session | `a` = start/stop/suspend; `trip` (active trip) on a start, `why` = deferredUntilTripEnds on a deferred stop |
| `st` | Trip state transition | `f` (from) `to` |
| `gate` | Motion-gated GPS | `a` = open/sched/close; `why` = trip/motion (open), stationary (sched), inactivityTimeout/stop/session/dispose (close); `in` (s) on a sched |
| `fix` | GPS fix | `lat` `lon` `ac` m `sp` **m/s** `al` `hd` `gt` (provider time). `sp` is always what the OS said; `dsp` **m/s** appears only where T048 derived a speed from the displacement since the previous fix and the pipeline used *that* — so `dsp` present means `sp` was 0 or invalid |
| `hb` | Heartbeat, every 30 s | `n` ticks, `mn` motion samples the pipeline processed, `dr` samples the rate hold dropped, `fn` fixes, `dt` ms, `hz` configured sampling rate. `mn / (dt / 1000)` is what the pipeline ran at; `(mn + dr) / (dt / 1000)` is what the OS delivered, and that is the figure to compare with `hz` (L-086, T045) |
| `start` | Trip-start evaluation | `c` confidence, `n` streak, `go`, `mag` `gyr` `spk`, `vt`. `vt` false means the fix was too coarse (`k.spAcc`) or too old (`k.spAge`) for its speed to be believed, so `c` is motion-only and `spk` did **not** enter it (T048); absent when there was no fix at all |
| `dto` | Detection window timed out | `el` s, `n` streak at timeout |
| `cool` | Start cooldown | `a` = arm (`d` s, `why` = falseStart) / expire (`d` s). Armed only by a recording discarded for being **too short** — a long one discarded for want of route points is a GPS failure, not a false start (L-081) |
| `win` | Stationary window (**verbose**) | `n` `sd` m/s² `gy` rad/s `sta` `src` = gps/gps+vib/sensors `spk` km/h. Throttled to 1 Hz; every change of `sta` or `src` is kept (L-085) |
| `sens` | 1 Hz sensor aggregate (**verbose**) | `am` `gm` `ms` (MotionState) |
| `raw` | One second of raw motion (**capture**, T034) | `sess` the capture session, `hz` requested rate, `n` samples kept, `ax`/`ay`/`az` m·s⁻², `gx`/`gy`/`gz` rad·s⁻¹ — six arrays of length `n`, in sample order. `t` is the **end** of the window |
| `lbl` | Capture ground truth (**capture**, T034) | `a` = start/stop, `act` = bike/car/walk/still/other, `sess` the session id (its start, in epoch ms) |
| `stop` | Stop decision | `d` = continueTrip/pauseTrip/stopTrip, `sta` `cs` `cm` `so` s. Throttled to `k.evalMs`; every decision and counter change is kept (L-085). While the trip is *paused* only the decisions appear here — the once-a-second `continue` is `res`'s job |
| `res` | Resume evaluation | `go` `cm` `mv` ms of continuous movement (what the decision is made on, against `k.resume`) `so`. Throttled like `stop`, keyed on `mv` restarting |
| `trip` | Trip lifecycle | `a` = start/pause/resume/stop/discard, `id`; start: `conf` `act` `pre` (or `man` on a manual start); pause: `dist`; resume: `pau`; stop/discard: `dist` m `dur` s `pau` s `avg` `max` `n` `pts`. `n` is every route point the ride kept, and it is what the discard decision turns on against `k.minTripPts` (L-081); `pts` is present **only** when the final flush failed, and counts the points still stuck in the buffer |
| `bdate` | Start back-dated (L-076) | `id` `k` fixes `m` metres `ts` new start `was` old start |
| `buf` | Pre-trip buffer (**verbose**) | `a` = add/tail/clear, `n` fixes, `sp` span ms, `kp` kept by the riding-tail cut (tail), `why` = inactivityTimeout/stop/session/dispose/gpsError/recording/tripEnd (clear) |
| `gpsw` | GPS-loss watchdog (L-074) | `a` = arm/fire/disarm, `el` s `lim` s `ref` = lastFix/tripStart |
| `gps` | Location stream trouble | `a` = resub (`n` failures, `in` ms backoff) / error (`ex`) |
| `rp` | Route point | `a` = keep (normal) / drop (**verbose**), `why` = acc/speed/dist, `d` `ac` `spk` |
| `flush` | Database write | `a` = points, `n` `ms` `ok` |
| `pwr` | Power mode | `m` `b` % `hz` `df` `ui` `la` |
| `bat` | Battery sample (5 min, and on every OS battery-state change) | `b` % `ch`. A reading identical to the previous one inside the same 5-minute tick is not written (L-086) |
| `fgs` | Foreground service | `a` = start/stop/fail, `plat` = android/ios (L-078), `ex` on a fail |
| `noti` | Notification | `a` = show/cancel/action; `k` = fg/start/stop on a show or cancel, the action id (pause/resume/stop) on an action. Never the text. `show k:"fg"` is **verbose** |
| `log` | Bridged from `Logger` | `lv` = d/i/w/e, `tag` `m` |
| `err` | Error | `tag` `m` `ex` `st` (top 3 frames) |

### 2b. Capture files (T034)

A capture export holds only `hdr`, `raw` and `lbl`. Its unit is the **session**:
one `lbl a:"start"` opens it, one `lbl a:"stop"` closes it, and every `raw` line
between them belongs to the `sess` both labels name. A session with no closing
`lbl` was interrupted (a kill, a crash, a "delete training data" while it ran) —
its data is still labelled, and still usable.

`n` is what the second actually held, and is **not** `hz`. The OS rounds the
requested sampling period and the T045 rate hold drops the surplus, so a healthy
file has `n` a little under `hz`; a run of lines with a much smaller `n` is the
device throttling the sensors, not the rider standing still. Use `n`, never the
array index, to reconstruct a timeline.

Turning a session into fixed windows, from the shell:

```bash
# Sessions in the file, with their labels and how long each recorded.
zcat autoride-capture-*.ndjson.gz \
  | jq -rc 'select(.e=="lbl") | [.sess, .a, .act, .t] | @tsv'

# Every accelerometer sample of one session, flattened to one row per sample
# (t is interpolated inside the window: the line's t is its END).
zcat autoride-capture-*.ndjson.gz \
  | jq -rc --argjson s 1756900000000 '
      select(.e=="raw" and .sess==$s)
      | . as $l
      | range(0; $l.n) as $i
      | [$l.t - 1000 + ($i * 1000 / $l.n) | floor,
         $l.ax[$i], $l.ay[$i], $l.az[$i],
         $l.gx[$i], $l.gy[$i], $l.gz[$i]] | @csv'

# Sanity check before training on it: the rate each line really carried.
zcat autoride-capture-*.ndjson.gz \
  | jq -rc 'select(.e=="raw") | .n' | sort -n | uniq -c
```

Every capture line carries `sess`, so a session can be selected without
reasoning about what the `lbl` lines bracket. The database keeps the same id in
a column of its own, which is what retention deletes on.

Speeds: `fix.sp` and `fix.dsp` are **m/s**; `win.spk`, `start.spk`, `rp.spk` are
**km/h**.

**Reconstructing `start.c`.** `c` is `mag`/`gyr` scored alone when `vt` is false
or absent, and `mot × k.wMot + speed × k.wSpd` only when `vt` is true. Reading
every line the second way — as was natural before T048 put `vt` in the file —
attributes a motion-only score to a speed that never voted, and is how a fix
that vetoed a whole ride (L-087) can be made to look like corroboration.

**Two clocks, one pause.** `stop.so` / `res.so` count from the *stationary
onset*; `trip.pau` counts from the state machine's *pause transition*, which
happens `k.minPause` seconds later. `so` ≈ `pau + minPause` for the same pause,
and that is agreement, not a discrepancy (L-086). Files written by a build
older than schema 2 (`hdr.sv`) carry the same number under `pd`.

**Sampling rate.** `hb.hz` is what the power mode *asks* the OS for;
`mn / (dt / 1000)` is what arrived. They differ — 55.6 Hz backgrounded and
83 Hz foregrounded for a configured 50 on a Pixel 6a, 51.4 Hz on an iPhone
(L-086) — because a sampling period is a request. Read the measured rate,
never `k.hzN`.

**Retention is no longer silent.** An `aud {a:"purge"}` line says how many rows
a bound deleted and which bound bit. A file whose first lines are mid-session
*and* carries no `purge` line was truncated by the export's `since` filter, not
by retention.

## 3. Recipes

```bash
# The decision timeline — usually start here.
gzcat log.ndjson.gz | jq -c 'select(.e|IN("sess","st","trip","gate","gpsw","app","bdate"))'

# Gaps, correlated with the heartbeat. n well below 30, or dt well above 30000,
# means the OS froze the process; n intact with mn == 0 means the process ran
# but sensors_plus delivered nothing.
gzcat log.ndjson.gz | jq -r 'select(.e=="hb")|[.t,.n,.mn,.fn,.dt]|@tsv' \
  | awk '$2<25 || $5>35000'

# The rate the pipeline really ran at, against the one the power mode asked for.
gzcat log.ndjson.gz | jq -r 'select(.e=="hb")|[.t,(.mn/(.dt/1000)),.hz]|@tsv'

# Battery profile → %/hour.
gzcat log.ndjson.gz | jq -r 'select(.e=="bat")|[.t,.b]|@tsv'

# Time the GPS gate spent open (the first suspect for drain). `why` on a close
# separates a real stationary timeout from a session teardown, which is not the
# rider standing still.
gzcat log.ndjson.gz | jq -r 'select(.e=="gate")|[.t,.a,.why]|@tsv'

# Session health, first thing on any "it did not work" report: what the OS
# granted, whether the foreground service started, and every error.
gzcat log.ndjson.gz | jq -c 'select(.e|IN("sess","perm","fgs","err"))'

# Where a heartbeat series stops, and what came back. A large dt on the line
# AFTER a gap means a suspension; a gap with no hb after it at all means the
# process was killed — look for the next launch `hdr` to confirm.
gzcat log.ndjson.gz | jq -r 'select(.e|IN("hb","hdr","app"))|[.t,.e,.n,.dt,.st]|@tsv'

# Everything around one instant.
gzcat log.ndjson.gz | jq -c --argjson a 1756800000000 --argjson b 1756800120000 \
  'select(.t>$a and .t<$b)'

# Clock offset against GPS time: the median of t - gt.
gzcat log.ndjson.gz | jq -r 'select(.e=="fix" and .gt)|.t-.gt' \
  | sort -n | awk '{a[NR]=$1} END{print a[int(NR/2)]}'

# The log as a GPX track, to overlay on the Strava ride.
gzcat log.ndjson.gz | jq -r 'select(.e=="fix")|
  "<trkpt lat=\"\(.lat)\" lon=\"\(.lon)\"><time>\(.t/1000|todate)</time></trkpt>"'
```

## 4. Aligning against a Strava FIT/GPX

Two devices, two clocks. Each `fix` carries **both** `t` (this phone's wall
clock at reception) and `gt` (`location.timestamp` — on a real GNSS fix,
disciplined by the satellites).

1. **Clock estimate**: the median of `t - gt` is the device's offset plus
   delivery latency. Subtract it and every other event — which carries only `t`
   — lands on the GPS timescale, which is the FIT's timescale.
   Compute it **per segment between two `clk` events**: an NTP correction
   mid-session poisons a single global median.
2. **Geometric estimate**: decode the FIT (`fit_dart_sdk` is already in
   `pubspec.yaml`, or use `fitdecode`/`gpsbabel`), then match points spatially
   and look at the distribution of Δt.

Agreement within ±2 s means the cross-reference is solid. Disagreement means one
of the two traces has a problem — say so instead of picking one.

`gt == t` exactly happens on a fix served from a network/cache provider
(Android); those fixes are useless for the clock estimate — filter them out.

## 5. Verdicts for `tasks/T041-device-validation.md`

**Item 1 — GPS stops when stationary.** Expect `win`/`sens` stationary →
`gate {a:"sched",why:"stationary",in:30}` → 30 s with no `fix` →
`gate {a:"close",why:"inactivityTimeout"}` → **no `fix` after that**. A later
`fix` proves a leak. Any other `why` on the close (`stop`, `session`,
`dispose`) means the session was torn down and the item was not exercised.
*Limit*: the OS location indicator is not observable from Dart. The log proves
the app stopped *asking*, not that the OS turned the chip off. It gives the
exact instant the indicator should go dark, which makes the visual check
verifiable rather than approximate.

**Item 4 — battery drain.** `bat` every 5 min gives %/hour; `pwr` says which
mode was in force; the summed `gate open`→`close` time is the denominator.
*Require `lvl: "normal"` in the file header* — the log itself consumes, and a verbose run is not a
neutral observer. Ask for a control run with the log off before quoting a
number.

**Item 8 — detection with the screen off.** Expect `app {st:"paused"}`, then a
continuous `hb` series with `mn > 0` and **no** `app {st:"resumed"}`, then
`start`, `st idle→detecting`, `trip {a:"start"}`. Conclusive because of `hb`.

**The two platforms fail this item for different reasons, and the log says
which.** Check the prerequisites *before* reading the heartbeats:

- `fgs` must show `{a:"start"}` and never `{a:"fail"}`. A `fail` carries the
  exception in `ex`; before L-078 the failure was swallowed and left **no `fgs`
  line at all**, so an old log with no `fgs` is a failed start, not an absent
  call.
- **`plat` decides what an `fgs start` is worth.** The foreground service is
  Android's mechanism. On iOS `flutter_background_service` starts a second
  FlutterEngine and holds no notification, so `fgs {a:"start",plat:"ios"}`
  promises nothing about the process surviving. Do not read one platform's
  evidence into the other.
- On **iOS**, the line that matters is `perm {k:"background"}`: `alw` false
  means "While Using" was granted, under which iOS terminates the process a few
  minutes after `app paused` no matter what else is configured. That is the
  verdict, and no amount of heartbeat reading substitutes for it.

**Then separate a suspension from a termination — they are different verdicts
and look identical if you only read the gap.** After the `hb` series stops:

| What comes back | Reading |
|---|---|
| An `hb` with a large `dt` (and `n` far below `dt/1000`) | The OS **suspended** the process and let it resume. The 1 Hz timer was frozen; the process is the same one. |
| Nothing, then a fresh **launch `hdr`** and a `sess {a:"start"}` | The OS **terminated** the process. The next lines are a cold start, not a resume. |
| `hb` intact (`n` ≈ 30) with `mn == 0` | The process ran and `sensors_plus` delivered nothing — a different failure again, and the one item 3 is about. |

Worked example (2026-09-02, iPhone 14,3, build 1.0.0+8): seven clean heartbeats
after `app paused` (`n` 31, `mn` ~3084, `fn` 0), then silence for 40 min 17 s,
then a launch header — a **termination**, and the signature of "While Using".
The `fn` 0 on every one of those is not itself a fault: the gate was open but
the rider was stationary, so with a 15 m distance filter no fix was due.

**Item 9 — auto-pause/stop with the phone carried.** Needs `lvl: "verbose"`
(`win` is verbose-only).
- Red light: watch `win.sta` flip and `stop.cs` climb to `k.nSta`. Both are
  throttled to one line a second, so count the *transitions*, not the lines.
- Basket case: `win {src:"gps",spk:22,sta:false}` — GPS speed beat calm sensors.
- False pause on a slow climb: `win {src:"sensors",spk:4.2,sta:true}` — the
  speed sits in the dead band between `k.staKmh` (3) and `k.movKmh` (6), where
  neither GPS arm applies and the sensors decide alone. That band is the knob.

**Item 10 — trip ends on GPS loss.** Expect `gpsw {a:"arm",ref:…}` (the `ref`
says what the countdown runs from — a slow first fix must not end a ride), then
`k.gpsLoss` seconds with no `fix`, then `gpsw {a:"fire"}`, the `log` warning,
`trip {a:"stop"}` and `st active→idle`. A tunnel is a `fix` gap with **no**
`gpsw fire`.

**Item 11 — the trip starts where the riding started.** Take `bdate` and the
`fix` lines before it. The prefix should open at the first fix with
`(dsp ?? sp)*3.6 ≥ k.cycMin` — on a build before T048, or a provider that
reports its own speed, that is just `sp`; check `ts` matches it and that the walk to the bike (fixes
below that speed) is *before* `ts`. After a long stop, expect `gate close` then
a `trip start` with no `bdate` (or `k:0`). This is the item where the Strava
cross-reference is worth the most.

## 6. Traps

- `t` is emission, not occurrence.
- `aud {a:"overflow"}` is a **declared** gap (the buffer was trimmed) and the
  only `aud` action there is. Do not read it as an OS suspension — that is what
  `hb` is for. A retention purge is silent, and a clock jump is a `clk`, not an
  `aud`.
- A missing verbose event may just mean the log ran at normal level. Check the
  file header's `lvl` before concluding anything is absent.
- A `sess {a:"stop"}` is not followed by a `suspend` for the same stop: one stop
  is one `sess` line, and only a session that actually started produces one.
- Timestamps are UTC ms; apply `hdr.tz` before quoting a time to the user.
- **Never re-`echo` a line through the shell.** A loop like
  `… | while read -r l; do echo "$l" | jq …; done` makes `echo` expand the `\n`
  inside an `err`'s `ex` into a real newline, and jq then reports *"Invalid
  string: control characters from U+0000 through U+001F must be escaped"* on a
  line that is perfectly valid. The log is not corrupt; the pipeline is. Feed
  the stream straight to jq, or use `printf '%s'` if a loop is unavoidable.
- A `select()` filter written with `test()` on `.e` matches substrings: a
  `test("hb|acc")` exclusion also swallows unrelated types. Use
  `IN("hb","acc")` (or `==`) whenever the point is the event type.
- **No `fgs` line at all is not "the service was never asked for".** Before
  L-078 a failed start threw inside a swallowed catch and produced nothing;
  since L-078 it produces `fgs {a:"fail"}`. Which build wrote the log decides
  how to read the silence — the header's `app` says.
- **No `perm {k:"background"}` in a pre-L-078 log is not evidence either**, and
  neither is a missing `perm {k:"autoDetection"}`: the latter was emitted only
  on a *change*, and its comparison against an uninitialised provider state
  threw on the first build of a cold start — precisely the launches worth
  explaining.
- **`dsp` absent across a whole run is a finding, not a formatting detail.** The
  derived speed only fires between two fixes that are accurate (`k.spAcc`),
  displaced further than their own accuracy, and **between `k.dspMin` and
  `pwr.ui × k.dspFac` apart**. That last bound is a multiple of the update
  interval the power mode requests, and not a fixed duration, because T048's
  first build used a fixed 30 s against an Android `locationUpdateNormal` of
  exactly 30 s: fixes arriving 30.7 s apart were all refused, and two Pixel
  rides derived nothing at all. So on a run with no `dsp`, check `pwr.ui`
  against the real fix cadence before concluding the provider was healthy.
