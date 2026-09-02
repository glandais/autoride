# T043 — Branch review: `feat/T043-audit-log`

Date: 2026-09-02. Scope: the 8 commits `d894124..f3c41f6` against `develop`
(46 files, +4 400 / −47). Method: three parallel Opus reviewers (port + sink +
export; pipeline instrumentation + UI; docs + privacy + skill), each finding
re-verified by reading the code, and the two top findings reproduced (a
throwaway Riverpod test for R-01, `sqlite3` for R-02).

Quality gates on the branch as reviewed: `./check.sh` green — analyze clean,
**547 tests pass**, working tree clean. Green gates are not the problem here:
the two blocking defects live in paths the in-memory test seam cannot reach.

Status legend: ☐ open · ✅ fixed (commit) · ↷ deferred (reason).

**Remediation (2026-09-02, same day):** all 24 findings fixed in three commits —
`31d8940` (instrumentation, R-07..R-09 code, R-16..R-21), `47d110c` (sink /
controller / database, R-01..R-06, R-18) and `e67077c` (skill, policy, README,
export header, R-09 docs, R-10..R-15, R-22..R-24) — plus `c13fc7d` (format).
`./check.sh` green afterwards: analyze clean, **586 tests** (547 → 586). Two
notes: R-10's export header derives `lvl` from the `AuditLog` port rather than
from the controller's protected `state` (same value); R-22's sink-side comment
(`sqlite_audit_sink.dart` `_sizeBytes`) was left as written, only the ledger
sentence was narrowed. Vocabulary additions on the way: `gate close` carries
`why`, `buf` and `noti` are emitted, `cool expire` exists, `set` covers
`auditLog`, `stop` eval `src` has a `gps+vib` arm.

---

## 1. Blocking — must be fixed before merge

| # | Sev | Where | Defect | Status |
|---|-----|-------|--------|--------|
| R-01 | **Critical** | `audit_log_controller.dart:43-47`, `:65` | `build()` watches the whole `currentSettingsProvider`, and `ref.onDispose` runs on **every rebuild**, not only on disposal. A rebuild therefore calls `_sink.close()` on the shared `keepAlive` `auditSinkProvider` instance (`_closed = true`, connection closed), then `_apply` re-reads the *same* dead sink and reinstalls it. From then on `SqliteAuditSink.write` returns at line 90 and the log records nothing, while `AuditLog.enabled` is still `true` and the settings screen shows it on. Trigger: the log is on and the user changes **any** setting — audit level normal→verbose, theme, units, sound. **Reproduced** with a container whose settings override is mutable: after one unrelated setting change, the new session header lands and the next `critical` event is silently dropped (`stats().eventCount` stays at 2). | ✅ `47d110c` |
| R-02 | **High** | `audit_database.dart:84-86` | `PRAGMA auto_vacuum = INCREMENTAL` is issued **after** `PRAGMA journal_mode = WAL`. SQLite then leaves `auto_vacuum` at 0 for the life of the file (verified: WAL-first → `PRAGMA auto_vacuum` = 0; auto_vacuum-first → 2). Consequence chain: `PRAGMA incremental_vacuum(256)` in `sqlite_audit_sink.dart:231` is a no-op, `page_count` never decreases after deletes, so once the file passes 20 MB the byte-bound loop at `:221-232` deletes 20 000 rows, re-measures the same size, and repeats until `deleted == 0` — i.e. **every purge past 20 MB empties the whole journal**, precisely on the long rides the log exists for. The unit tests cannot see this because the in-memory database has WAL inert (`test/helpers/test_database.dart:34-36`). | ✅ `47d110c` |

Fix sketch for R-01: keep the sink across rebuilds (close it only from a real
disposal, e.g. by watching `select((s) => (s.auditLogEnabled, s.auditLogLevel))`
and not registering `onDispose` inside `build`, or by giving the sink a
`reopen()`), and emit the session header only on an off→on transition (see
R-06). Fix sketch for R-02: swap the two pragma lines, and add a file-backed
`sqflite_common_ffi` test that writes past a small `auditMaxBytes` and asserts
the table is *not* emptied.

## 2. Should fix — evidence quality

These do not lose the whole log, but they make the exported evidence say the
wrong thing, which for a diagnostic journal is the failure mode the ledger
(L-077 §6) says it was designed against.

| # | Sev | Where | Defect | Status |
|---|-----|-------|--------|--------|
| R-03 | Medium | `sqlite_audit_sink.dart:116-119` | `_requestFlush` returns whenever a flush is in flight, so a `critical` event arriving during a batch commit is **not** flushed immediately — it waits for the 5 s timer, and the running flush's `pending` copy was taken before it. A process kill in that window (the exact case `critical` exists for) loses the `trip`/`st`/`err` line. Let a critical write always chain `flush()`; keep the early return only for the batch-size path. | ✅ `47d110c` |
| R-04 | Medium | `sqlite_audit_sink.dart:180` | After a successful commit, `removeRange(0, min(pending.length, _buffer.length))` removes by *count*. If the overflow backstop trimmed the buffer during the flight, the removal discards **newer, never-committed** lines, and those are not added to `_droppedSinceReport`, so the `overflow` marker under-reports the gap. Remove by a per-record sequence number instead. | ✅ `47d110c` |
| R-05 | Medium | `sqlite_audit_sink.dart:284-289` | `clear()` neither awaits nor invalidates an in-flight flush. A "Clear log" during a commit lets the flush finish, reopen a fresh database, and re-insert the "erased" batch, then drop freshly buffered lines by count (R-04). Await `_flushInFlight` and bump a generation counter the flush checks before committing. | ✅ `47d110c` |
| R-06 | Medium | `audit_log_controller.dart:51, 71` | Because `build()` watches the whole settings object, `_emitSessionHeader` runs on every settings change, despite the doc comment "a header per process launch". The skill's procedure bounds process launches by counting `hdr` events, so one launch reads as several and inverts the verdict on checklist item 8 (process death). Emit only on off→on. (Same root cause as R-01.) | ✅ `47d110c` |
| R-07 | Medium | `trip_detection_coordinator.dart:361-367` | `_closeGpsGate()` hard-codes `why: 'inactivityTimeout'`, but it is also reached from `_cleanup()` (`:966`), i.e. from `_suspendListening`, `_stopNow` and `ref.onDispose`. A gate closed by session teardown is journalled as a stationary timeout. Pass the reason as a parameter. | ✅ `31d8940` |
| R-08 | Medium | `trip_detection_coordinator.dart:220, 240-252` | `_heartbeatSince` is only reset in `startListening()` and `_emitHeartbeat()`. Enabling the log mid-session (the normal flow: start riding, then flip the switch) makes the first `hb` report `n: 1` with a `dt` of minutes — the signature the ledger defines as "the OS froze the 1 Hz timer". False positive on items 3 and 8. Reset the baseline when `AuditLog.enabled` flips. | ✅ `31d8940` |
| R-09 | Medium | `audit_event.dart:82, 107` + `SKILL.md:52, 55` | `buf` and `noti` exist in the vocabulary and are documented as live rows in the skill, but **no call site emits them** (46 `AuditEvent.` sites in `lib/`, none for `buffer`/`notification`). The pre-trip buffer is mutated at `trip_detection_coordinator.dart:620, 622, 722, 871` with no emit. Likewise `cool a:"expire"` and `aud a:"purge"/"clkjump"` are documented but never produced. An analyst filtering `e=="buf"` will read silence as "the buffer never filled". Either emit them or mark the rows "declared, not yet emitted". | ✅ `31d8940 + e67077c` |
| R-10 | Medium | `SKILL.md:19-25` vs `audit_export_service.dart:158-171` | The skill tells the analyst to read `hdr.lvl` from the file's first line, and §5 item 4 / §6 depend on it, but the **export** header never writes `lvl` (it writes `sv, app, os, dev, tz, tzn, n, from, to, exp, k`); only the per-launch header (`audit_log_controller.dart:81-92`) does. Add `lvl` to the export header and split the skill's `hdr` row into file-header vs launch-header. | ✅ `e67077c` |
| R-11 | Medium | `SKILL.md:28-63` | The event table ("the whole vocabulary") omits `clk` (`AuditEvent.clock`, emitted critically at `audit_log_controller.dart:117`), yet §4 step 1 says "compute it per segment between two `clk` events". Add a `clk` row with `wall`/`mono`/`drift`. | ✅ `e67077c` |

## 3. Docs and public claims that the branch made false

| # | Sev | Where | Defect | Status |
|---|-----|-------|--------|--------|
| R-12 | High | `README.md:361-366` | "What leaves your device — **Exactly one thing**" (map tiles) is now false: T042's FIT export and T043's log export leave via the share sheet. `privacy-policy.md` §3.2/§3.3 was updated in this branch, the README was not. Mirror §3.3 ("the only *automatic* one" + user-initiated exports). | ✅ `e67077c` |
| R-13 | High | `README.md:355-358` | "Accelerometer and gyroscope readings … are **never written to disk**" contradicts the verbose log's 1 Hz `sens` aggregate (`trip_detection_coordinator.dart:583-588`) — the very caveat `data-safety.md` §2 added. Add the same "opt-in, off by default, summaries only, never raw 50 Hz" caveat. | ✅ `e67077c` |
| R-14 | Medium | `docs/index.md:24-29` | Public landing page still says map tiles are "the one exception"; no mention of user-initiated exports. One sentence pointing at policy §3.3. | ✅ `e67077c` |
| R-15 | Medium | `privacy-policy.md` §2.5 | Discloses "notification activity" (never recorded, see R-09) and omits **altitude and heading**, which every `fix` carries (`trip_detection_coordinator.dart:609-610`). The omission is the direction that matters. | ✅ `e67077c` |

## 4. Low

| # | Where | Defect | Status |
|---|-------|--------|--------|
| R-16 | `settings_service.dart:40-64` | `_auditSettingChange` covers detection, battery mode, background location and `auditLogLevel`, but not `auditLogEnabled`. The sink is still installed at that moment, so the emit would land; without it the log simply *ends* when turned off, indistinguishable from a kill. | ✅ `31d8940` |
| R-17 | `trip_detection_coordinator.dart:425-434, 455-461` | `_stopNow()` emits `sess {a:'stop'}` then `_suspendListening()` emits `sess {a:'suspend'}` — two session events per stop; and `stop` is emitted even when `_isAnalyzing` was never true. | ✅ `31d8940` |
| R-18 | `sqlite_audit_sink.dart:93` + `audit_log_controller.dart:53-60` | The periodic flush timer is created on the first write and only cancelled in `close()`; turning the log off keeps the sink, so a 5 s timer fires for the rest of the process on the app whose thesis is battery. Cancel when the buffer empties, or `pause()` from `_apply(off)`. | ✅ `47d110c` |
| R-19 | `trip_stop_detector.dart:206-211` | `src` reports `'gps'` for the arm that actually returns `_window.isVibrationFree` — the sensors decide. Report `'gps+vib'`. | ✅ `31d8940` |
| R-20 | `audit_log_section.dart:188-189` | `ref.invalidate(auditLogStatsProvider)` after `await …clear()` has no `mounted` guard (the snackbar below it does). Leaving settings mid-delete throws on a disposed `WidgetRef`. | ✅ `31d8940` |
| R-21 | `audit_event.dart:22, 68, 84` | Doc comments for `perm`, `res` and `st` list fields that are not what is emitted (`k:'autoDetection', en, loc, onb, go` / `go, cm, pd` / `f, to`). The skill matches the emissions; the code comment is the wrong document. | ✅ `31d8940` |
| R-22 | `sqlite_audit_sink.dart:265-268`, LEDGER L-077 | Rationale "avoids DiskSpace/FileTimestamp reasoning" is half-undercut: `audit_export_service.dart:94` calls `file.length()` (a stat) and `PrivacyInfo.xcprivacy` already declares FileTimestamp (`0A2A.1`). Not a compliance gap; narrow the comment to DiskSpace. | ✅ `e67077c` |
| R-23 | `tasks/TASKS.md:462` | `Last Updated: 2026-09-01` while the T043 entry is dated 2026-09-02. | ✅ `e67077c` |
| R-24 | `CLAUDE.md` | Structure diagram and Key Files table omit `lib/core/audit/` and `lib/features/diagnostics/`. | ✅ `e67077c` |

## 5. Test gaps that let R-01 and R-02 through

- `audit_log_controller_test.dart` overrides `currentSettingsProvider` with a
  constant, so the controller is never rebuilt in any test; a test that mutates
  the settings after enabling and then asserts a later write lands would have
  caught R-01.
- `sqlite_audit_sink_test.dart:166-196`: the overflow test never asserts the
  `aud {a:"overflow"}` marker — it checks a count bound, then builds a *different*
  sink and asserts `rows()` is non-empty. There is no failed-batch-then-success
  retry test and no flush-during-flush ordering test, although L-077 names both
  as defects fixed while building the sink. The byte bound is untestable on the
  in-memory database (WAL inert), which is why R-02 survived — it needs a
  file-backed `sqflite_common_ffi` database.
- Coordinator audit group pins `sess/gate/fix/st/gpsw/start/stop/hb` and the
  disabled case, but nothing covers `gate close`, `cool`, `dto`, `trip`, `bdate`
  or `gpsw disarm`: removing any of those emits still passes.
- `audit_log_section_test.dart`'s "clear" group only asserts the dialog appears;
  tapping Delete is never exercised.

## 6. Checked and fine

- Disabled-path cost: every ≥1 Hz emitter (`fix`, `sens`, `hb`, detector evals,
  `rp keep`, `Logger._mirror`) sits behind `if (AuditLog.enabled)` /
  `AuditLog.verbose`; `emit` is a static load + null test when off, and the
  field closure is proven not to run (`audit_log_test.dart:16-45`).
- No control-flow regression in the coordinator, recorder, stop detector or
  location service: the `_stationaryVerdict` extraction is byte-for-byte the
  old arms, `location_service.dart` only hoists `_retryDelay`, and every emit is
  inserted between pure computations. `AuditLog._write` swallows sink and
  field-getter throws, so a stream callback cannot die on an emit.
- No Logger ↔ AuditLog recursion: nothing under `core/audit` or the sink logs,
  and mirrored `Logger` messages contain no coordinates.
- `flush()` chaining is correct (`identical` guard on `whenComplete`); failed
  batches are retried from the buffer; `_writtenSincePurge` is not advanced on
  failure. NDJSON validity: `jsonEncode` escapes newlines, non-finite doubles
  are dropped, strings truncated at 300.
- Export truly streams (keyset pagination, 5 000-row pages, `utf8 → gzip →
  pipe`), filename and gzip claims match the skill, `t` is wall-clock epoch ms
  as the skill says, all seven jq recipes run under jq 1.7 against real-shaped
  lines. Temp files under `<cache>/audit_exports` are never pruned — the same
  convention as the FIT exporter, so not new.
- Privacy dialog is genuinely blocking before `shareLog`, with `mounted` checks
  on every post-await context use in `_export`; its wording matches what the
  header and `fix` lines actually contain, so `data-safety.md` §3.3 holds.
  `auditLogEnabled` defaults to `false`; retention numbers in policy §6 and
  data-safety §1 match `AppConstants`.
- `debugLoggingEnabled` removal is clean (single JSON blob, unknown keys
  ignored, no live references). No new runtime dependency: the two additions
  are dev-only test seams; gzip is `dart:io`.
- Bookkeeping: TASKS.md counts (43 / 25 ✅ / 9 ⏳ / 9 ☐) are exact; L-077's
  instrumentation list matches the 46 call sites; `main.dart` emits the
  lifecycle event before the `!= resumed` early return and installs the
  controller ahead of everything it observes; background isolate emits nothing,
  so the static port being main-isolate-only is harmless.
