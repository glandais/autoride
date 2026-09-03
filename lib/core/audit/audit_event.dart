import 'dart:convert';

/// The event type vocabulary (`e`) and the line encoder.
///
/// One event is one flat JSON object on one line. `t` and `e` come first
/// because a `Map` literal preserves insertion order through `jsonEncode`, so
/// `grep '"e":"trip"'` stays usable on the exported file without jq.
///
/// Keys are short on purpose. The full names live in
/// `.claude/skills/autoride-audit-log/SKILL.md`, and the exported header
/// carries the schema version so an old file stays readable.
abstract final class AuditEvent {
  // --- Application-level -----------------------------------------------
  /// File/session header: build, device, timezone, active thresholds.
  static const String header = 'hdr';

  /// App lifecycle change. `st` = resumed|inactive|paused|hidden|detached.
  static const String lifecycle = 'app';

  /// Whether the pipeline is allowed to run. `k` names the gate.
  ///
  /// `k` = autoDetection: `en` the user's setting, `loc` the location
  /// permission, `onb` onboarding completion, `go` the resulting verdict.
  ///
  /// `k` = background: what the OS actually grants for background location —
  /// `alw` "Always" / "Allow all the time", `acc` = precise|reduced, `issue`
  /// the blocking one of the two (null when all is well). `loc` alone cannot
  /// answer this: it folds iOS "While Using" into "granted", and "While Using"
  /// is exactly the setting under which iOS kills the process a few minutes
  /// after the app is backgrounded.
  static const String permission = 'perm';

  /// A user setting changed. `k`, `o` (old), `n` (new).
  static const String setting = 'set';

  /// The log talking about itself.
  ///
  /// `a` = overflow, with `n` lines dropped by the buffer backstop; or
  /// `a` = purge, with `n` rows the retention bounds deleted and `why` =
  /// age|rows|bytes naming the bound that bit. A purge used to be silent by
  /// the L-077 design, which is how the 2026-09-02 Pixel file lost its own
  /// header, `sess start` and `perm` lines with nothing to say so (L-085).
  static const String audit = 'aud';

  /// Wall-clock vs monotonic clock pair, re-emitted when they drift apart.
  static const String clock = 'clk';

  // --- Detection session ------------------------------------------------
  /// Coordinator session. `a` = start|stop|suspend.
  static const String session = 'sess';

  /// Trip state machine transition. `f` (from), `to` — the union case names.
  ///
  /// The *reason* is not carried here: it is whatever event immediately
  /// precedes the transition (`start`, `stop`, `dto`, `gpsw fire`).
  static const String stateChange = 'st';

  /// Motion-gated GPS gate. `a` = open|close|sched|cancel, `why`, `in` (s).
  static const String gate = 'gate';

  /// A location fix. `lat`, `lon`, `ac` (m), `sp` (m/s), `al`, `hd`, and `gt`
  /// — the provider's own timestamp, which is what a Strava FIT aligns to.
  ///
  /// `sp` is always the number the OS reported, including the zeroes iOS
  /// delivers mid-ride. `dsp` (m/s) is present only on the fixes where T048
  /// derived a speed from the displacement since the previous fix and the
  /// pipeline used *that* instead — so `count(dsp) / count(fix)` is how much of
  /// a run's speed evidence the provider failed to supply.
  static const String fix = 'fix';

  /// Liveness proof. `n` ticks, `mn` motion samples, `dr` samples dropped by
  /// the rate hold, `fn` fixes, `dt` ms, and `hz` — the sampling rate the power
  /// mode in force asks for.
  ///
  /// Without it a gap in the timeline is ambiguous: the OS suspended the
  /// process, or the log lost its buffer to a kill. Those are opposite
  /// conclusions, and items 3 and 8 of the T041 checklist turn on which.
  ///
  /// `hz` sits next to `mn` because the sampling period is a request the OS
  /// rounds to a rate of its own. Since T045 the pipeline holds itself to `hz`
  /// by dropping the surplus, so it takes all three: `mn / (dt / 1000)` is what
  /// the pipeline really ran at, `(mn + dr) / (dt / 1000)` is what the OS
  /// really delivered, and only that second figure can still be compared with
  /// `hz` the way L-086 was found.
  static const String heartbeat = 'hb';

  // --- Detectors ---------------------------------------------------------
  /// Trip-start evaluation. `c` confidence, `n` consecutive, `go`, `spk` km/h,
  /// `vt`.
  ///
  /// `vt` is T048's verdict on the fix `spk` came from: false means the fix was
  /// too coarse (`k.spAcc`) or too old (`k.spAge`) for its speed to be believed,
  /// so `c` is a motion-only score and `spk` did not enter it (L-088, L-089).
  /// Absent when there was no fix at all. Reading `c` against `k.wMot`/`k.wSpd`
  /// without it gives the wrong reconstruction of the arithmetic.
  static const String startEval = 'start';

  /// Detection window timed out. `el` seconds spent in `Detecting`.
  static const String detectionTimeout = 'dto';

  /// Start cooldown. `a` = arm|expire, `d` seconds.
  static const String cooldown = 'cool';

  /// Stationary window verdict (verbose). `sd`, `gy`, `sta`, `src`, `spk`.
  static const String window = 'win';

  /// 1 Hz sensor aggregate (verbose). Never raw 50 Hz samples.
  static const String sensors = 'sens';

  /// Trip-stop decision. `d` = continue|pause|stop, `cs`, `cm`, `so`.
  ///
  /// `so` is the detector's clock: seconds since the **stationary onset**. It
  /// is deliberately not the same number as the trip's `pau`, which the
  /// recorder counts from the state machine's *pause transition* — and that
  /// only happens `minPause` seconds after the onset. A ride reporting `so`
  /// 299 and `pau` 269 is one pause seen by two clocks, not a discrepancy
  /// (L-086); the key was renamed from `pd` at schema 2 to say so.
  static const String stopEval = 'stop';

  /// Resume evaluation while paused. `go`, `cm` (consecutive movement
  /// detections), `mv` (ms of *continuous* movement so far — the quantity the
  /// resume decision is actually made on, against `k.resume`), `so` (seconds
  /// since the stationary onset — see [stopEval]).
  static const String resumeEval = 'res';

  // --- Training capture (T034) -------------------------------------------
  /// One second of raw motion samples, at capture level (`lvl` 2).
  ///
  /// The axes the diagnostic [sensors] aggregate throws away, batched into
  /// parallel arrays so a 50 Hz stream costs one row a second instead of
  /// fifty: `hz` the rate asked for, `n` the samples actually kept, then
  /// `ax`/`ay`/`az` (m·s⁻²) and `gx`/`gy`/`gz` (rad·s⁻¹), each of length `n`
  /// and in sample order.
  ///
  /// `n` is not always `hz`: the OS rounds the requested sampling period and
  /// the T045 rate hold drops the surplus, so the count travels with the line
  /// rather than being assumed from it. `t` is the instant the line was
  /// flushed — the end of its window, not the start.
  static const String rawMotion = 'raw';

  /// Ground truth for the capture that follows or precedes it (`lvl` 2).
  ///
  /// `a` = start|stop, `act` = bike|car|walk|still|other, `sess` the capture
  /// session id (the session's start, in epoch ms). Emitted `critical` so the
  /// label reaches the disk before the window it opens: a corpus whose label
  /// was lost to a kill is worse than no corpus, because it is silently
  /// mislabelled by the session before it.
  static const String label = 'lbl';

  // --- Trip lifecycle ----------------------------------------------------
  /// `a` = start|pause|resume|stop|discard, plus the finalized metrics.
  static const String trip = 'trip';

  /// Pre-trip fixes replayed and the start back-dated (L-076).
  static const String backdate = 'bdate';

  /// Pre-trip location buffer activity (verbose).
  ///
  /// `a` = add (a fix was buffered) | tail (the buffer was handed to the
  /// recorder) | clear (it was discarded), `n` the fixes involved, `sp` the
  /// span they cover in ms, `kp` how many the riding-tail cut kept, and `why`
  /// on a clear.
  static const String buffer = 'buf';

  /// GPS-loss watchdog (L-074). `a` = arm|fire|disarm, `el`, `lim`, `ref`.
  static const String gpsWatchdog = 'gpsw';

  /// Location stream resubscription after an error or completion.
  static const String gpsResubscribe = 'gps';

  /// Route point kept (normal) or dropped (verbose). `why` = acc|speed|dist.
  static const String routePoint = 'rp';

  /// A database write. `a` = points|metrics, `n`, `ms`, `ok`.
  static const String flush = 'flush';

  // --- Environment -------------------------------------------------------
  /// Power mode resolved. `m`, `b` (battery %), `ch`, `hz`, `df`, `ui`, `la`.
  static const String powerMode = 'pwr';

  /// Battery level sample, on the existing 5-minute tick.
  static const String battery = 'bat';

  /// Foreground service. `a` = start|stop|fail, `plat` = android|ios, `ex` on
  /// a fail. `plat` matters: the foreground service is an Android concept, and
  /// an `fgs start` on iOS carries no promise that the process survives
  /// backgrounding — there, only `UIBackgroundModes: location` plus an
  /// "Always" authorisation does (see the `perm` line with `k` = background).
  static const String foregroundService = 'fgs';

  /// Notification activity. `a` = show|cancel|action, `k` = fg|start|stop for
  /// a show or cancel and the action id for an action. Never the message text.
  static const String notification = 'noti';

  /// iOS background session (T046). `a` names what happened:
  ///
  ///   * `bootstrap` — the native side ran at launch, with `lr` = location|
  ///     normal. A `bootstrap {lr:"location"}` **is** the proof that iOS
  ///     relaunched a terminated process for a significant-change or visit
  ///     event; nothing else in the log can say it.
  ///   * `arm` / `disarm` — significant-change + visit monitoring, the only two
  ///     APIs that bring a killed app back. Armed exactly while automatic
  ///     detection is on, so `disarm` is what stops iOS relaunching us.
  ///   * `keepAlive` with `on` — the coarse (3 km) session that runs while the
  ///     Dart GPS gate is closed. Without it, closing the gate removed the only
  ///     CoreLocation session in the process and iOS suspended it 40 s later
  ///     (L-084); the sensors that should have re-opened the gate then stopped
  ///     arriving, which made the state absorbing.
  ///   * `coarse` (`n`, `ac`) / `visit` (`arr`, `dep`) / `err` (`ex`) —
  ///     deliveries from the native manager. These are **never** positions: a
  ///     3 km fix must not reach `_lastLocation`, the pre-trip buffer or
  ///     `GpsSpeedEstimator`. They are journalled only, as evidence that the
  ///     process is alive rather than suspended.
  ///
  /// Android emits none of these.
  static const String iosBackground = 'ios';

  // --- Diagnostics -------------------------------------------------------
  /// Bridged from [Logger]. `lv` = d|i|w|e, `tag`, `m`.
  static const String log = 'log';

  /// An error with its exception and the first stack frames.
  static const String error = 'err';

  /// Every type above, for the schema test that pins their uniqueness.
  static const List<String> all = <String>[
    header,
    lifecycle,
    permission,
    setting,
    audit,
    clock,
    session,
    stateChange,
    gate,
    fix,
    heartbeat,
    startEval,
    detectionTimeout,
    cooldown,
    window,
    sensors,
    rawMotion,
    label,
    stopEval,
    resumeEval,
    trip,
    backdate,
    buffer,
    gpsWatchdog,
    gpsResubscribe,
    routePoint,
    flush,
    powerMode,
    battery,
    foregroundService,
    notification,
    iosBackground,
    log,
    error,
  ];

  /// Longest string value kept in a field, in characters.
  ///
  /// A stack trace or a plugin error message can run to kilobytes, and one
  /// pathological line must not eat the retention budget of a whole ride.
  static const int maxStringLength = 300;

  /// Decimal places kept for latitude and longitude — ~1 cm.
  ///
  /// Not rounded further: cross-referencing a ride against a FIT recorded on a
  /// second device relies on a geometric alignment, and that is what pays for
  /// the precision.
  static const int coordinatePrecision = 7;

  /// Decimal places kept for every other double. Millimetre / mm·s⁻¹ scale,
  /// which is far below any sensor's real resolution and saves ~13 bytes per
  /// value against Dart's default `toString`.
  static const int defaultPrecision = 3;

  static const Set<String> _coordinateKeys = <String>{'lat', 'lon'};

  /// Encode one event as a single NDJSON line (no trailing newline).
  ///
  /// Never throws: a value the encoder does not understand degrades to its
  /// `toString`, and a field that cannot be encoded at all is dropped rather
  /// than losing the whole line.
  static String encode(int t, String type, Map<String, Object?> fields) {
    final map = <String, Object?>{'t': t, 'e': type};

    for (final entry in fields.entries) {
      if (entry.value == null) continue; // absent means absent — no `"x":null`
      final value = _sanitize(entry.key, entry.value);
      if (value != null) map[entry.key] = value;
    }

    try {
      return jsonEncode(map);
    } catch (_) {
      // Should be unreachable after _sanitize, but the log must degrade rather
      // than throw inside a stream callback.
      return jsonEncode(<String, Object?>{'t': t, 'e': type, 'enc': 'failed'});
    }
  }

  static Object? _sanitize(String key, Object? value) {
    return switch (value) {
      final int v => v,
      final double v => _round(key, v),
      final bool v => v,
      final String v => _truncate(v),
      final DateTime v => v.millisecondsSinceEpoch,
      final Duration v => v.inMilliseconds,
      final Enum v => v.name,
      final Iterable<Object?> v =>
        v.map((e) => _sanitize(key, e)).toList(growable: false),
      final Map<Object?, Object?> v => <String, Object?>{
        for (final e in v.entries)
          e.key.toString(): _sanitize(e.key.toString(), e.value),
      },
      null => null,
      _ => _truncate(value.toString()),
    };
  }

  /// Round a double, and drop a non-finite one entirely.
  ///
  /// `double.nan` and the infinities are not representable in JSON — encoding
  /// one throws and would cost the whole line. A sensor or a speed field can
  /// legitimately be NaN when a provider has no value.
  static Object? _round(String key, double value) {
    if (!value.isFinite) return null;
    final places = _coordinateKeys.contains(key)
        ? coordinatePrecision
        : defaultPrecision;
    final rounded = double.parse(value.toStringAsFixed(places));
    // Emit whole values as ints: "sp":3 instead of "sp":3.0, which also keeps
    // counters that happen to be doubles readable.
    if (rounded == rounded.roundToDouble() && rounded.abs() < 1e15) {
      return rounded.toInt();
    }
    return rounded;
  }

  static String _truncate(String value) {
    if (value.length <= maxStringLength) return value;
    return '${value.substring(0, maxStringLength)}…';
  }
}
