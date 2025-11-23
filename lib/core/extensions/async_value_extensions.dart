import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:autoride/core/utils/error_handler.dart';
import 'package:autoride/shared/widgets/error_view.dart';

/// Extensions for AsyncValue to simplify error handling
extension AsyncValueExtensions<T> on AsyncValue<T> {
  /// Get user-friendly error message
  String? get errorMessage {
    return whenOrNull(
      error: (error, stackTrace) => ErrorHandler.getErrorMessage(error),
    );
  }

  /// Get error type
  AppErrorType? get errorType {
    return whenOrNull(
      error: (error, stackTrace) => ErrorHandler.classifyError(error),
    );
  }

  /// Get ErrorView type
  ErrorType? get errorViewType {
    final type = errorType;
    if (type == null) return null;
    return ErrorHandler.toErrorViewType(type);
  }

  /// Check if has data (even if loading or error)
  bool get hasData => hasValue && value != null;

  /// Get data or null (even if error/loading)
  T? get dataOrNull => hasValue ? value : null;

  /// Build ErrorView for this AsyncValue
  ErrorView? buildErrorView({VoidCallback? onRetry}) {
    return whenOrNull(
      error: (error, stackTrace) {
        final type = ErrorHandler.classifyError(error);
        final message = ErrorHandler.getErrorMessage(error);
        final title = ErrorHandler.getErrorTitle(type);
        final errorViewType = ErrorHandler.toErrorViewType(type);

        return ErrorView(
          type: errorViewType,
          title: title,
          message: message,
          onRetry: onRetry,
        );
      },
    );
  }
}
