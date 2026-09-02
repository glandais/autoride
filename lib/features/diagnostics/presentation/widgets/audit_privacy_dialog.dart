import 'package:flutter/material.dart';

/// Blocking confirmation shown before the audit log leaves the device.
///
/// A dialog rather than a subtitle or a snackbar because this is the moment of
/// the decision: the file holds the rider's precise positions — the routes they
/// took and the places they set off from — and the share sheet is the point at
/// which that stops being private to the phone.
///
/// It also carries a second weight. `store-metadata/data-safety.md` declares
/// that AutoRide collects and shares nothing, which stays true for a transfer
/// the user initiates through the system share sheet *provided they are told
/// what they are sending*. This dialog is that condition, not decoration.
class AuditPrivacyDialog extends StatelessWidget {
  const AuditPrivacyDialog({super.key});

  /// Show the dialog and return whether the user chose to share.
  static Future<bool> show(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const AuditPrivacyDialog(),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Share diagnostic log?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This file contains your precise GPS positions — the routes you '
            'rode and the places you set off from — plus your device model, '
            'OS version and app version.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'It does not contain your name, email address, or any advertising '
            'identifier.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'Only share it with someone you trust.',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Share'),
        ),
      ],
    );
  }
}
