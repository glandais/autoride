import 'package:flutter/material.dart';
import 'package:autoride/core/theme/app_spacing.dart';

/// Reusable loading indicator widget with optional message
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message, this.inline = false});

  const LoadingView.inline({super.key, this.message}) : inline = true;

  const LoadingView.fullScreen({super.key, this.message}) : inline = false;

  final String? message;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final content = Column(
      mainAxisSize: inline ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        if (message != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            message!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );

    if (inline) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: content,
      );
    }

    return Center(child: content);
  }
}
