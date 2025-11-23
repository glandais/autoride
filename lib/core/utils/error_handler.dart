import 'package:sqflite/sqflite.dart';
import 'package:geolocator/geolocator.dart';
import 'package:autoride/features/trip_history/presentation/providers/trip_detail_provider.dart';
import 'package:autoride/shared/widgets/error_view.dart';

enum AppErrorType {
  notFound,
  network,
  permission,
  database,
  timeout,
  unknown,
}

class ErrorHandler {
  ErrorHandler._();

  /// Classify error type based on exception
  static AppErrorType classifyError(Object error) {
    if (error is TripNotFoundException) {
      return AppErrorType.notFound;
    }

    if (error is LocationServiceDisabledException ||
        error is PermissionDeniedException) {
      return AppErrorType.permission;
    }

    if (error is DatabaseException ||
        error.toString().contains('database') ||
        error.toString().contains('sqlite')) {
      return AppErrorType.database;
    }

    if (error.toString().contains('network') ||
        error.toString().contains('connection') ||
        error.toString().contains('timeout')) {
      return AppErrorType.network;
    }

    if (error is TimeoutException) {
      return AppErrorType.timeout;
    }

    return AppErrorType.unknown;
  }

  /// Extract user-friendly error message
  static String getErrorMessage(Object error) {
    // Custom exceptions with message property
    if (error is TripNotFoundException) {
      return error.message;
    }

    // Location service exceptions
    if (error is LocationServiceDisabledException) {
      return 'Location services are disabled. Please enable them in settings.';
    }

    if (error is PermissionDeniedException) {
      return 'Location permission denied. Please grant permission in settings.';
    }

    if (error is PermissionRequestInProgressException) {
      return 'Permission request is already in progress.';
    }

    // Database exceptions
    if (error is DatabaseException) {
      return 'Database error: ${error.toString()}';
    }

    // Generic error message
    final errorStr = error.toString();

    // Remove "Exception: " prefix if present
    if (errorStr.startsWith('Exception: ')) {
      return errorStr.substring('Exception: '.length);
    }

    return errorStr;
  }

  /// Get user-friendly title for error type
  static String getErrorTitle(AppErrorType type) {
    switch (type) {
      case AppErrorType.notFound:
        return 'Not Found';
      case AppErrorType.network:
        return 'Connection Error';
      case AppErrorType.permission:
        return 'Permission Required';
      case AppErrorType.database:
        return 'Database Error';
      case AppErrorType.timeout:
        return 'Request Timeout';
      case AppErrorType.unknown:
        return 'Error';
    }
  }

  /// Convert error to ErrorView type
  static ErrorType toErrorViewType(AppErrorType type) {
    switch (type) {
      case AppErrorType.notFound:
        return ErrorType.notFound;
      case AppErrorType.network:
      case AppErrorType.timeout:
        return ErrorType.network;
      case AppErrorType.permission:
        return ErrorType.permission;
      case AppErrorType.database:
        return ErrorType.database;
      case AppErrorType.unknown:
        return ErrorType.unknown;
    }
  }
}

/// Custom timeout exception
class TimeoutException implements Exception {
  final String message;
  const TimeoutException(this.message);

  @override
  String toString() => message;
}
