import 'package:flutter/foundation.dart';

import 'package:autoride/core/audit/audit_event.dart';
import 'package:autoride/core/audit/audit_log.dart';

/// Simple logging utility for AutoRide
///
/// Two destinations. `debugPrint`, as before, which only exists in debug
/// builds — and, when the user has turned the audit log on, the log itself.
///
/// The bridge is what makes the device checklist usable: several items of
/// `tasks/T041-device-validation.md` say "log line to look for", and until now
/// those lines did not exist in a release build and needed a cable in a debug
/// one. They now land in the exported file as `log` events, at the cost of one
/// static boolean test per call when the log is off.
class Logger {
  const Logger(this.tag);

  final String tag;

  void debug(String message) {
    _mirror('d', message);
    if (kDebugMode) {
      debugPrint('[$tag] DEBUG: $message');
    }
  }

  void info(String message) {
    _mirror('i', message);
    if (kDebugMode) {
      debugPrint('[$tag] INFO: $message');
    }
  }

  void warning(String message) {
    _mirror('w', message);
    if (kDebugMode) {
      debugPrint('[$tag] WARNING: $message');
    }
  }

  void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (AuditLog.enabled) {
      AuditLog.emit(
        AuditEvent.error,
        () => <String, Object?>{
          'tag': tag,
          'm': message,
          'ex': error?.toString(),
          'st': _topFrames(stackTrace),
        },
        // An error is exactly the kind of event whose absence would make the
        // log inconclusive, so it must be on disk before whatever it caused.
        critical: true,
      );
    }

    debugPrint('[$tag] ERROR: $message');
    if (error != null) {
      debugPrint('Error: $error');
    }
    if (stackTrace != null) {
      debugPrint('StackTrace: $stackTrace');
    }
  }

  void _mirror(String level, String message) {
    if (!AuditLog.enabled) return;
    AuditLog.emit(
      AuditEvent.log,
      () => <String, Object?>{'lv': level, 'tag': tag, 'm': message},
    );
  }

  /// First few stack frames — enough to place an error, short enough that one
  /// exception cannot eat a ride's retention budget.
  static String? _topFrames(StackTrace? stackTrace) {
    if (stackTrace == null) return null;
    final frames = stackTrace.toString().split('\n');
    return frames.take(3).map((f) => f.trim()).join(' | ');
  }
}
