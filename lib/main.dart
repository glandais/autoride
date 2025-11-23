import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'features/onboarding/data/services/onboarding_service.dart';
import 'features/onboarding/presentation/screens/onboarding_screen.dart';
import 'features/trip_detection/data/services/trip_state_machine.dart';
import 'features/trip_detection/domain/models/trip_state.dart';
import 'features/trip_detection/presentation/screens/trip_tracking_screen.dart';
import 'shared/providers/app_state_provider.dart';
import 'shared/providers/example_provider.dart';

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
        ) ?? true;

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
        '/trip-tracking': (context) => const TripTrackingScreen(),
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
          return const HomePage();
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

/// Home page demonstrating Riverpod usage
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch providers - rebuilds when state changes
    final counter = ref.watch(counterProvider);
    final welcomeMsg = ref.watch(welcomeMessageProvider);
    final appState = ref.watch(appStateProvider);
    final tripState = ref.watch(tripStateMachineProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AutoRide - Riverpod Demo'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Welcome message
            Text(
              welcomeMsg,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 32),

            // Counter display
            Text(
              'Counter: $counter',
              style: Theme.of(context).textTheme.displayMedium,
            ),
            const SizedBox(height: 16),

            // Counter controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () => ref.read(counterProvider.notifier).decrement(),
                  child: const Icon(Icons.remove),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () => ref.read(counterProvider.notifier).reset(),
                  child: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () => ref.read(counterProvider.notifier).increment(),
                  child: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // App state display
            Text(
              'App State: ${appState.name}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),

            // Example of family provider
            Text(
              '5 × 3 = ${ref.watch(multiplyProvider(5, 3))}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
      // Show FAB when there's an active trip for manual access to tracking screen
      floatingActionButton: tripState.hasActiveTrip
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(context).pushNamed('/trip-tracking');
              },
              icon: const Icon(Icons.directions_bike),
              label: const Text('View Trip'),
              backgroundColor: Theme.of(context).colorScheme.primary,
            )
          : null,
    );
  }
}
