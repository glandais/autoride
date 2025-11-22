import 'package:flutter/foundation.dart';

/// Simple logging utility for AutoRide
class Logger {
  const Logger(this.tag);

  final String tag;

  void debug(String message) {
    if (kDebugMode) {
      debugPrint('[$tag] DEBUG: $message');
    }
  }

  void info(String message) {
    if (kDebugMode) {
      debugPrint('[$tag] INFO: $message');
    }
  }

  void warning(String message) {
    if (kDebugMode) {
      debugPrint('[$tag] WARNING: $message');
    }
  }

  void error(String message, [Object? error, StackTrace? stackTrace]) {
    debugPrint('[$tag] ERROR: $message');
    if (error != null) {
      debugPrint('Error: $error');
    }
    if (stackTrace != null) {
      debugPrint('StackTrace: $stackTrace');
    }
  }
}
