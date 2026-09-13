# T034 — Data Collection Service

**Status**: ⏳ Code complete since 2026-09-03, `./check.sh` green. Everything in
the design (§1–§7) and the work breakdown (§6) below has shipped and is
verified against the current code (`capture_controller.dart`,
`capture_session.dart`, `capture_section.dart`, `audit_event.dart`'s `raw`/`lbl`
vocabulary, the `AppConstants.capture*` constants, `AuditLog`'s
`emitCapture`/`captureEnabled`/`emitAlways`, the sink's split journal/capture
purge, the re-added consent toggle, `store-metadata/data-safety.md` §7.1). What
remains is purely the **device run**: measured MB/h against the ~8 MB/h
projection, a battery note, and a labelled bike + non-bike session exported and
read back through the audit-log skill — see "Remaining work" below, copied
verbatim from the original plan's §8/§9.

---

## What shipped

**Why:** The existing audit substrate (sink, database, export, consent, header)
already covered ~80% of a training-data pipeline; only the sensor hot path,
ground truth, and retention semantics needed something new. Rather than build
a parallel system, T034 replaced only those pieces and reused the rest.

**Durable decisions:**
- **No anonymisation in this first pass** (decided 2026-09-03, still true): the
  corpus is personal, precisely-located movement data; it stays local
  (no upload, no automatic transmission, no third-party SDK), shared only
  through a deliberate OS share-sheet gesture. Anonymisation becomes a
  prerequisite of any future upload path, tracked as its own task then.
- **Capture is a third, orthogonal axis** (`lvl = 2`), independent of the
  linear `AuditLogLevel` (off/normal/verbose) — so training capture can run
  with diagnostics off and vice versa. `AuditLog.enabled` was split into a
  level test plus a separate `captureEnabled` check everywhere it was used.
- **The producer is `CaptureController`, not `TripDetectionCoordinator`** — it
  holds its own subscription to the shared `motionDataStreamProvider`, so a
  car journey or a walk can be recorded with auto-detection off. Going through
  the coordinator would have meant no negative classes, or trip detection
  inventing bike trips out of a car journey.
- **Capture retention is separate from the journal's** and evaluated
  independently in `SqliteAuditSink.purge`: its own byte budget
  (`AppConstants.captureMaxBytes`, 256 MB), deleted by whole labelled session
  (never mid-session), exported sessions eligible for deletion first, and any
  forced deletion of an unexported session emits an `aud {a:"purge",
  why:"capture"}` line so the loss is visible.
- **Sampling rate is fixed during capture**: a capture session forces
  `PowerMode.normal` so a model never trains on windows that silently drop
  rate with the battery. This means T041 item 4's battery measurement must be
  taken with capture **off**.
- **Schema v2** (not "no migration" as first assumed): deleting a labelled
  session whole needs a grouping key, so `audit_events.sess` plus a
  `capture_sessions` table were added.

**Delivered:** `lib/features/diagnostics/data/services/capture_controller.dart`,
`lib/features/diagnostics/domain/models/capture_session.dart` (+ `.freezed.dart`),
`lib/features/diagnostics/presentation/widgets/capture_section.dart` (+ `.g.dart`),
`lib/core/audit/audit_event.dart` (`raw`, `lbl` event types),
`lib/core/audit/audit_log.dart` (`AuditLogLevel` + independent `_capture` flag,
`emitCapture`, `emitAlways`, `captureEnabled`, `captureSession`),
`lib/core/constants/app_constants.dart` (`captureMaxBytes`,
`captureBatchDuration`, `captureMaxSamplesPerLine`, `captureRetention`),
`lib/features/diagnostics/data/services/sqlite_audit_sink.dart` (split
`_purgeJournal`/`_purgeCapture`, `sess` column),
`lib/features/diagnostics/data/services/audit_export_service.dart` (`lvl = 2`
capture export separate from the journal export),
`lib/features/settings/presentation/widgets/privacy_settings_section.dart`
(re-added consent toggle), `store-metadata/data-safety.md` §7.1,
`.claude/skills/autoride-audit-log/SKILL.md` (`raw`/`lbl` field reference + jq
recipes).

**Pitfalls:**
- The journal export excludes `lvl = 2`; capture has its own
  `autoride-capture-*.ndjson.gz`, or every diagnostic export would become a
  hundred-megabyte transfer nobody asked for.
- Both byte bounds (journal and capture) measure *stored content*, not the
  file's page count — once the two classes share one SQLite file, a page count
  can't be attributed to either.
- The foreground service covers capture too: without it, Doze suspends the
  process with the screen off, and a corpus recorded with the screen on is a
  corpus of a phone in a hand, not a phone in a pocket.
- Capture is off unless `dataCollectionConsent` is granted **and** capture is
  explicitly enabled — both gates, not either.

---

## Remaining work

The following is copied verbatim from the original plan (§8 Definition of
done, and §9 item 3) — it is the only part of T034 not yet done.

### Definition of done (§8)

- [x] `raw` batched at 1 Hz with 3-axis accel + gyro, `lvl = 2`
- [x] `lbl` events with a working activity selector
- [x] Capture axis independent of `AuditLogLevel`; every `AuditLog.enabled`
      guard reviewed
- [x] Capture retention separate from the journal's, purge reported
- [x] Consent toggle re-added with copy matching real behaviour (§5)
- [x] `./check.sh` green
- [ ] Device run: a labelled bike session and a labelled non-bike session
      exported and read back through the audit-log skill
- [ ] Measured MB/h on device, compared against §4's ~8 MB/h projection
- [ ] Battery drain during capture noted — and a note that T041 item 4's
      measurement must be taken with capture **off**
- [x] `store-metadata/data-safety.md` §7.1 updated
- [x] `tasks/TASKS.md` updated

### Outstanding confirmation (§9 item 3)

3. **256 MB confirmed** as `AppConstants.captureMaxBytes`, still to be checked
   against real storage pressure on the device run.

### Byte budget projection, for the device run to confirm against

| Scheme | Rate | Bytes/h | Rows/h | Verdict |
|---|---|---|---|---|
| `sens` today | 1 Hz, 2 magnitudes | ~0.2 MB | 3 600 | unusable for ML |
| One line per sample | 50 Hz | ~18 MB | 180 000 | exhausts both bounds in ~1 h |
| **`raw` batched** | 50 Hz, 1 line/s | **~8 MB** (~2-3 MB gzipped) | **3 600** | ships |

A 2 h ride is ~16 MB of capture; 256 MB holds about 30 h of labelled sessions
— the device run is what confirms this against real storage pressure rather
than the arithmetic above.
