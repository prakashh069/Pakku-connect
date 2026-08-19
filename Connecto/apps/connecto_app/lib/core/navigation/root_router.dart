import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../interfaces/startup_coordinator.dart';
import '../pairing/device_pairing_coordinator.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/home/screens/home_screen.dart';

class RootRouter extends StatelessWidget {
  const RootRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final coordinator = context.watch<StartupCoordinator>();
    final state = coordinator.state;

    if (state.isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Branded loading splash — logo + indicator
              LayoutBuilder(builder: (ctx, _) {
                final isDark = MediaQuery.platformBrightnessOf(ctx) == Brightness.dark;
                return Image.asset(
                  isDark
                      ? 'assets/images/connecto_logo_dark.png'
                      : 'assets/images/connecto_logo_light.png',
                  height: 40,
                  fit: BoxFit.contain,
                );
              }),
              const SizedBox(height: 28),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ],
          ),
        ),
      );
    }

    if (!state.hasSeenOnboarding) {
      return const OnboardingScreen();
    }

    if (!state.isPaired) {
      return const DevicePairingCoordinator();
    }
    
    return HomeScreen(sessionState: state.sessionState);
  }
}
