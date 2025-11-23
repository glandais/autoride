import 'package:flutter/material.dart';
import '../../theme/app_spacing.dart';
import '../models/permission_rationale.dart';

/// Permission rationale dialog
///
/// Shows rationale explaining why a permission is needed before requesting it.
/// Follows platform best practices for progressive permission requests.
class PermissionRationaleDialog extends StatelessWidget {
  const PermissionRationaleDialog({
    required this.rationale,
    required this.onAllow,
    this.onDeny,
    super.key,
  });

  final PermissionRationale rationale;
  final VoidCallback onAllow;
  final VoidCallback? onDeny;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      icon: Icon(
        rationale.icon,
        size: 48,
        color: theme.colorScheme.primary,
      ),
      title: Text(rationale.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Description
            Text(
              rationale.description,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),

            // Benefits
            Text(
              rationale.isOptional ? 'Benefits:' : 'Required for:',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            ...rationale.benefits.map(
              (benefit) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        benefit,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Privacy note
            if (rationale.privacyNote != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.privacy_tip,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        rationale.privacyNote!,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        // Deny/Skip button
        if (rationale.isOptional)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onDeny?.call();
            },
            child: const Text('Skip'),
          ),
        if (!rationale.isOptional)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onDeny?.call();
            },
            child: const Text('Not Now'),
          ),

        // Allow button
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            onAllow();
          },
          child: const Text('Allow'),
        ),
      ],
    );
  }

  /// Show the dialog
  ///
  /// Returns true if user tapped Allow, false if denied/skipped, null if dismissed
  static Future<bool?> show(
    BuildContext context,
    PermissionRationale rationale,
  ) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PermissionRationaleDialog(
        rationale: rationale,
        onAllow: () => Navigator.of(context).pop(true),
        onDeny: () => Navigator.of(context).pop(false),
      ),
    );
  }
}
