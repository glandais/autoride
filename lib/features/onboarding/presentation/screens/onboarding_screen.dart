import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_page_indicator.dart';
import 'welcome_screen.dart';
import 'features_screen.dart';
import 'location_permission_screen.dart';
import 'background_permission_screen.dart';
import 'setup_complete_screen.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  @override
  void dispose() {
    ref.read(onboardingProvider.notifier).dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar with Skip Button
            if (state.currentPage < 4)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back Button (if not first page)
                    if (state.currentPage > 0)
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => notifier.previousPage(),
                      )
                    else
                      const SizedBox(width: 48),

                    // Page Indicator
                    OnboardingPageIndicator(
                      currentPage: state.currentPage,
                      pageCount: 5,
                    ),

                    // Skip Button (if not on permission screens)
                    if (state.currentPage < 2)
                      TextButton(
                        onPressed: () => notifier.skip(),
                        child: const Text('Skip'),
                      )
                    else
                      const SizedBox(width: 48),
                  ],
                ),
              ),

            // Page View
            Expanded(
              child: PageView(
                controller: notifier.pageController,
                onPageChanged: (page) => notifier.updatePage(page),
                physics: const NeverScrollableScrollPhysics(), // Disable swipe
                children: const [
                  WelcomeScreen(),
                  FeaturesScreen(),
                  LocationPermissionScreen(),
                  BackgroundPermissionScreen(),
                  SetupCompleteScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
