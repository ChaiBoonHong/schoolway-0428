import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:schoolway/core/preferences/app_preferences.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/l10n/app_localizations.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../auth/auth_choice_screen.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  static const routeName = '/onboarding';

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      setState(() {
        _currentPage = _pageController.page?.round() ?? 0;
      });
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onNextPressed() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : SchoolWayTheme.motionMedium,
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _onGetStartedPressed() async {
    await ref.read(appPreferencesProvider.notifier).completeOnboarding();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AuthChoiceScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    children: [
                      _OnboardingPage(
                        icon: Icons.map_outlined,
                        headline: strings.welcomeTitle,
                        description: strings.welcomeBody,
                      ),
                      _OnboardingPage(
                        icon: Icons.nfc,
                        headline: strings.boardingAlertsTitle,
                        description: strings.boardingAlertsBody,
                      ),
                      _OnboardingPage(
                        icon: Icons.shield_outlined,
                        headline: strings.safetyTitle,
                        description: strings.safetyBody,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 16.0,
                  ),
                  child: Column(
                    children: [
                      // Page Indicator
                      SmoothPageIndicator(
                        controller: _pageController,
                        count: 3,
                        effect: WormEffect(
                          dotHeight: 12,
                          dotWidth: 12,
                          activeDotColor: Theme.of(context).colorScheme.primary,
                          dotColor: Theme.of(context).colorScheme.secondary,
                          spacing: 16,
                        ),
                      ),
                      const SizedBox(height: 32),
                      // Navigation Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton(
                          onPressed: _currentPage == 2
                              ? _onGetStartedPressed
                              : _onNextPressed,
                          child: Text(
                            _currentPage == 2
                                ? strings.getStarted
                                : strings.next,
                            style: const TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ],
            ),
            if (_currentPage < 2)
              Positioned(
                top: 8,
                right: 12,
                child: TextButton(
                  onPressed: _onGetStartedPressed,
                  child: Text(
                    strings.skip,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final IconData icon;
  final String headline;
  final String description;

  const _OnboardingPage({
    required this.icon,
    required this.headline,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.schoolWayColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),
          // Illustration/Icon
          Icon(icon, size: 150, color: SchoolWayTheme.accent),
          const SizedBox(height: 48),
          // Headline
          Text(
            headline,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: colors.brandNavy,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          // Description
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: colors.mutedText,
              height: 1.5,
            ),
          ),
          const Spacer(flex: 3),
        ],
      ),
    );
  }
}
