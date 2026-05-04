import 'package:flutter/material.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../auth/auth_choice_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const routeName = '/onboarding';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
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
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onGetStartedPressed() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AuthChoiceScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFCAF0F8),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    children: const [
                      _OnboardingPage(
                        icon: Icons.map_outlined,
                        headline: 'Welcome to SchoolWay',
                        description:
                            'Track your child\'s kindergarten bus in real-time. No more guessing, just peace of mind.',
                      ),
                      _OnboardingPage(
                        icon: Icons.nfc,
                        headline: 'Instant Boarding Alerts',
                        description:
                            'Receive immediate notifications the moment your child taps their NFC card to board or exit the bus.',
                      ),
                      _OnboardingPage(
                        icon: Icons.shield_outlined,
                        headline: 'All-in-One Safety',
                        description:
                            'A unified, secure platform for parents, drivers, and kindergarten staff. Let\'s get started!',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Column(
                    children: [
                      // Page Indicator
                      SmoothPageIndicator(
                        controller: _pageController,
                        count: 3,
                        effect: const WormEffect(
                          dotHeight: 12,
                          dotWidth: 12,
                          activeDotColor: Color(0xFF0077B6),
                          dotColor: Color(0xFF00B4D8),
                          spacing: 16,
                        ),
                      ),
                      const SizedBox(height: 32),
                      // Navigation Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _currentPage == 2 ? _onGetStartedPressed : _onNextPressed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0077B6),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 2,
                          ),
                          child: Text(
                            _currentPage == 2 ? 'Get Started' : 'Next',
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
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0077B6),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),
          // Illustration/Icon
          Icon(
            icon,
            size: 150,
            color: const Color(0xFF00B4D8),
          ),
          const SizedBox(height: 48),
          // Headline
          Text(
            headline,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF03045E),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          // Description
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: Color(0xFF03045E),
              height: 1.5,
            ),
          ),
          const Spacer(flex: 3),
        ],
      ),
    );
  }
}


