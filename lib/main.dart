import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'features/onboarding/data/services/onboarding_service.dart';
import 'features/onboarding/presentation/screens/onboarding_screen.dart';
import 'shared/providers/app_state_provider.dart';
import 'shared/providers/example_provider.dart';

void main() {
  runApp(
    const ProviderScope(
      child: AutoRideApp(),
    ),
  );
}

class AutoRideApp extends ConsumerWidget {
  const AutoRideApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch theme mode provider for dynamic theme switching
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'AutoRide',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const InitialRouteScreen(),
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
    );
  }
}
