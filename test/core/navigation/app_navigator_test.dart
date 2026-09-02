import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:autoride/core/navigation/app_navigator.dart';

void main() {
  late AppNavigator navigator;

  setUp(() {
    navigator = AppNavigator(GlobalKey<NavigatorState>());
  });

  /// Mount a bare app wired the way `main.dart` wires the real one.
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator.navigatorKey,
        navigatorObservers: [navigator],
        home: const Scaffold(body: Text('home')),
        routes: {
          AppRoutes.tripTracking: (_) => const Scaffold(body: Text('tracking')),
        },
        onGenerateRoute: (settings) {
          if (settings.name != AppRoutes.tripDetail) return null;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) =>
                Scaffold(body: Text('detail ${settings.arguments}')),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('goToTripTracking pushes the tracking route', (tester) async {
    await pumpApp(tester);

    navigator.goToTripTracking();
    await tester.pumpAndSettle();

    expect(find.text('tracking'), findsOneWidget);
    expect(navigator.currentRouteName, AppRoutes.tripTracking);
  });

  // A second tap on the ongoing notification must not stack a second tracking
  // screen the user then has to pop twice.
  testWidgets('a repeated push of the current route is ignored', (
    tester,
  ) async {
    await pumpApp(tester);

    navigator.goToTripTracking();
    await tester.pumpAndSettle();
    navigator.goToTripTracking();
    await tester.pumpAndSettle();

    Navigator.of(navigator.navigatorKey.currentContext!).pop();
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(find.text('tracking'), findsNothing);
  });

  testWidgets('goToTripDetail carries the trip id, and a different id '
      'is not deduplicated', (tester) async {
    await pumpApp(tester);

    navigator.goToTripDetail(7);
    await tester.pumpAndSettle();
    expect(find.text('detail 7'), findsOneWidget);

    navigator.goToTripDetail(7);
    await tester.pumpAndSettle();
    expect(find.text('detail 7'), findsOneWidget);

    navigator.goToTripDetail(8);
    await tester.pumpAndSettle();
    expect(find.text('detail 8'), findsOneWidget);
  });

  testWidgets('goToHome unwinds back to the first route', (tester) async {
    await pumpApp(tester);

    navigator.goToTripDetail(3);
    await tester.pumpAndSettle();
    navigator.goToTripTracking();
    await tester.pumpAndSettle();

    navigator.goToHome();
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    // Back on the initial route, which `MaterialApp` names '/'.
    expect(navigator.currentRouteName, '/');
  });
}
