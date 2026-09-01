import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:autoride/core/permissions/services/permission_handler_service.dart';
import 'package:autoride/core/platform/models/platform_info.dart';
import 'package:autoride/core/permissions/widgets/background_location_banner.dart';

import '../../../helpers/widget/fake_trip_providers.dart';
import '../../../helpers/widget/pump_app.dart';

// ===========================================================================
// The banner is the only place the app admits that automatic detection cannot
// run in the background — iOS "While Using" and Android's "Allow all the time"
// are both invisible failures otherwise, and so is an approximate location
// that keeps detection alive while recording kilometre-off points. These tests
// pin when it appears, which of the two issues it reports, and that its copy
// names the right system-settings choice per platform.
// ===========================================================================

/// Calls the permission double was asked to make. Kept outside the notifier:
/// the provider is autoDispose and a notifier instance may not be reused.
class PermissionLog {
  int openAppSettingsCalls = 0;
}

/// Permission service double: `openAppSettings` counts calls instead of
/// reaching the plugin.
class FakePermissionHandlerService extends PermissionHandlerService {
  FakePermissionHandlerService(this.log);

  final PermissionLog log;

  @override
  Future<void> build() async {}

  @override
  Future<bool> openAppSettings() async {
    log.openAppSettingsCalls++;
    return true;
  }
}

void main() {
  const title = 'Automatic detection needs background location';
  const iosBody =
      'Set Location to "Always" in Settings so trips can start while the app '
      'is closed.';
  const androidBody =
      'Choose "Allow all the time" in Settings so trips can start while the '
      'app is closed.';
  const preciseTitle = 'Automatic detection needs precise location';
  const preciseIosBody =
      'Turn on "Precise Location" for AutoRide in Settings so trips are '
      'recorded accurately.';
  const preciseAndroidBody =
      'Choose "Precise" location for AutoRide in Settings so trips are '
      'recorded accurately.';

  Future<PermissionLog> pumpBanner(
    WidgetTester tester, {
    bool backgroundLocationGranted = false,
    bool backgroundLocationPrecise = true,
    bool automaticDetectionEnabled = true,
    PlatformInfo platform = androidPlatform,
  }) async {
    final permissions = PermissionLog();
    await pumpAppWidget(
      tester,
      const Scaffold(body: BackgroundLocationBanner()),
      overrides: [
        ...tripSurfaceOverrides(
          recorder: RecorderLog(),
          detection: AutoDetectionLog(),
          automaticDetectionEnabled: automaticDetectionEnabled,
          backgroundLocationGranted: backgroundLocationGranted,
          backgroundLocationPrecise: backgroundLocationPrecise,
          platform: platform,
        ),
        permissionHandlerServiceProvider.overrideWith(
          () => FakePermissionHandlerService(permissions),
        ),
      ],
    );
    await tester.pumpAndSettle();
    return permissions;
  }

  testWidgets('stays hidden when "Always" and precise location are granted', (
    tester,
  ) async {
    await pumpBanner(tester, backgroundLocationGranted: true);

    expect(find.text(title), findsNothing);
    expect(find.text(preciseTitle), findsNothing);
  });

  testWidgets('stays hidden when automatic detection is disabled', (
    tester,
  ) async {
    await pumpBanner(tester, automaticDetectionEnabled: false);

    expect(find.text(title), findsNothing);
  });

  testWidgets('names the Android choice when the permission is missing', (
    tester,
  ) async {
    await pumpBanner(tester);

    expect(find.text(title), findsOneWidget);
    expect(find.text(androidBody), findsOneWidget);
    expect(find.text(iosBody), findsNothing);
    expect(find.byIcon(Icons.location_off), findsOneWidget);
  });

  testWidgets('names the iOS choice on iOS', (tester) async {
    await pumpBanner(tester, platform: iosPlatform);

    expect(find.text(title), findsOneWidget);
    expect(find.text(iosBody), findsOneWidget);
    expect(find.text(androidBody), findsNothing);
  });

  testWidgets('asks for precise location when only accuracy is reduced', (
    tester,
  ) async {
    await pumpBanner(
      tester,
      backgroundLocationGranted: true,
      backgroundLocationPrecise: false,
    );

    expect(find.text(preciseTitle), findsOneWidget);
    expect(find.text(preciseAndroidBody), findsOneWidget);
    expect(find.text(preciseIosBody), findsNothing);
    // The accuracy warning must not be mistaken for the permission one.
    expect(find.text(title), findsNothing);
    expect(find.byIcon(Icons.location_searching), findsOneWidget);
    expect(find.byIcon(Icons.location_off), findsNothing);
  });

  testWidgets('names the iOS "Precise Location" switch on iOS', (tester) async {
    await pumpBanner(
      tester,
      backgroundLocationGranted: true,
      backgroundLocationPrecise: false,
      platform: iosPlatform,
    );

    expect(find.text(preciseTitle), findsOneWidget);
    expect(find.text(preciseIosBody), findsOneWidget);
    expect(find.text(preciseAndroidBody), findsNothing);
  });

  testWidgets('reports the missing permission first when both are wrong', (
    tester,
  ) async {
    await pumpBanner(tester, backgroundLocationPrecise: false);

    expect(find.text(title), findsOneWidget);
    expect(find.text(preciseTitle), findsNothing);
  });

  testWidgets('"Open Settings" opens the system settings', (tester) async {
    final permissions = await pumpBanner(tester);

    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();

    expect(permissions.openAppSettingsCalls, 1);
  });
}
