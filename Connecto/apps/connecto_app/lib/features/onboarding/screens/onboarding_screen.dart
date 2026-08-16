import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/onboarding_slide.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
    });
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                physics: const BouncingScrollPhysics(),
                children: const [
                  OnboardingSlide(
                    icon: Icons.devices_rounded,
                    title: "Your Android and Mac,\nconnected instantly.",
                    subtitle: "Connecto seamlessly bridges your devices over local Wi-Fi.",
                  ),
                  OnboardingSlide(
                    icon: Icons.send_to_mobile_rounded,
                    title: "Share Everything",
                    subtitle: "Send photos, files, and documents instantly.\nNo cables. No cloud.",
                  ),
                  OnboardingSlide(
                    icon: Icons.content_copy_rounded,
                    title: "Universal Clipboard",
                    subtitle: "Copy on one device.\nPaste on the other.",
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      3,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.symmetric(horizontal: 4.0),
                        width: _currentPage == index ? 24.0 : 8.0,
                        height: 8.0,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? theme.primaryColor
                              : (isDark ? Colors.white24 : Colors.black12),
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: _currentPage == 2
                        ? SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: _completeOnboarding,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.primaryColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text(
                                "Get Started",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                        : SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: TextButton(
                              onPressed: () {
                                _pageController.nextPage(
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeOutCubic,
                                );
                              },
                              style: TextButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Text(
                                "Next",
                                style: TextStyle(
                                  fontSize: 18,
                                  color: isDark ? Colors.white70 : Colors.black54,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
