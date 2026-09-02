import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/permissions/providers/background_location_status.dart';
import 'core/permissions/widgets/background_location_banner.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/utils/platform_config_validator.dart';
import 'features/diagnostics/data/services/audit_log_controller.dart';
import 'features/onboarding/data/services/onboarding_service.dart';
import 'features/onboarding/presentation/screens/onboarding_screen.dart';
import 'features/settings/presentation/screens/settings_screen.dart';
import 'features/trip_detection/data/services/trip_recovery_service.dart';
import 'features/trip_detection/data/services/trip_state_machine.dart';
import 'features/trip_detection/domain/models/trip_state.dart';
import 'features/trip_detection/presentation/providers/auto_detection_controller.dart';
import 'features/trip_detection/presentation/screens/trip_tracking_screen.dart';
import 'features/trip_history/presentation/screens/trip_detail_screen.dart';
import 'features/trip_history/presentation/screens/trip_history_screen.dart';

// Global navigator key for auto-navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Validate platform configuration (debug mode only)
  await PlatformConfigValidator.printConfigStatus();

  runApp(const ProviderScope(child: AutoRideApp()));
}

class AutoRideApp extends ConsumerStatefulWidget {
  const AutoRideApp({super.key});

  @override
  ConsumerState<AutoRideApp> createState() => _AutoRideAppState();
}

class _AutoRideAppState extends ConsumerState<AutoRideApp>
    with WidgetsBindingObserver {
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Before the early return below, deliberately: `paused` is the one state
    // that matters most to the audit log, and it is exactly the one the return
    // discards. Android kills a backgrounded process without `detached` and
    // without running `ref.onDispose`, so this is the last reliable moment to
    // get the buffer onto the disk.
    unawaited(
      ref.read(auditLogControllerProvider.notifier).onLifecycleState(state),
    );

    // The user may have changed location permission in system settings while
    // the app was backgrounded; without a re-read, automatic detection would
    // stay off until the next cold start.
    if (state != AppLifecycleState.resumed) return;

    if (!ref.read(autoDetectionControllerProvider).permissionGranted) {
      ref.read(autoDetectionControllerProvider.notifier).refreshPermission();
    }

    // Unconditional: the background permission can have been downgraded as
    // well as upgraded ("Always" back to "While Using"), and the banner has to
    // follow both directions.
    ref.read(backgroundLocationStatusProvider.notifier).refresh();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Listen for trip state changes and auto-navigate to tracking screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The audit log comes first, before anything it is meant to observe:
      // instantiated after the coordinator, it would miss the session start of
      // the very launch being diagnosed.
      ref.listenManual(auditLogControllerProvider, (_, _) {});

      // Close any trip a process death left mid-recording (L-068), before
      // automatic detection below can start a new one. Fire-and-forget: the
      // provider logs its own outcome and a failure must not block launch —
      // the rows stay `active` and are retried next time.
      ref.listenManual(tripRecoveryProvider, (_, _) {});

      // Lifecycle owner for automatic detection (audit #11): instantiating it
      // here — above every screen — is what makes detection run at all. The
      // listener is what keeps it reactive: a keepAlive provider with no
      // listener would not recompute when the setting or the permission
      // changes, it would merely be invalidated.
      ref.listenManual(autoDetectionControllerProvider, (_, _) {});

      ref.listenManual(tripStateMachineProvider, (previous, next) {
        // Auto-navigate when trip becomes Active (from Idle or Detecting)
        final wasNotActive =
            previous?.map(
              idle: (_) => true,
              detecting: (_) => true,
              active: (_) => false,
              paused: (_) => false,
            ) ??
            true;

        final isNowActive = next.map(
          idle: (_) => false,
          detecting: (_) => false,
          active: (_) => true,
          paused: (_) => false,
        );

        if (wasNotActive && isNowActive) {
          // Navigate to trip tracking screen
          navigatorKey.currentState?.pushNamed('/trip-tracking');
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watch theme mode provider for dynamic theme switching
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'AutoRide',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const InitialRouteScreen(),
      routes: {
        '/home': (context) => const HomeShell(),
        '/trip-tracking': (context) => const TripTrackingScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
      onGenerateRoute: (settings) {
        // Handle trip detail route with arguments
        if (settings.name == '/trip-detail') {
          final tripId = settings.arguments as int?;
          if (tripId != null) {
            return MaterialPageRoute(
              builder: (context) => TripDetailScreen(tripId: tripId),
            );
          }
        }
        return null;
      },
    );
  }
}

/// Initial route that checks onboarding status and routes accordingly
class InitialRouteScreen extends ConsumerWidget {
  const InitialRouteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFirstLaunchAsync = ref.watch(onboardingServiceProvider);

    return isFirstLaunchAsync.when(
      data: (isFirstLaunch) {
        if (isFirstLaunch) {
          return const OnboardingScreen();
        } else {
          return const HomeShell();
        }
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stack) =>
          Scaffold(body: Center(child: Text('Error: $error'))),
    );
  }
}

/// Main navigation shell with bottom navigation bar
///
/// Contains:
/// - Trip History (main screen)
/// - Active Trip (when trip is active)
/// - Settings
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _currentIndex = 0;

  // Screens for each tab
  static const List<Widget> _screens = [
    TripHistoryScreen(),
    TripTrackingScreen(),
    SettingsScreen(),
  ];

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tripState = ref.watch(tripStateMachineProvider);
    final hasActiveTrip = tripState.hasActiveTrip;

    // The Trip tab is always reachable: with no trip running it is where the
    // manual start button lives (audit #11 — the app previously had no way to
    // start a trip at all, and this tab was permanently disabled).
    return Scaffold(
      body: _screens[_currentIndex],
      // The banner sits between the tab content and the navigation bar: each
      // tab owns its app bar, so the top of the shell would put it above the
      // title and under the status bar.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BackgroundLocationBanner(),
          NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: _onTabTapped,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.history),
                selectedIcon: Icon(Icons.history),
                label: 'History',
              ),
              NavigationDestination(
                icon: const Icon(Icons.directions_bike),
                selectedIcon: const Icon(Icons.directions_bike),
                label: hasActiveTrip ? 'Active Trip' : 'Trip',
              ),
              const NavigationDestination(
                icon: Icon(Icons.settings),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
