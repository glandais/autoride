import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_navigator.g.dart';

/// Route names registered on the app's [Navigator].
///
/// They live here rather than inline in `main.dart` because the notification
/// service — which has no `BuildContext` — has to name the same routes.
abstract final class AppRoutes {
  static const String home = '/home';
  static const String tripTracking = '/trip-tracking';
  static const String settings = '/settings';

  /// Takes the trip id as its route argument (`int`).
  static const String tripDetail = '/trip-detail';
}

/// App-level navigation reachable from outside the widget tree.
///
/// A notification tap arrives on a platform callback with no `BuildContext`,
/// so the only way to route it is the app's global navigator key. This class
/// owns that key, and doubles as the `NavigatorObserver` that keeps track of
/// the current route — without it, a second tap on the ongoing notification
/// would stack a duplicate tracking screen on top of the first.
class AppNavigator extends NavigatorObserver {
  AppNavigator(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;

  final List<Route<dynamic>> _stack = <Route<dynamic>>[];

  /// Name of the route currently on top, or `null` before the first push.
  String? get currentRouteName =>
      _stack.isEmpty ? null : _stack.last.settings.name;

  /// Argument of the route currently on top.
  Object? get currentRouteArguments =>
      _stack.isEmpty ? null : _stack.last.settings.arguments;

  /// Open the live tracking screen (ongoing/start notification tapped).
  void goToTripTracking() => _pushNamed(AppRoutes.tripTracking);

  /// Open the detail screen of [tripId] (completed-trip notification tapped).
  void goToTripDetail(int tripId) =>
      _pushNamed(AppRoutes.tripDetail, arguments: tripId);

  /// Return to the home shell, whose first tab is the history list.
  ///
  /// The fallback when a trip notification carries no usable id: the ride is
  /// still the most recent row of that list.
  void goToHome() =>
      navigatorKey.currentState?.popUntil((route) => route.isFirst);

  void _pushNamed(String routeName, {Object? arguments}) {
    // Re-tapping a notification that is already showing its destination must
    // not stack a second copy of it.
    if (currentRouteName == routeName && currentRouteArguments == arguments) {
      return;
    }
    navigatorKey.currentState?.pushNamed(routeName, arguments: arguments);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = _stack.indexOf(oldRoute!);
    if (index < 0) return;
    if (newRoute == null) {
      _stack.removeAt(index);
    } else {
      _stack[index] = newRoute;
    }
  }
}

/// The one navigator key the app installs on its `MaterialApp`.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Kept alive: the notification service reads it from a platform callback,
/// long after any screen that could have been holding a listener is gone.
@Riverpod(keepAlive: true)
AppNavigator appNavigator(Ref ref) => AppNavigator(appNavigatorKey);
