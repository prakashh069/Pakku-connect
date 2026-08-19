import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';
import '../services/websocket_service.dart';

class StartupState {
  final bool isLoading;
  final bool isPaired;
  final bool hasSeenOnboarding;
  final DeviceSessionState sessionState;

  StartupState({
    this.isLoading = true,
    this.isPaired = false,
    this.hasSeenOnboarding = false,
    this.sessionState = DeviceSessionState.disconnected,
  });

  StartupState copyWith({
    bool? isLoading,
    bool? isPaired,
    bool? hasSeenOnboarding,
    DeviceSessionState? sessionState,
  }) {
    return StartupState(
      isLoading: isLoading ?? this.isLoading,
      isPaired: isPaired ?? this.isPaired,
      hasSeenOnboarding: hasSeenOnboarding ?? this.hasSeenOnboarding,
      sessionState: sessionState ?? this.sessionState,
    );
  }
}

abstract class StartupCoordinator extends ChangeNotifier {
  StartupState get state;
  Future<void> initialize();
}
