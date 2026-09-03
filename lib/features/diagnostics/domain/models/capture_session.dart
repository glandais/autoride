import 'package:freezed_annotation/freezed_annotation.dart';

part 'capture_session.freezed.dart';

/// What a training-capture recording is labelled as (T034).
///
/// The ground truth a classifier is trained against. Deliberately coarse: the
/// question the model has to answer is "is this a bike ride", and a label set
/// the user has to think about is a label set they get wrong.
///
/// [other] is not a dustbin — it is the honest answer for a session the rider
/// cannot name (a train, a lift, a scooter), and a mislabelled session is worse
/// for the corpus than an `other` one.
enum CaptureActivity {
  bike,
  car,
  walk,
  still,
  other;

  /// Label shown in the picker.
  String get displayName => switch (this) {
    CaptureActivity.bike => 'Cycling',
    CaptureActivity.car => 'Car',
    CaptureActivity.walk => 'Walking',
    CaptureActivity.still => 'Still',
    CaptureActivity.other => 'Other',
  };
}

/// One labelled capture session as the database holds it.
///
/// [id] is the session's start in epoch ms, and doubles as the `sess` stamp on
/// every row it owns: [AuditSink.write] is synchronous and on the recording
/// path, so it cannot await a database-allocated id.
@freezed
sealed class CaptureSession with _$CaptureSession {
  const CaptureSession._();

  const factory CaptureSession({
    required int id,
    required CaptureActivity activity,
    required DateTime startedAt,
    required DateTime? endedAt,
    required DateTime? exportedAt,
  }) = _CaptureSession;
}

/// Extension methods for [CaptureSession].
extension CaptureSessionExtensions on CaptureSession {
  /// Whether the session is still being recorded.
  bool get isRecording => endedAt == null;

  /// Whether the session has already been exported, and is therefore the first
  /// thing capture retention may delete.
  bool get isExported => exportedAt != null;

  /// How long it recorded for, or has been recording.
  Duration duration(DateTime now) => (endedAt ?? now).difference(startedAt);
}

/// What the settings screen shows about the captured corpus.
///
/// Separate from `AuditLogStats` because the two are budgeted separately: the
/// journal is bounded at 20 MB and 7 days, capture at 256 MB and 30 days, and
/// a single "recorded" figure covering both would make either bound impossible
/// to reason about from the screen.
@freezed
sealed class CaptureStats with _$CaptureStats {
  const CaptureStats._();

  const factory CaptureStats({
    required int sessionCount,
    required int rowCount,

    /// Bytes of NDJSON, not bytes of file: capture and journal share one
    /// database, so the file's page count cannot be attributed to either.
    required int sizeBytes,
    required int unexportedSessionCount,
    required DateTime? oldestAt,
    required DateTime? newestAt,
  }) = _CaptureStats;

  /// Nothing captured yet — also what an unopened database reports.
  factory CaptureStats.empty() => const CaptureStats(
    sessionCount: 0,
    rowCount: 0,
    sizeBytes: 0,
    unexportedSessionCount: 0,
    oldestAt: null,
    newestAt: null,
  );
}

/// Extension methods for [CaptureStats].
extension CaptureStatsExtensions on CaptureStats {
  /// Whether there is anything to export or delete.
  bool get isEmpty => rowCount == 0;
}
