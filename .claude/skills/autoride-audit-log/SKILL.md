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
depend on which), `app`, `os`, `dev`, `tz` (offset to apply to every `t`),
`tzn`, `n`, `from`/`to` and `exp` (when the file was written).

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
| `perm` | Permission / auto-detection inputs | `k` = autoDetection, `en` `loc` `onb` `go` |
| `set` | A setting changed | `k` = automaticDetection/batteryMode/backgroundLocation/auditLog/auditLogLevel, `o` (old) `n` (new) |
| `clk` | Wall/monotonic pair, re-emitted when they drift > 2 s apart | `wall` ms, `mono` ms since launch, `drift` ms |
| `aud` | The log about itself | `a` = overflow (the only one), `n` lines dropped |
| `sess` | Coordinator session | `a` = start/stop/suspend; `trip` (active trip) on a start, `why` = deferredUntilTripEnds on a deferred stop |
| `st` | Trip state transition | `f` (from) `to` |
| `gate` | Motion-gated GPS | `a` = open/sched/close; `why` = trip/motion (open), stationary (sched), inactivityTimeout/stop/session/dispose (close); `in` (s) on a sched |
| `fix` | GPS fix | `lat` `lon` `ac` m `sp` **m/s** `al` `hd` `gt` (provider time) |
| `hb` | Heartbeat, every 30 s | `n` ticks, `mn` motion samples, `fn` fixes, `dt` ms |
| `start` | Trip-start evaluation | `c` confidence, `n` streak, `go`, `mag` `gyr` `spk` |
| `dto` | Detection window timed out | `el` s, `n` streak at timeout |
| `cool` | Start cooldown | `a` = arm (`d` s, `why` = falseStart) / expire (`d` s) |
| `win` | Stationary window (**verbose**) | `n` `sd` m/s² `gy` rad/s `sta` `src` = gps/gps+vib/sensors `spk` km/h |
| `sens` | 1 Hz sensor aggregate (**verbose**) | `am` `gm` `ms` (MotionState) |
| `stop` | Stop decision | `d` = continueTrip/pauseTrip/stopTrip, `sta` `cs` `cm` `pd` s |
| `res` | Resume evaluation | `go` `cm` `pd` |
| `trip` | Trip lifecycle | `a` = start/pause/resume/stop/discard, `id`; start: `conf` `act` `pre` (or `man` on a manual start); pause: `dist`; resume: `pau`; stop/discard: `dist` m `dur` s `pau` s `avg` `max` `pts` |
| `bdate` | Start back-dated (L-076) | `id` `k` fixes `m` metres `ts` new start `was` old start |
| `buf` | Pre-trip buffer (**verbose**) | `a` = add/tail/clear, `n` fixes, `sp` span ms, `kp` kept by the riding-tail cut (tail), `why` = inactivityTimeout/stop/session/dispose/gpsError/recording/tripEnd (clear) |
| `gpsw` | GPS-loss watchdog (L-074) | `a` = arm/fire/disarm, `el` s `lim` s `ref` = lastFix/tripStart |
| `gps` | Location stream trouble | `a` = resub (`n` failures, `in` ms backoff) / error (`ex`) |
| `rp` | Route point | `a` = keep (normal) / drop (**verbose**), `why` = acc/speed/dist, `d` `ac` `spk` |
| `flush` | Database write | `a` = points, `n` `ms` `ok` |
| `pwr` | Power mode | `m` `b` % `hz` `df` `ui` `la` |
| `bat` | Battery sample (5 min, and on every OS battery-state change) | `b` % `ch` |
| `fgs` | Foreground service | `a` = start/stop |
| `noti` | Notification | `a` = show/cancel/action; `k` = fg/start/stop on a show or cancel, the action id (pause/resume/stop) on an action. Never the text. `show k:"fg"` is **verbose** |
| `log` | Bridged from `Logger` | `lv` = d/i/w/e, `tag` `m` |
| `err` | Error | `tag` `m` `ex` `st` (top 3 frames) |

Speeds: `fix.sp` is **m/s**; `win.spk`, `start.spk`, `rp.spk` are **km/h**.

## 3. Recipes

```bash
# The decision timeline — usually start here.
gzcat log.ndjson.gz | jq -c 'select(.e|IN("sess","st","trip","gate","gpsw","app","bdate"))'

# Gaps, correlated with the heartbeat. n well below 30, or dt well above 30000,
# means the OS froze the process; n intact with mn == 0 means the process ran
# but sensors_plus delivered nothing.
gzcat log.ndjson.gz | jq -r 'select(.e=="hb")|[.t,.n,.mn,.fn,.dt]|@tsv' \
  | awk '$2<25 || $5>35000'

# Battery profile → %/hour.
gzcat log.ndjson.gz | jq -r 'select(.e=="bat")|[.t,.b]|@tsv'

# Time the GPS gate spent open (the first suspect for drain). `why` on a close
# separates a real stationary timeout from a session teardown, which is not the
# rider standing still.
gzcat log.ndjson.gz | jq -r 'select(.e=="gate")|[.t,.a,.why]|@tsv'

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

**Item 9 — auto-pause/stop with the phone carried.** Needs `lvl: "verbose"`
(`win` is verbose-only).
- Red light: watch `win.sta` flip and `stop.cs` climb to `k.nSta`.
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
`sp*3.6 ≥ k.cycMin`; check `ts` matches it and that the walk to the bike (fixes
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
