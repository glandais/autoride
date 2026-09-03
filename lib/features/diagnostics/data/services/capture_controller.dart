import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:autoride/core/audit/audit_event.dart';
import 'package:autoride/core/audit/audit_log.dart';
import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/core/utils/logger.dart';
import 'package:autoride/features/diagnostics/data/services/audit_log_controller.dart';
import 'package:autoride/features/diagnostics/domain/models/capture_session.dart';
import 'package:autoride/features/settings/data/services/settings_service.dart';
import 'package:autoride/features/trip_detection/data/services/sensor_service.dart';
import 'package:autoride/features/trip_detection/domain/models/motion_data.dart';

part 'capture_controller.g.dart';

const _logger = Logger('CaptureController');

/// Owns a training-capture session (T034): the label, the motion subscription
/// and the per-second batching of raw samples.
///
/// ## Why it does not go through `TripDetectionCoordinator`
///
/// The coordinator only runs while automatic detection is on, and the negative
/// classes this corpus needs most — a car journey, a walk — are exactly the
/// sessions a rider does not want trip detection running for. Recording them
/// through the coordinator would either require detection to be on (and invent
/// bike trips out of a car journey) or leave the corpus with nothing but bike
/// data, which is a corpus that cannot teach a classifier anything.
///
/// So capture holds its own subscription to [motionDataStreamProvider]. That is
/// the same shared stream the coordinator consumes — subscribing twice costs
/// one extra listener, not a second sensor subscription — so the two run side
/// by side when detection happens to be on, and capture runs alone when it is
/// not.
///
/// ## What it costs
///
/// One row per second holding that second's samples as parallel arrays:
/// ~2.2 kB/s, so ~8 MB an hour uncompressed and ~2-3 MB gzipped, at 3 600
/// rows/h. One row *per sample* would be ~18 MB and 180 000 rows an hour, which
/// exhausts both journal bounds in about an hour — a two-hour ride would delete
/// its own first hour, header included (L-085).
@Riverpod(keepAlive: true)
class CaptureController extends _$CaptureController {
  void Function()? _closeMotionSubscription;

  /// The samples of the second being accumulated. Fixed-capacity lists reused
  /// across windows: at 50 Hz this path runs 50 times a second, and allocating
  /// six growable lists per window is exactly the kind of cost the audit log is
  /// not allowed to charge to the pipeline it observes.
  final List<double> _ax = <double>[];
  final List<double> _ay = <double>[];
  final List<double> _az = <double>[];
  final List<double> _gx = <double>[];
  final List<double> _gy = <double>[];
  final List<double> _gz = <double>[];

  /// End of the window being filled. Advanced by whole [captureBatchDuration]
  /// steps rather than reset to "now" on every flush, so the windows tile the
  /// session instead of drifting later by the lateness of each sample.
  DateTime? _windowEnd;

  @override
  CaptureSession? build() {
    ref.onDispose(_teardown);
    return null;
  }

  /// Wall clock, as a seam: the batcher's window boundaries are wall-clock
  /// seconds, and a test that waited for real ones would take a real minute.
  @visibleForTesting
  DateTime now() => DateTime.now();

  /// Whether a session is recording right now.
  bool get isRecording => state != null;

  /// Start recording [activity].
  ///
  /// Refuses without [UserSettings.dataCollectionConsent]: capture writes raw
  /// motion — and, when the diagnostic log is also on, precise positions — to
  /// the device, and that is what the consent is for. A second call while a
  /// session is running is ignored rather than silently relabelling the data
  /// already recorded.
  Future<void> start(CaptureActivity activity) async {
    if (state != null) return;

    final settings = ref.read(currentSettingsProvider);
    if (!settings.dataCollectionConsent) {
      _logger.warning('Capture refused: data collection consent not granted');
      return;
    }

    // The session id doubles as the `sess` stamp on every row it owns, so it
    // has to exist before the first line is written — and `write` is
    // synchronous, so it cannot be a database-allocated one.
    final startedAt = now();
    final session = CaptureSession(
      id: startedAt.millisecondsSinceEpoch,
      activity: activity,
      startedAt: startedAt,
      endedAt: null,
      exportedAt: null,
    );

    // Installs the sink if the journal is off, so the `lbl` below has somewhere
    // to land. Synchronous on purpose: see `AuditLogController.setCapture`.
    ref
        .read(auditLogControllerProvider.notifier)
        .setCapture(active: true, session: session.id, activity: activity.name);

    AuditLog.emitCapture(
      AuditEvent.label,
      () => <String, Object?>{
        'a': 'start',
        'act': activity.name,
        'sess': session.id,
      },
      critical: true,
    );

    _resetWindow(startedAt);
    _closeMotionSubscription ??= ref.container
        .listen(
          motionDataStreamProvider,
          (previous, next) =>
              next.whenOrNull(data: _onMotionData, error: _onMotionStreamError),
        )
        .close;

    // Published last: `state` is what the power mode, the foreground service
    // and the UI read, and none of them should see a session that is not yet
    // recording.
    state = session;
    _logger.info('Capture session ${session.id} started as ${activity.name}');
  }

  /// Stop the session, flushing the partial second it was filling.
  ///
  /// The trailing window is written even though it is short: `n` says how many
  /// samples it holds, so a consumer windowing the corpus can decide what to do
  /// with it — whereas a silently dropped second looks like a gap in the
  /// sensor stream, which is a statement about the *device*.
  Future<void> stop() async {
    final session = state;
    if (session == null) return;

    _flushWindow();

    AuditLog.emitCapture(
      AuditEvent.label,
      () => <String, Object?>{
        'a': 'stop',
        'act': session.activity.name,
        'sess': session.id,
      },
      critical: true,
    );

    _closeMotionSubscription?.call();
    _closeMotionSubscription = null;
    _windowEnd = null;
    state = null;

    final controller = ref.read(auditLogControllerProvider.notifier);
    controller.setCapture(active: false, session: session.id);
    await controller.flush();
    _logger.info('Capture session ${session.id} stopped');
  }

  void _teardown() {
    _closeMotionSubscription?.call();
    _closeMotionSubscription = null;
  }

  /// Accumulate one sample, flushing whenever the window boundary is crossed.
  ///
  /// Runs at the configured sampling rate, so nothing here may allocate: the
  /// six `add` calls amortise into the reused lists, and the only object built
  /// per *second* is the field map inside [AuditLog.emitCapture]'s closure.
  void _onMotionData(MotionData motion) {
    final at = now();
    final end = _windowEnd;
    if (end == null) return;

    if (!at.isBefore(end)) _flushWindow(at: at);

    // The backstop, not a second throttle: the T045 rate hold already holds the
    // stream to the configured rate, and this only catches an OS delivering
    // past it inside a single window. The surplus is dropped rather than
    // growing the line, and `n` records what was kept.
    if (_ax.length >= AppConstants.captureMaxSamplesPerLine) return;

    _ax.add(motion.accelerometer.x);
    _ay.add(motion.accelerometer.y);
    _az.add(motion.accelerometer.z);
    _gx.add(motion.gyroscope.x);
    _gy.add(motion.gyroscope.y);
    _gz.add(motion.gyroscope.z);
  }

  /// Write the accumulated window as one `raw` line and open the next.
  ///
  /// [at] is the sample that crossed the boundary; the next window is placed by
  /// stepping the boundary forward, and re-anchored on [at] only if the stream
  /// was interrupted for longer than a window (a suspension, a resubscription)
  /// — otherwise every second of a five-minute gap would be stepped through one
  /// empty window at a time.
  void _flushWindow({DateTime? at}) {
    if (_ax.isNotEmpty) {
      // Copied out of the reusable buffers: the encoder walks the iterables
      // inside `AuditEvent.encode`, which happens on this call, but a closure
      // that read the live lists would still be a hazard the day emission
      // becomes deferred.
      final n = _ax.length;
      // The session id travels *inside* the line as well as in the `sess`
      // column: the column is what retention groups on, but an exported file
      // is plain NDJSON with no columns, and a corpus whose windows cannot be
      // attributed to a label is not a corpus.
      final session = state?.id;
      final ax = List<double>.of(_ax);
      final ay = List<double>.of(_ay);
      final az = List<double>.of(_az);
      final gx = List<double>.of(_gx);
      final gy = List<double>.of(_gy);
      final gz = List<double>.of(_gz);

      AuditLog.emitCapture(
        AuditEvent.rawMotion,
        () => <String, Object?>{
          'sess': session,
          'hz': AppConstants.captureSamplingRate,
          'n': n,
          'ax': ax,
          'ay': ay,
          'az': az,
          'gx': gx,
          'gy': gy,
          'gz': gz,
        },
      );
    }

    _ax.clear();
    _ay.clear();
    _az.clear();
    _gx.clear();
    _gy.clear();
    _gz.clear();

    final end = _windowEnd;
    if (at == null || end == null) return;

    final next = end.add(AppConstants.captureBatchDuration);
    _windowEnd = next.isAfter(at)
        ? next
        : at.add(AppConstants.captureBatchDuration);
  }

  void _resetWindow(DateTime from) {
    _ax.clear();
    _ay.clear();
    _az.clear();
    _gx.clear();
    _gy.clear();
    _gz.clear();
    _windowEnd = from.add(AppConstants.captureBatchDuration);
  }

  /// The motion stream is the only input capture has. Losing it ends the
  /// session rather than leaving a `lbl start` open over a silence that would
  /// later read as a stationary rider.
  void _onMotionStreamError(Object error, StackTrace stackTrace) {
    _logger.error('Motion stream error during capture', error, stackTrace);
    unawaited(stop());
  }
}
