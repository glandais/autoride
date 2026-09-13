# T054 replay harness

Answers, offline and from logs already on disk, the question T054 §3.1 asks:
**would a longer or differently-shaped corroboration keep the real departures
and lose the false starts?**

```bash
cd "$(mktemp -d)"
~/code/perso/autoride/scripts/t054-replay/extract.sh ~/Documents/autoride-audit-*.ndjson.gz
python3 ~/code/perso/autoride/scripts/t054-replay/replay.py   # the candidate sweep
python3 ~/code/perso/autoride/scripts/t054-replay/runs.py     # the burst-length distributions
```

## The trap it exists to avoid

**A log written by a 3-second rule truncates every positive run at 3 seconds.**
The instant the streak reaches 3 the trip opens and the start detector stops
being evaluated, so seconds 4..N of that run were never written to `start`. Read
naively, every longer streak therefore looks free: the first version of this
harness scored `streak 5s` at **0.6 false starts per 24 h against the baseline's
20.1**, which is not a result, it is the absence of the evidence that would have
convicted it.

The seconds are recoverable. Once the trip is active the *stop* path emits `win`
at 1 Hz, and `win.sd` / `win.gy` are the same `StationaryWindow` statistics the
start path scores (over 1.5 s instead of 1 s). Validated at the seam: from one
second after a trip start, `win.sd` median **2.97** against the `asd` **2.92**
that fired it. Second 0 reads 0 because the window is cleared at the transition,
and is dropped.

`replay.py` follows every run the baseline cut short into the recording it
opened. With the continuation, `streak 5s` scores **42 false starts against 52** —
a 19 % reduction, not a 97 % one.

## Ground truth

Mechanical, from the log itself: a recording that went somewhere (`net` ≥ 100 m,
the `minTripNet` the discard rule already uses, or `dist` ≥ 500 m) is a
**journey** — the start was justified, whatever the mode of travel. The start
path is not the layer that separates a bicycle from a car or a walk (L-100), so
labelling a town drive a false start would be scoring it against a job it does
not have. Everything else is a **phantom**: the rider did not travel.

No hand labelling, so re-running it on a new corpus needs no maintainer input.

## Reading the output

Two columns matter and they trade against each other: `departs` (how many of the
journeys the rule still starts) and `/24h` (false starts per day at rest, over
the observed at-rest evaluation time). Latency is measured from the instant the
3-second rule fired, so it is the delay a candidate *adds* — which the pre-trip
back-date is supposed to pay back, and currently cannot (L-110).
