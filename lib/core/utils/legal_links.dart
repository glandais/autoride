import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'error_handler.dart';

/// Opens one of the hosted legal documents in the device browser.
///
/// The documents are opened externally rather than rendered from a bundled asset so that users
/// always see the published version. A copy shipped inside the app would drift out of date
/// between releases, and the privacy policy is filed verbatim with both stores — see
/// `store-metadata/data-safety.md` §9.
///
/// Use with [AppConstants.privacyPolicyUrl] or [AppConstants.termsOfUseUrl].
Future<void> openLegalUrl(BuildContext context, String url) async {
  // Captured before the await: using `context` afterwards would be unsafe if the widget were
  // disposed while the browser was opening (use_build_context_synchronously).
  final messenger = ScaffoldMessenger.of(context);

  try {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the page in a browser')),
      );
    }
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Could not open the page: ${ErrorHandler.getErrorMessage(e)}',
        ),
      ),
    );
  }
}
