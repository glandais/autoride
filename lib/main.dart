import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'features/onboarding/data/services/onboarding_service.dart';
import 'features/onboarding/presentation/screens/onboarding_screen.dart';
import 'features/settings/presentation/screens/settings_screen.dart';
import 'features/trip_detection/data/services/trip_state_machine.dart';
import 'features/trip_detection/domain/models/trip_state.dart';
import 'features/trip_detection/presentation/screens/trip_tracking_screen.dart';
import 'features/trip_history/presentation/screens/trip_detail_screen.dart';
import 'features/trip_history/presentation/screens/trip_history_screen.dart';

// Global navigator key for auto-navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(
    const ProviderScope(
      child: AutoRideApp(),
    ),
  );
}

class AutoRideApp extends ConsumerStatefulWidget {
  const AutoRideApp({super.key});

  @override
  ConsumerState<AutoRideApp> createState() => _AutoRideAppState();
}

class _AutoRideAppState extends ConsumerState<AutoRideApp> {
  @override
  void initState() {
    super.initState();

    // Listen for trip state changes and auto-navigate to tracking screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listenManual(tripStateMachineProvider, (previous, next) {
        // Auto-navigate when trip becomes Active (from Idle or Detecting)
        final wasNotActive = previous?.map(
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
      loading: () => const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, stack) => Scaffold(
        body: Center(
          child: Text('Error: $error'),
        ),
      ),
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

    // If user manually navigates to Active Trip tab when no trip is active,
    // show Trip History instead
    if (_currentIndex == 1 && !hasActiveTrip) {
      _currentIndex = 0;
    }

    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabTapped,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.history),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.directions_bike,
              color: hasActiveTrip ? null : Colors.grey.shade400,
            ),
            selectedIcon: const Icon(Icons.directions_bike),
            label: 'Active Trip',
            enabled: hasActiveTrip,
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
