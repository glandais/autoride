import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:autoride/features/settings/domain/models/user_settings.dart';
import 'package:autoride/features/settings/presentation/widgets/data_management_section.dart';

import '../../../../helpers/widget/pump_app.dart';

// ===========================================================================
// The app redistributes Roboto under Apache-2.0 and a long list of packages,
// so it has to be able to show their licences. What is under test is the row
// that gets the user there.
// ===========================================================================

void main() {
  setUp(() {
    // `PackageInfo.fromPlatform()` has no plugin behind it in a widget test.
    PackageInfo.setMockInitialValues(
      appName: 'AutoRide',
      packageName: 'com.example.autoride',
      version: '1.0.0',
      buildNumber: '16',
      buildSignature: '',
    );
  });

  Future<void> pumpSection(WidgetTester tester) async {
    await pumpAppWidget(
      tester,
      const Scaffold(
        body: SingleChildScrollView(
          child: DataManagementSection(settings: UserSettings()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers an open-source licenses row', (tester) async {
    await pumpSection(tester);

    expect(find.text('Open-source licenses'), findsOneWidget);
  });

  testWidgets('tapping it opens the license page', (tester) async {
    await pumpSection(tester);

    await tester.tap(find.text('Open-source licenses'));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
  });
}
