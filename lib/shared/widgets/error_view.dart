import 'package:flutter/material.dart';
import 'package:autoride/core/theme/app_colors.dart';
import 'package:autoride/core/theme/app_spacing.dart';

enum ErrorType {
  notFound,
  network,
  permission,
  database,
  unknown,
}

class ErrorView extends StatelessWidget {
  final ErrorType type;
  final String? title;
  final String? message;
  final VoidCallback? onRetry;
  final String? retryLabel;

  const ErrorView({
    super.key,
    this.type = ErrorType.unknown,
    this.title,
    this.message,
    this.onRetry,
    this.retryLabel,
  });

  factory ErrorView.notFound({
    String? title,
    String? message,
    VoidCallback? onRetry,
  }) {
    return ErrorView(
      type: ErrorType.notFound,
      title: title ?? 'Not Found',
      message: message ?? 'The requested item could not be found.',
      onRetry: onRetry,
    );
  }

  factory ErrorView.network({
    String? title,
    String? message,
    VoidCallback? onRetry,
  }) {
    return ErrorView(
      type: ErrorType.network,
      title: title ?? 'Connection Error',
      message: message ?? 'Please check your internet connection and try again.',
      onRetry: onRetry,
      retryLabel: 'Retry',
    );
  }

  factory ErrorView.permission({
    String? title,
    String? message,
    VoidCallback? onRetry,
  }) {
    return ErrorView(
      type: ErrorType.permission,
      title: title ?? 'Permission Required',
      message: message ?? 'This feature requires additional permissions.',
      onRetry: onRetry,
      retryLabel: 'Grant Permission',
    );
  }

  factory ErrorView.database({
    String? title,
    String? message,
    VoidCallback? onRetry,
  }) {
    return ErrorView(
      type: ErrorType.database,
      title: title ?? 'Database Error',
      message: message ?? 'Failed to access local data. Please try again.',
      onRetry: onRetry,
      retryLabel: 'Retry',
    );
  }

  factory ErrorView.generic({
    required String message,
    VoidCallback? onRetry,
  }) {
    return ErrorView(
      type: ErrorType.unknown,
      title: 'Error',
      message: message,
      onRetry: onRetry,
      retryLabel: 'Retry',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              _getIcon(),
              size: 64,
              color: AppColors.error,
            ),
            const SizedBox(height: AppSpacing.md),
            if (title != null)
              Text(
                title!,
                style: theme.textTheme.titleLarge?.copyWith(
                      color: AppColors.error,
                    ),
                textAlign: TextAlign.center,
              ),
            if (title != null) const SizedBox(height: AppSpacing.sm),
            if (message != null)
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodySmall?.color,
                    ),
                textAlign: TextAlign.center,
              ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(retryLabel ?? 'Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getIcon() {
    switch (type) {
      case ErrorType.notFound:
        return Icons.search_off;
      case ErrorType.network:
        return Icons.wifi_off;
      case ErrorType.permission:
        return Icons.lock_outline;
      case ErrorType.database:
        return Icons.storage;
      case ErrorType.unknown:
        return Icons.error_outline;
    }
  }
}
