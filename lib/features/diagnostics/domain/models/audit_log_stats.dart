import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:autoride/core/audit/audit_level.dart';

part 'audit_log_stats.freezed.dart';

/// What the settings screen shows about the audit log: how much has been
/// recorded, how far back it actually reaches, and what it occupies.
///
/// [oldestAt] is not decoration. Retention is stated as seven days, but at
/// verbose level the byte and row bounds bite first — a full journal covers
/// roughly seven *hours of riding*, not seven days. Showing the window that is
/// really covered is the honest version of that promise.
@freezed
sealed class AuditLogStats with _$AuditLogStats {
  const AuditLogStats._();

  const factory AuditLogStats({
    required int eventCount,
    required int sizeBytes,
    required DateTime? oldestAt,
    required DateTime? newestAt,
    required AuditLogLevel level,
  }) = _AuditLogStats;

  /// Nothing recorded yet — also what an unopened database reports.
  factory AuditLogStats.empty(AuditLogLevel level) => AuditLogStats(
    eventCount: 0,
    sizeBytes: 0,
    oldestAt: null,
    newestAt: null,
    level: level,
  );
}

/// Extension methods for [AuditLogStats].
extension AuditLogStatsExtensions on AuditLogStats {
  /// Whether there is anything to export.
  bool get isEmpty => eventCount == 0;

  /// Time span actually covered by the retained events.
  Duration? get coverage {
    final from = oldestAt;
    final to = newestAt;
    if (from == null || to == null) return null;
    return to.difference(from);
  }
}
