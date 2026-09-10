# T053 — A veto that records instead of deleting

Date opened: 2026-09-10. Status: ⏳ **written and green (810 tests); the device run is
outstanding.**
Owner findings: **L-106**, **L-107** (`tasks/LEDGER.md` §12).
Undoes the destructive half of T051 and the whole of T052 §3.1; leaves T052 §3.2 and §3.3 alone.
Sixth in the line T048 → T049 → T050 → T051 → T052 → T053, and the one that closes the speed axis.

---

## 1. What happened

2026-09-09 evening and the night after, three sporting rides on **1.0.0+15** — the first build
carrying T052 — recorded in parallel on a Karoo. One verbose log,
`autoride-audit-20260910-0329.ndjson.gz`, and three FIT files. Clock offset 32 ms, so the two
traces are directly comparable.

**AutoRide tracked all three correctly** — distances within 0.6-4 % of the FIT, peak speeds within
0.3 km/h — **and then deleted two of them, 71.8 km, as motor vehicles.** The 64.5 km ride was cut
into seven fragments first, each refused separately.

---

## 2. Why the axis cannot be rescued

T051 chose speed because motion could not tell a car from a bicycle (L-100). T052 kept that choice
and moved the live arm to 50 km/h, on the reasoning that no cyclist holds 50. The FIT files say
otherwise, and they say it about every statistic the veto could read:

| recording | measured fixes | ≥ 35 km/h | share | max measured |
|---|---|---|---|---|
| 2026-09-07 drive to the shops | 37 | 10 | 27.0 % | **39.3** |
| 2026-09-09 morning commute | 42 | 6 | 14.3 % | 39.9 |
| 2026-09-09 evening commute | 38 | 0 | 0.0 % | 28.1 |
| night ride (trip 66, kept) | 381 | 35 | 9.2 % | 46.6 |
| sporting ride #1 (trip 51) | 354 | 98 | **27.7 %** | 46.7 |
| sporting ride #2 (trips 52-58) | 2 800 | 1 554 | **55.5 %** | **59.9** |

* **The car has the lowest maximum in the corpus.** Every ride out-peaks it.
* **The car's share is indistinguishable from a real ride's** — 27.0 % against 27.7 %.
* **The big ride is above the live threshold too**: 1.8 % of its samples exceed 50 km/h.

There is no ordering of these recordings by measured speed that puts the drive on one side and the
rides on the other. The axis is not mis-thresholded; it is **inverted**, because a town car is slow
with bursts and a sporting cyclist is fast continuously.

**And that closes the speed axis for good** — the maintainer's decision, recorded so it is not
reopened: what will eventually tell these modes apart is **the inertial unit** (the T034 training
capture feeding a classifier), not a threshold. `vehicleSpeedKmh` and `vehicleSpeedMinShare` are
not to be recalibrated again.

---

## 3. What to change

### 3.1 The veto records evidence; it never decides (L-106)

* `Trip` gains **`suspectedVehicle`**, persisted (schema v4).
* `Trip.discardReason` **loses its `vehicle` arm**. A recording made in a car is kept like any
  other, and judged on `dur` / `pts` / `still` alone.
* `TripRecorderService._watchForVehicle` **no longer ends the recording**. The live arm was the
  thing that fragmented a 64.5 km ride into seven, and ending a ride early is a destructive act
  taken on a handful of fixes — the same objection as the discard, one step smaller.
* At the stop, `suspectedVehicle` is set from `VehicleSpeedWatch.looksLikeVehicle`. `vfx`/`vmf`
  already ride on every ending and stay.
* History shows a badge on a flagged trip so a real drive is one tap to delete.

**What dies with it**, rather than being left as dead weight: `vehicleLiveSpeedKmh` (added
yesterday, refuted today), `vehicleSustainSeconds`, `vehicleSpeedWindowFixes`,
`vehicleSpeedMinFixes`' live role, `VehicleSpeedWatch.isVehicleNow` / `hasFired` / `_recent`, and
`vehicleCooldownPeriodSeconds` with its arming — a discard reason that no longer exists cannot arm
a cooldown. `vehicleSpeedKmh` and `vehicleSpeedMinShare` survive as what produces the **flag**.

The `veh` audit line survives with a new action: `{a:"flag"}` at the ending, not `{a:"fire"}` mid
-ride.

### 3.2 L-107 goes away with it

The cooldown is armed only when the end-of-ride arm fires, never when the live arm does —
`_watchForVehicle` calls `stopRecording()` directly and bypasses `_finalizeAndStopTrip`, where the
arming lives. That is why trips 53, 54 and 55 restarted 21-26 s after the previous refusal. Removing
the live arm and the `vehicle` discard reason removes both the defect and its subject.

Recorded rather than fixed in place, because the fix is the deletion. **The signature was already
in §11's log** — trip 30 discarded 08:40:03, trip 31 started 08:40:15 — and was read past.

---

## 3bis. What shipped

| | |
|---|---|
| `Trip.suspectedVehicle` | new field, persisted as `trips.suspected_vehicle` INTEGER NOT NULL DEFAULT 0 (schema **v4**) |
| `Trip.discardReason` | the `vehicle` arm and the `vehicleEvidence` parameter are **gone** |
| `TripRecorderService._watchForVehicle` | one line — it feeds the watch and returns. No `stopRecording()` |
| `VehicleSpeedWatch` | the live arm deleted: `isVehicleNow`, `hasFired`, `_recent` and `_SpeedSample` are gone; `looksLikeVehicle` is the share arm alone |
| `AppConstants` | `vehicleLiveSpeedKmh`, `vehicleSpeedWindowFixes`, `vehicleSustainSeconds`, `vehicleCooldownPeriodSeconds` deleted; `vehicleSpeedKmh`, `vehicleSpeedMinFixes`, `vehicleSpeedMinShare` kept as the flag's |
| the coordinator's vehicle cooldown | deleted with the discard reason it keyed on (L-107) |
| `veh` audit line | `{a:"flag"}` at the ending, never `{a:"fire"}` mid-ride; `k.vehWin`/`vehSec`/`vehCool`/`vehLiveKmh` dropped from the header |
| History | a second `StatusBadge` — "Vehicle?", `Icons.directions_car`, `AppColors.error` — beside the activity badge, in a `Wrap` so the pair survives a narrow screen |
| Trip detail | a `Speed profile: Looks like a vehicle` row, shown only when flagged |

`flutter analyze` clean, **810 tests** (806 → 810), including a v3→v4 migration test, a v1→v4
one-hop, a `suspectedVehicle` round-trip through the shipped schema, and two widget tests for the
badge.

One test was rewritten to assert the truth rather than the assumption: **the 2026-09-09 descent,
read on its own, does raise the flag** — six of thirteen measured fixes, 46 %. That is the point of
never ending a recording early. Truncating a ride manufactures the verdict; the same descent inside
its own commute reads 14.3 %.

---

## 4. Acceptance

1. A sporting ride is **one trip, kept**, whatever its speed. The 64.5 km ride is the test case.
2. A drive is **kept and flagged**, and the badge is visible in History.
3. No `veh {a:"fire"}` line exists any more; `veh {a:"flag"}` appears on the drive's ending.
4. A trip recorded before the migration reads back with `suspectedVehicle` false, not null.
5. Unit tests: `discardReason` never answers `vehicle`; the recorder flags without stopping; the
   schema round-trips the new column; the v3→v4 migration preserves existing rows.

---

## 5. Not changed

* **T052 §3.2** (`minTripLoopDistanceMeters`) and **§3.3** (`noProgressStopTimeout`) — both held
  across this run, and neither depends on the veto.
* **`vehicleSpeedKmh` (35) and `vehicleSpeedMinShare` (0.25)** — kept as the flag's thresholds. They
  will over-flag a sporting rider, and that is now a badge rather than a deletion. Tuning them is
  explicitly out of scope (§2).
