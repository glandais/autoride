import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// `Override` is not re-exported by flutter_riverpod.
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;

import 'package:autoride/core/permissions/exceptions/permission_exceptions.dart';
import 'package:autoride/core/permissions/providers/background_location_status.dart';
import 'package:autoride/core/permissions/services/permission_handler_service.dart';
import 'package:autoride/core/platform/models/platform_info.dart';
import 'package:autoride/core/platform/services/platform_info_service.dart';
import 'package:autoride/features/settings/data/services/settings_service.dart';
import 'package:autoride/features/settings/domain/models/user_settings.dart';
import 'package:autoride/features/settings/presentation/widgets/location_settings_section.dart';

import '../../../../helpers/widget/fake_permission_handler_service.dart';
import '../../../../helpers/widget/fake_trip_providers.dart';
import '../../../../helpers/widget/pump_app.dart';

// ===========================================================================
// The background-location toggle used to mirror the stored *preference*, which
// can say "on" while the OS only granted "While Using" (iOS) or never got
// "Allow all the time" (Android 11+). What is under test here is that the row
// reports the OS permission and that every request path re-reads it.
// ===========================================================================

void main() {
  late PermissionScript script;
  late FakeBackgroundLocationStatus backgroundStatus;

  setUp(() {
    script = PermissionScript();
    backgroundStatus = FakeBackgroundLocationStatus(granted: false);
  });

  Future<void> pumpSection(
    WidgetTester tester, {
    bool granted = false,
    bool precise = true,
    PlatformInfo platform = androidPlatform,
    // The stored preference: deliberately the opposite of the OS answer by
    // default, so a row that reads it instead of the permission fails here.
    bool storedPreference = true,
  }) async {
    backgroundStatus = FakeBackgroundLocationStatus(
      granted: granted,
      precise: precise,
    );
    final overrides = <Override>[
      backgroundLocationStatusProvider.overrideWith(() => backgroundStatus),
      platformInfoServiceProvider.overrideWith(
        () => FakePlatformInfoService(platform),
      ),
      settingsServiceProvider.overrideWith(FakeSettingsService.new),
      permissionHandlerServiceProvider.overrideWith(
        () => FakePermissionHandlerService(script),
      ),
    ];

    await pumpAppWidget(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: LocationSettingsSection(
            settings: UserSettings(backgroundLocationEnabled: storedPreference),
          ),
        ),
      ),
      overrides: overrides,
    );
    await tester.pumpAndSettle();
  }

  Switch backgroundSwitch(WidgetTester tester) {
    return tester.widget<Switch>(find.byType(Switch));
  }

  Future<void> toggleBackground(WidgetTester tester) async {
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
  }

  group('Background location row - state', () {
    testWidgets('is on when the OS granted it, whatever the preference says', (
      tester,
    ) async {
      await pumpSection(tester, granted: true, storedPreference: false);

      expect(backgroundSwitch(tester).value, isTrue);
      expect(
        find.text('Trips can start while the app is closed'),
        findsOneWidget,
      );
    });

    testWidgets('is off when the OS did not grant it, preference ignored', (
      tester,
    ) async {
      await pumpSection(tester, granted: false, storedPreference: true);

      expect(backgroundSwitch(tester).value, isFalse);
    });

    testWidgets('explains the missing iOS "Always" setting', (tester) async {
      await pumpSection(tester, granted: false, platform: iosPlatform);

      expect(find.text('Location is not set to "Always"'), findsOneWidget);
    });

    testWidgets('explains the missing Android "Allow all the time"', (
      tester,
    ) async {
      await pumpSection(tester, granted: false, platform: androidPlatform);

      expect(find.text('"Allow all the time" is not enabled'), findsOneWidget);
    });

    testWidgets('reports reduced accuracy rather than a missing permission', (
      tester,
    ) async {
      await pumpSection(
        tester,
        granted: true,
        precise: false,
        platform: iosPlatform,
      );

      // "Always" is granted, so the row must not blame the permission.
      expect(find.text('"Precise Location" is off'), findsOneWidget);
      expect(find.text('Location is not set to "Always"'), findsNothing);
      // Approximate points make the recorded trip useless: not ready.
      expect(backgroundSwitch(tester).value, isFalse);
    });

    testWidgets('Android names reduced accuracy "Precise"', (tester) async {
      await pumpSection(
        tester,
        granted: true,
        precise: false,
        platform: androidPlatform,
      );

      expect(find.text('Location is not set to "Precise"'), findsOneWidget);
    });
  });

  group('Background location row - turning it on', () {
    testWidgets('shows the rationale first and requests only on Allow', (
      tester,
    ) async {
      script.requestGrants[AppPermission.locationAlways] = true;
      await pumpSection(tester);

      await toggleBackground(tester);

      // Rationale, and nothing requested yet.
      expect(find.text('Background Location'), findsWidgets);
      expect(script.wasRequested(AppPermission.locationAlways), isFalse);

      await tester.tap(find.widgetWithText(FilledButton, 'Allow'));
      await tester.pumpAndSettle();

      expect(script.wasRequested(AppPermission.locationAlways), isTrue);
      expect(backgroundStatus.refreshCalls, 1);
    });

    testWidgets('a refused rationale requests nothing', (tester) async {
      await pumpSection(tester);

      await toggleBackground(tester);
      // `locationAlways` is an optional rationale, so its refusal is "Skip".
      await tester.tap(find.widgetWithText(TextButton, 'Skip'));
      await tester.pumpAndSettle();

      expect(script.requested, isEmpty);
      expect(backgroundStatus.refreshCalls, 0);
      // The rationale closed without taking the settings screen with it.
      expect(find.byType(LocationSettingsSection), findsOneWidget);
    });

    testWidgets(
      'a permanently denied request offers the platform-specific settings fix',
      (tester) async {
        script.permanentlyDenied.add(AppPermission.locationAlways);
        await pumpSection(tester, platform: iosPlatform);

        await toggleBackground(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Allow'));
        await tester.pumpAndSettle();

        expect(find.text('Change in Settings'), findsOneWidget);
        expect(
          find.text(
            'Set Location to "Always" for AutoRide in the Settings app.',
          ),
          findsOneWidget,
        );
        // The status is re-read even though the request threw.
        expect(backgroundStatus.refreshCalls, 1);

        await tester.tap(find.widgetWithText(FilledButton, 'Open Settings'));
        await tester.pumpAndSettle();

        expect(script.settingsOpened, 1);
      },
    );

    testWidgets('Android gets the "Allow all the time" wording', (
      tester,
    ) async {
      script.permanentlyDenied.add(AppPermission.locationAlways);
      await pumpSection(tester, platform: androidPlatform);

      await toggleBackground(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Allow'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Choose "Allow all the time" for AutoRide\'s location in the '
          'Settings app.',
        ),
        findsOneWidget,
      );
    });
  });

  group('Background location row - reduced accuracy', () {
    testWidgets('goes straight to Settings, skipping a pointless request', (
      tester,
    ) async {
      await pumpSection(
        tester,
        granted: true,
        precise: false,
        platform: iosPlatform,
      );

      await toggleBackground(tester);

      // No rationale, and nothing requested: "Always" is already granted, so
      // re-requesting it shows no prompt and would not restore accuracy.
      expect(find.text('Background Location'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Allow'), findsNothing);
      expect(script.requested, isEmpty);

      expect(find.text('Change in Settings'), findsOneWidget);
      expect(
        find.text(
          'Turn on "Precise Location" for AutoRide in the Settings '
          'app.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Open Settings'));
      await tester.pumpAndSettle();

      expect(script.settingsOpened, 1);
      // The user may have fixed it: the status we hold is now stale.
      expect(backgroundStatus.refreshCalls, 1);
    });

    testWidgets(
      'Android gets the "Precise" wording, and Cancel still re-reads',
      (tester) async {
        await pumpSection(
          tester,
          granted: true,
          precise: false,
          platform: androidPlatform,
        );

        await toggleBackground(tester);

        expect(
          find.text(
            'Choose "Precise" location for AutoRide in the Settings app.',
          ),
          findsOneWidget,
        );

        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();

        expect(script.settingsOpened, 0);
        expect(backgroundStatus.refreshCalls, 1);
      },
    );
  });

  group('Background location row - turning it off', () {
    testWidgets('explains that only the system settings can revoke it', (
      tester,
    ) async {
      await pumpSection(tester, granted: true);

      await toggleBackground(tester);

      expect(find.text('Revoke in Settings'), findsOneWidget);
      // Nothing was requested, and no rationale was shown.
      expect(script.requested, isEmpty);
      expect(find.widgetWithText(FilledButton, 'Allow'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Open Settings'));
      await tester.pumpAndSettle();

      expect(script.settingsOpened, 1);
    });
  });
}
