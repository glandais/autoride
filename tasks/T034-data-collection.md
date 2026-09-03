# T034 — Data Collection Service

**Status**: ⏳ Code complete 2026-09-03 — `./check.sh` green (738 tests). The
device run of §8 is what remains: measured MB/h, the battery note, and a
labelled bike + non-bike session read back through the audit-log skill.
**Phase**: 9.1 — Training Data Pipeline
**Dependencies**: T015 (trip recording), T017 — plus, in practice, the audit
subsystem shipped by T043/T047 (`lib/core/audit/`, `lib/features/diagnostics/`)
**Unblocks**: T035 (training data export)
**Opened**: 2026-09-03
**Estimate**: 3-4 h in `TASKS.md` — realistic at **6-8 h** with the sensor
batching and the labelling UI below.

---

## 0. The question this file answers

> *Can the existing audit system be used for T034, even if that means allowing
> more than 20 MB of storage?*

**Yes for roughly 80 % of it — and no for the sensor hot path.** The blocker is
not `AppConstants.auditMaxBytes`. Raising the byte bound alone produces a
capture that exhausts `auditMaxEvents` in about an hour, purges its own first
hour on a two-hour ride, and biases the very battery measurement the log was
built to support (`tasks/T041-device-validation.md` item 4).

The plan below **reuses the audit substrate** — sink, database, export,
consent, header — and **replaces only the sensor event**.

A first pass ships **without anonymisation** (decided 2026-09-03). See §5.

---

## 1. What the audit subsystem already provides

| T034 / T035 need | Already exists | Where |
|---|---|---|
| Buffered, non-throwing write path | `AuditSink` / `SqliteAuditSink` (batch 200, 5 s timer, 5 000-line backstop) | `core/audit/audit_sink.dart`, `diagnostics/data/services/sqlite_audit_sink.dart` |
| Isolated local store | `autoride_audit.db`, separate from the trip DB, `auto_vacuum=INCREMENTAL`, WAL, `synchronous=NORMAL` | `audit_database.dart` |
| Export to a shareable file (= most of T035) | gzipped NDJSON streamed in 5 000-row pages + OS share sheet | `audit_export_service.dart` |
| Per-line level column for filtering an export | `lvl` (0 normal, 1 verbose) — **already in the schema** | `audit_events.lvl` |
| Session metadata | `hdr`: build, device, timezone **and every active threshold** (`AuditSchema.thresholds()`) | `core/audit/audit_schema.dart` |
| Forward-compatible format | Opaque `line` column; a new event type needs **no** schema bump nor migration | `audit_schema.dart` doc comment |
| Consent plumbing | `UserSettings.dataCollectionConsent` (defaults `false`, persisted, tested) | `settings/domain/models/user_settings.dart:62` |
| Consent UI slot | Removed by T037 §5.1 with an explicit note to re-add it here | `settings/presentation/widgets/privacy_settings_section.dart:17` |
| Ride context around a window | `fix` (lat/lon 1e-7, `sp`, `dsp`, `ac`), `hb`, `pwr`, `trip`, `st`, `start` | `core/audit/audit_event.dart` |

That is the entire storage/export/consent half of T034 already built and
device-proven. None of it should be duplicated.

---

## 2. What it cannot provide as it stands

### 2.1 Sensor resolution — the real blocker

`AuditEvent.sensors` emits `am` / `gm` — two **magnitudes** — at **1 Hz**
(`_emitSensorSample`, throttled by `AppConstants.auditSensorSampleInterval`).

An activity-recognition model wants **3-axis accelerometer + 3-axis gyroscope
at 20-50 Hz**. Both dimensions are missing: the axes are collapsed into a norm
(rotation-invariant, which is convenient, but it discards the orientation
signal most classifiers use), and 1 Hz is one to two orders of magnitude below
what a windowed classifier needs.

`audit_level.dart` states the current position explicitly: *"Raw 50 Hz sensor
samples are never recorded at any level"*.

### 2.2 The cost is row count and write rate, not disk

One NDJSON line per sample at 50 Hz:

```
{"t":1756900000000,"e":"raw","ax":-0.123,"ay":9.812,"az":0.456,"gx":0.001,"gy":0,"gz":-0.002}
```

≈ 100 bytes → **~18 MB/h** and **180 000 rows/h**.

`AppConstants.auditMaxEvents` is 200 000 and `auditMaxBytes` is 20 MB: a
capture run exhausts *both* in roughly one hour, so a two-hour ride deletes its
own first hour — header included, which is exactly the failure L-085 already
recorded once. Raising only `auditMaxBytes` leaves the row bound biting first.

### 2.3 No ground truth

A training corpus needs a label (bike / car / walk / still / other). The only
label the log carries today is the output of `TripStartDetector` — i.e. the
output of the model being trained. Circular, and useless as supervision.

### 2.4 Retention semantics are wrong for a corpus

`SqliteAuditSink.purge` deletes oldest-first by age / rows / bytes. Correct for
a rolling journal; wrong for a corpus, where a labelled session must survive
until it has been exported.

### 2.5 The level scale is linear, the need is orthogonal

`AuditLogLevel` is `off → normal → verbose`. Putting capture inside `verbose`
forces every diagnostic line along with it (and vice versa). Capture has to be
a **separate axis**.

### 2.6 Capture has no session of its own

The motion stream only runs while `TripDetectionCoordinator` holds a session,
which `AutoDetectionController` starts only when auto-detection is enabled.
Negative classes — a car ride, a walk — are exactly the sessions a user may not
want auto-detection running for. See §6.6.

---

## 3. Design — reuse the substrate, replace the hot path

### 3.1 A `raw` event batched to 1 Hz, carrying arrays

One line per second holding the second's samples as parallel arrays:

```json
{"t":1756900000000,"e":"raw","hz":50,"n":50,
 "ax":[…50 values],"ay":[…],"az":[…],
 "gx":[…],"gy":[…],"gz":[…]}
```

* ~2.2 kB/s → **~8 MB/h** uncompressed, **~2-3 MB/h** gzipped.
* **1 row/s** → 3 600 rows/h, under 2 % of the current row bound.
* Fits the existing batch-200 / 5 s flush tuning with no retuning.
* `AuditEvent.encode` already sanitises `Iterable` element-wise and rounds
  doubles to `defaultPrecision` (3 dp) — no encoder change needed.
* `hz` and `n` travel with the line because the OS rounds the requested
  sampling period and the T045 rate hold drops the surplus; `n` is what was
  actually kept, and it is not always `hz`.

Implementation: a fixed-size accumulator in `TripDetectionCoordinator`
(alongside `_heartbeatMotionSamples`), flushed on a wall-clock second boundary
and on session close. Never allocate per sample when capture is off — the
`AuditLog` doc comment's rule about capturing closures applies verbatim.

### 3.2 A third level value, `lvl = 2`

The `lvl` column already exists and is already exported/filterable, so capture
lines cost **no migration**:

* `lvl 0` normal, `lvl 1` verbose, **`lvl 2` capture**.
* `AuditLog` gains `emitCapture(...)`, and its `bool _verbose` becomes an
  `AuditLogLevel _level` plus an independent `bool _capture`. `emit` returns
  early when `_level == off`, so capture can run with diagnostics off.
* `AuditLog.enabled` currently means "a sink is installed"; with capture able to
  install a sink on its own, every existing guard `if (AuditLog.enabled)` must
  become a level test. **This is the one non-trivial refactor in the task** and
  it touches every 1 Hz+ emit site.
* `AuditLogController` installs the sink when
  `auditLogLevel != off || captureEnabled`.

### 3.3 A `lbl` event and a labelling control

`{"t":…,"e":"lbl","a":"start|stop","act":"bike|car|walk|still|other"}`, emitted
`critical: true` so it reaches disk before the window it opens.

UI: a compact activity selector in the diagnostics screen (next to
`audit_log_section.dart`), visible only when capture is on. Live labelling
only — no post-hoc re-labelling of stored trips in this task.

### 3.4 Retention: keep until exported

Capture rows (`lvl = 2`) get their own bounds, evaluated separately from the
journal's in `SqliteAuditSink.purge`:

* their own byte budget, `AppConstants.captureMaxBytes` — **256 MB** proposed
  (≈ 30 h of capture at §3.1's rate), to be confirmed on device;
* deleted by *labelled session*, oldest first, never mid-session;
* never counted against `auditMaxEvents` / `auditMaxBytes`, and the journal's
  purge must never delete a capture row (nor the reverse).

A capture session that has been exported is eligible for deletion first; one
that has not is deleted only when the byte budget forces it, and that deletion
emits an `aud {a:"purge", why:"capture"}` line so the loss is visible (L-085's
lesson).

### 3.5 New constants

In `AppConstants`, next to the existing `audit*` block:

| Constant | Proposed | Note |
|---|---|---|
| `captureMaxBytes` | `256 * 1024 * 1024` | separate budget, §3.4 |
| `captureBatchDuration` | `Duration(seconds: 1)` | the array window, §3.1 |
| `captureMaxSamplesPerLine` | `64` | backstop if the OS over-delivers |
| `captureRetention` | `Duration(days: 30)` | vs the journal's 7 |

`AuditSchema.thresholds()` is pinned by
`test/core/audit/audit_event_test.dart` for **detection** constants only; these
are storage constants and do not belong in the header. Confirm against that
test when adding them.

---

## 4. Byte budget, for the record

| Scheme | Rate | Bytes/h | Rows/h | Verdict |
|---|---|---|---|---|
| `sens` today | 1 Hz, 2 magnitudes | ~0.2 MB | 3 600 | unusable for ML (§2.1) |
| One line per sample | 50 Hz | ~18 MB | 180 000 | exhausts both bounds in ~1 h |
| **`raw` batched (§3.1)** | 50 Hz, 1 line/s | **~8 MB** (~2-3 MB gzipped) | **3 600** | ships |

A 2 h ride is ~16 MB of capture; 256 MB holds about 30 h of labelled sessions.

---

## 5. No anonymisation in the first pass

Decided 2026-09-03. Consequences, stated so they are not rediscovered later:

* **Technically nothing to build.** Coordinates are already kept at
  `AuditEvent.coordinatePrecision` (1e-7, ~1 cm) and the file stays on device
  behind the existing share sheet. Capture inherits that.
* **The data is personal data.** A `raw` + `fix` + `lbl` corpus is a
  precisely-located movement history. It must stay local: **no upload, no
  automatic transmission, no third-party SDK** in this task. Sharing is a
  deliberate user gesture through the OS share sheet, exactly as the audit
  export already works.
* **Declarations must be updated** before any build shipping capture reaches a
  store: `store-metadata/data-safety.md` §7.1 (already written as the entry
  point for T034 — see `tasks/T037-privacy-policy.md` §1) and the privacy
  policy's data-collection section.
* **Consent copy must be honest.** T037 §5.1 removed the old toggle precisely
  because it described behaviour that did not exist. The re-added toggle must
  say what actually happens: raw sensor data and precise positions are recorded
  on this device, kept until you delete or export them, and never sent
  anywhere.
* Anonymisation (coordinate truncation, start/end clipping, session
  pseudonymisation) becomes a prerequisite of **any** future upload path, and
  should be tracked as its own task then.

---

## 6. Work breakdown

### 6.1 Vocabulary — `lib/core/audit/audit_event.dart`
Add `raw` and `lbl`, document their fields, append both to `all` (the schema
test pins uniqueness). No `AuditSchema.version` bump: adding event types is
explicitly outside the bump rule.

### 6.2 Emit API — `lib/core/audit/audit_log.dart`
`_verbose` → `_level` + `_capture`; add `emitCapture`; add `captureEnabled`.
Audit every existing `AuditLog.enabled` guard (§3.2) — `grep -rn
'AuditLog.enabled' lib/`.

### 6.3 Sink & retention — `sqlite_audit_sink.dart`
Split `purge` into a journal path (`lvl < 2`) and a capture path (`lvl = 2`)
with the §3.4 rules; report a capture purge through `AuditEvent.audit`.

### 6.4 Producer — `trip_detection_coordinator.dart`
Per-second accumulator + flush; leave `_emitSensorSample` untouched (it stays
the verbose diagnostic aggregate — it answers a different question).

### 6.5 Consent & control
Re-add the toggle to `privacy_settings_section.dart` wired to
`dataCollectionConsent`, with §5 copy. Capture is off unless consent is granted
**and** capture is enabled.

### 6.6 Capture session lifetime (§2.6)
Decide and implement one of:
* **(a)** capture requires auto-detection to be running — simplest, but it
  cannot record a car ride with detection off;
* **(b)** capture holds its own coordinator session, started by the labelling
  control — more code, but it is what makes negative classes collectable.
**(b) is recommended**; the corpus is worth little without non-cycling classes.

### 6.7 Labelling UI (§3.3)
Activity selector in the diagnostics screen, capture-only.

### 6.8 Documentation
`.claude/skills/autoride-audit-log/SKILL.md` — `raw` and `lbl` field reference
plus jq recipes for turning a session into windows;
`store-metadata/data-safety.md` §7.1; `CLAUDE.md` if the level model changes
shape.

### 6.9 Tests
Encoder round-trip for array fields; the per-second batcher (boundary, session
close, `n` != `hz`); capture purge never touching journal rows and vice versa;
`AuditLog` level matrix (capture on / diagnostics off, and every other
combination); consent gating.

---

## 7. What this leaves for T035

Very little, which is the point: `AuditExportService` already streams gzipped
NDJSON with paging and a share sheet. T035 becomes a `lvl`/`type` filter, a
session selector, and — if a CSV is genuinely wanted — a flattening pass that
expands the §3.1 arrays back to one row per sample at export time, where the
cost is paid once and off the hot path.

---

## 8. Definition of done

- [ ] `raw` batched at 1 Hz with 3-axis accel + gyro, `lvl = 2`
- [ ] `lbl` events with a working activity selector
- [ ] Capture axis independent of `AuditLogLevel`; every `AuditLog.enabled`
      guard reviewed
- [ ] Capture retention separate from the journal's, purge reported
- [ ] Consent toggle re-added with copy matching real behaviour (§5)
- [ ] `./check.sh` green
- [ ] Device run: a labelled bike session and a labelled non-bike session
      exported and read back through the audit-log skill
- [ ] Measured MB/h on device, compared against §4's ~8 MB/h projection
- [ ] Battery drain during capture noted — and a note that T041 item 4's
      measurement must be taken with capture **off**
- [ ] `store-metadata/data-safety.md` §7.1 updated
- [ ] `tasks/TASKS.md` updated

---

## 9. Questions, answered 2026-09-03

1. **Sampling rate: fixed, and capture forces `PowerMode.normal`.** (1 and 2
   together.) A model trained on windows that silently drop from 50 Hz to 20 Hz
   with the battery learns the battery, not the activity.
   `CurrentPowerMode.build()` returns `PowerModeConfig.normal` for as long as a
   capture session runs. The cost is a `normal`-mode battery draw during
   capture, which is why item 4 of the T041 checklist must be measured with
   capture **off** — already in §8.
2. **No magnetometer.** Accelerometer and gyroscope only, i.e. `MotionData` as
   it stands: no model change, no extra battery, and the NDJSON format takes a
   new channel later without a migration.
3. **256 MB confirmed** as `AppConstants.captureMaxBytes`, still to be checked
   against real storage pressure on the device run.

### What was decided during implementation, and is not in §3

* **The producer is not in `TripDetectionCoordinator`** (§6.4 proposed it, §6.6
  option (b) is what won). `CaptureController` holds its own subscription to
  `motionDataStreamProvider` — the same shared stream, one extra listener — so a
  car journey or a walk can be recorded with automatic detection **off**. Going
  through the coordinator would have meant either no negative classes or trip
  detection inventing bike trips out of a car journey.
* **`AuditLog.emitAlways`** was added alongside `emitCapture`. The session
  header, the `clk` pair and the lifecycle flush must exist whenever *anything*
  is recording, and `emit` drops them when the journal is off — a capture-only
  file would have had no `hdr`, i.e. no thresholds and no timezone.
* **Schema v2**, not "no migration". Adding the event types needed none, but
  deleting a *labelled session whole* needs a grouping key: `audit_events.sess`
  plus a `capture_sessions` table (id = the session's start in epoch ms, so the
  synchronous `write` can stamp rows without awaiting an AUTOINCREMENT).
* **Both byte bounds now measure stored content**, not the file's page count.
  Once the two classes share a file, a page count cannot be attributed to
  either — a 200 MB corpus would have made the journal delete itself for ever
  without the file shrinking below 20 MB.
* **The journal export excludes `lvl = 2`** and capture has its own
  `autoride-capture-*.ndjson.gz`. Otherwise every diagnostic export would have
  become a hundred-megabyte transfer of data nobody asked for.
* **The foreground service covers capture** (`AutoDetectionController`): without
  it Doze suspends the process with the screen off, and a corpus recorded with
  the screen on is a corpus of a phone in a hand, not a phone in a pocket.
