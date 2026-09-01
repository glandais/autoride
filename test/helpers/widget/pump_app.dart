import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// `Override` is not re-exported by flutter_riverpod.
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;

import 'package:autoride/core/theme/app_theme.dart';

/// Default surface for widget tests.
///
/// A BOUNDED surface matters here: the tracking screen puts a `FlutterMap`
/// inside an `Expanded` and the onboarding pages use `Spacer`s, so they need a
/// real viewport rather than the 800x600 landscape default.
///
/// It is deliberately larger than a phone. Widget tests render with the test
/// font (every glyph a square em), which makes the same copy far taller and
/// wider than on a device; at true phone dimensions these screens overflow on
/// the test font alone, which says nothing about the real layout. The size is
/// generous enough that an overflow here means a genuine layout regression.
const Size kTestSurfaceSize = Size(600, 1400);

/// Pump [child] inside the app's real `MaterialApp`/theme with the given
/// provider [overrides].
///
/// Returns nothing: read state back through the widget tree, or keep a
/// reference to the fakes you passed in.
Future<void> pumpAppWidget(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size surfaceSize = kTestSurfaceSize,
  Map<String, WidgetBuilder> routes = const {},
  NavigatorObserver? navigatorObserver,
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        routes: routes,
        navigatorObservers: [?navigatorObserver],
        home: child,
      ),
    ),
  );

  // One extra frame so async providers that resolve immediately (settings,
  // permissions, onboarding) are past their loading state.
  await tester.pump();
}

/// Records the routes pushed/popped by a screen under test.
class RecordingNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];
  final List<Route<dynamic>> popped = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popped.add(route);
  }
}
