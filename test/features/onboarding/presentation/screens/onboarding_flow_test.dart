import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:autoride/core/permissions/exceptions/permission_exceptions.dart';
import 'package:autoride/core/permissions/providers/background_location_status.dart';
import 'package:autoride/core/permissions/services/permission_handler_service.dart';
import 'package:autoride/features/onboarding/data/services/onboarding_service.dart';
import 'package:autoride/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:autoride/features/onboarding/presentation/screens/background_permission_screen.dart';
import 'package:autoride/features/onboarding/presentation/screens/onboarding_screen.dart';

import '../../../../helpers/widget/fake_permission_handler_service.dart';
import '../../../../helpers/widget/fake_trip_providers.dart';
import '../../../../helpers/widget/pump_app.dart';

// ===========================================================================
// The permission flow gates all data collection and had no coverage at all
// (L-013). What is under test here is the FLOW — which page the user lands on
// and what the app then believes about each permission — so the permission
// service is scripted and no platform call is asserted on.
// ===========================================================================

void main() {
  late PermissionScript script;
  late FakeOnboardingService onboardingService;
  late FakeBackgroundLocationStatus backgroundStatus;

  setUp(() {
    script = PermissionScript();
    onboardingService = FakeOnboardingService(firstLaunch: true);
    backgroundStatus = FakeBackgroundLocationStatus(granted: false);
  });

  /// Only the page the user is actually looking at.
  ///
  /// A `PageView` keeps neighbouring pages in its cache extent, so a bare
  /// `find.text` can match a page that is off-screen.
  Finder visibleText(String text) => find.text(text).hitTestable();

  Future<ProviderContainer> pumpOnboarding(WidgetTester tester) async {
    await pumpAppWidget(
      tester,
      const OnboardingScreen(),
      overrides: [
        permissionHandlerServiceProvider.overrideWith(
          () => FakePermissionHandlerService(script),
        ),
        onboardingServiceProvider.overrideWith(() => onboardingService),
        backgroundLocationStatusProvider.overrideWith(() => backgroundStatus),
      ],
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(OnboardingScreen)),
    );
  }

  /// Advance through the pages the way the buttons do, without asserting on
  /// them (each test asserts on the step it owns).
  Future<void> goToPage(
    WidgetTester tester,
    ProviderContainer container,
    int page,
  ) async {
    while (container.read(onboardingProvider).currentPage < page) {
      final done = container.read(onboardingProvider.notifier).nextPage();
      await tester.pumpAndSettle();
      await done;
    }
    await tester.pumpAndSettle();
  }

  int currentPage(ProviderContainer container) =>
      container.read(onboardingProvider).currentPage;

  group('Onboarding - navigation', () {
    testWidgets('welcome and features advance to the location rationale', (
      tester,
    ) async {
      final container = await pumpOnboarding(tester);

      expect(visibleText('Get Started'), findsOneWidget);
      expect(currentPage(container), 0);

      await tester.tap(visibleText('Get Started'));
      await tester.pumpAndSettle();
      expect(currentPage(container), 1);

      await tester.tap(visibleText('Continue'));
      await tester.pumpAndSettle();

      expect(currentPage(container), 2);
      expect(visibleText('Location Permission'), findsOneWidget);
      expect(visibleText('Allow Location Access'), findsOneWidget);
      // Nothing was requested by merely showing the rationale.
      expect(script.requested, isEmpty);
    });
  });

  group('Onboarding - location permission', () {
    testWidgets('granting location advances to the background step', (
      tester,
    ) async {
      script.requestGrants[AppPermission.locationWhenInUse] = true;
      final container = await pumpOnboarding(tester);
      await goToPage(tester, container, 2);

      await tester.tap(visibleText('Allow Location Access'));
      await tester.pumpAndSettle();

      expect(script.wasRequested(AppPermission.locationWhenInUse), isTrue);
      expect(
        container.read(onboardingProvider).locationPermissionGranted,
        isTrue,
      );
      expect(currentPage(container), 3);
      expect(find.byType(BackgroundPermissionScreen), findsOneWidget);
    });

    testWidgets('denying location keeps the user on the rationale, no crash', (
      tester,
    ) async {
      script.requestGrants[AppPermission.locationWhenInUse] = false;
      final container = await pumpOnboarding(tester);
      await goToPage(tester, container, 2);

      await tester.tap(visibleText('Allow Location Access'));
      await tester.pumpAndSettle();

      expect(script.wasRequested(AppPermission.locationWhenInUse), isTrue);
      expect(
        container.read(onboardingProvider).locationPermissionGranted,
        isFalse,
      );
      expect(currentPage(container), 2);
      // The button stays available so the user can try again.
      expect(visibleText('Allow Location Access'), findsOneWidget);
    });

    testWidgets(
      'a permanently denied location sends the user to app settings',
      (tester) async {
        script.permanentlyDenied.add(AppPermission.locationWhenInUse);
        final container = await pumpOnboarding(tester);
        await goToPage(tester, container, 2);

        await tester.tap(visibleText('Allow Location Access'));
        await tester.pumpAndSettle();

        expect(script.settingsOpened, 1);
        expect(currentPage(container), 2);
        expect(
          container.read(onboardingProvider).locationPermissionGranted,
          isFalse,
        );
      },
    );
  });

  group('Onboarding - background permission', () {
    testWidgets(
      'granting background also requests notifications, then advances',
      (tester) async {
        script.requestGrants[AppPermission.locationWhenInUse] = true;
        script.requestGrants[AppPermission.locationAlways] = true;
        script.requestGrants[AppPermission.notification] = true;
        final container = await pumpOnboarding(tester);
        await goToPage(tester, container, 3);

        await tester.tap(visibleText('Enable Automatic Tracking'));
        await tester.pumpAndSettle();

        expect(script.wasRequested(AppPermission.locationAlways), isTrue);
        // POST_NOTIFICATIONS was declared but never requested before T041/L-016.
        expect(script.wasRequested(AppPermission.notification), isTrue);

        final state = container.read(onboardingProvider);
        expect(state.backgroundPermissionGranted, isTrue);
        expect(state.notificationPermissionGranted, isTrue);
        expect(currentPage(container), 4);
        // The app-wide background-location status is re-read: it was built
        // before the request and would otherwise stay "not granted" forever.
        expect(backgroundStatus.refreshCalls, 1);
      },
    );

    testWidgets('a denied background permission still proceeds', (
      tester,
    ) async {
      script.requestGrants[AppPermission.locationWhenInUse] = true;
      script.requestGrants[AppPermission.locationAlways] = false;
      script.requestGrants[AppPermission.notification] = true;
      final container = await pumpOnboarding(tester);
      await goToPage(tester, container, 3);

      await tester.tap(visibleText('Enable Automatic Tracking'));
      await tester.pumpAndSettle();

      final state = container.read(onboardingProvider);
      expect(state.backgroundPermissionGranted, isFalse);
      expect(currentPage(container), 4);
    });

    testWidgets('"Skip for Now" requests notifications and advances', (
      tester,
    ) async {
      script.requestGrants[AppPermission.notification] = true;
      final container = await pumpOnboarding(tester);
      await goToPage(tester, container, 3);

      await tester.tap(visibleText('Skip for Now'));
      await tester.pumpAndSettle();

      expect(script.wasRequested(AppPermission.locationAlways), isFalse);
      expect(script.wasRequested(AppPermission.notification), isTrue);
      expect(
        container.read(onboardingProvider).notificationPermissionGranted,
        isTrue,
      );
      expect(currentPage(container), 4);
    });
  });

  group('Onboarding - setup complete', () {
    testWidgets('summarises what was granted and what was not', (tester) async {
      script.requestGrants[AppPermission.locationWhenInUse] = true;
      script.requestGrants[AppPermission.locationAlways] = false;
      script.requestGrants[AppPermission.notification] = true;
      final container = await pumpOnboarding(tester);
      await goToPage(tester, container, 2);

      // Walk the real permission steps: the summary reflects what the flow
      // recorded, not what the OS would answer if asked again.
      await tester.tap(visibleText('Allow Location Access'));
      await tester.pumpAndSettle();
      await tester.tap(visibleText('Enable Automatic Tracking'));
      await tester.pumpAndSettle();

      expect(visibleText("You're All Set!"), findsOneWidget);
      expect(visibleText('Location Access'), findsOneWidget);
      expect(visibleText('Automatic Tracking'), findsOneWidget);
      expect(visibleText('Trip Notifications'), findsOneWidget);

      // Granted rows are ticked, the refused one is crossed out.
      expect(
        _summaryIcon('Location Access', Icons.check_circle),
        findsOneWidget,
      );
      expect(_summaryIcon('Automatic Tracking', Icons.cancel), findsOneWidget);
      expect(
        _summaryIcon('Trip Notifications', Icons.check_circle),
        findsOneWidget,
      );

      // Copy adapts to the missing background permission.
      expect(
        visibleText(
          'AutoRide is ready! Tap the record button when you start riding '
          'to track your trips.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('"Start Riding" completes onboarding', (tester) async {
      final container = await pumpOnboarding(tester);
      await goToPage(tester, container, 4);

      await tester.tap(visibleText('Start Riding'));
      await tester.pumpAndSettle();

      expect(onboardingService.completeCalls, 1);
      expect(container.read(onboardingProvider).isComplete, isTrue);
    });
  });

  group('Onboarding - app resume', () {
    // Android 11+ only grants "Allow all the time" through app settings, so the
    // status held when openAppSettings() returns is the pre-detour one.
    testWidgets('re-reads every permission status when the app resumes', (
      tester,
    ) async {
      final container = await pumpOnboarding(tester);
      await goToPage(tester, container, 3);
      expect(
        container.read(onboardingProvider).backgroundPermissionGranted,
        isFalse,
      );

      // The user granted everything in system settings while we were away.
      script.checkGrants[AppPermission.locationWhenInUse] = true;
      script.checkGrants[AppPermission.locationAlways] = true;
      script.checkGrants[AppPermission.notification] = true;

      await _sendLifecycleState(tester, AppLifecycleState.inactive);
      await _sendLifecycleState(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      final state = container.read(onboardingProvider);
      expect(state.locationPermissionGranted, isTrue);
      expect(state.backgroundPermissionGranted, isTrue);
      expect(state.notificationPermissionGranted, isTrue);
    });
  });
}

/// The trailing state icon of one row of the setup summary.
Finder _summaryIcon(String label, IconData icon) => find.descendant(
  of: find
      .ancestor(of: find.text(label).hitTestable(), matching: find.byType(Row))
      .first,
  matching: find.byIcon(icon),
);

Future<void> _sendLifecycleState(
  WidgetTester tester,
  AppLifecycleState state,
) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/lifecycle',
    const StringCodec().encodeMessage(state.toString()),
    (_) {},
  );
  await tester.pump();
}
