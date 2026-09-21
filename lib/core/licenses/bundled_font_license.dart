import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Declare the licence of the Roboto font bundled in `assets/fonts/`.
///
/// Only packages ship their `LICENSE` to `LicenseRegistry` automatically; a
/// font copied into the assets does not, so without this the licence page
/// would omit the one file the app actually redistributes (Apache-2.0, which
/// requires the notice to travel with it).
///
/// The callback is lazy — `LicenseRegistry` only runs it when something
/// enumerates the licences — so registering at startup costs nothing but the
/// closure.
void registerBundledFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/LICENSE.txt');
    yield LicenseEntryWithLineBreaks(const ['Roboto'], license);
  });
}
