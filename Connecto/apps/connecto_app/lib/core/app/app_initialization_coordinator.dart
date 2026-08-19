import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/device_auth_manager.dart';
import '../connection/app_connection_manager.dart';
import '../platform/platform_integration_service.dart';
import '../services/websocket_service.dart';
import '../services/platform_transport.dart';
import '../constants/app_constants.dart';
import '../../features/auth/services/pairing_service.dart';
import '../navigation/navigation_service.dart';

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

class AppInitializationCoordinator extends ChangeNotifier {
  final DeviceAuthManager _authManager;
  final AppConnectionManager _connectionManager;
  final WebSocketService _ws;
  final PlatformIntegrationService _platformService;
  final PlatformTransport _transport;

  StartupState _state = StartupState();
  StartupState get state => _state;

  AppInitializationCoordinator(
    this._authManager,
    this._connectionManager,
    this._ws,
    this._platformService,
    this._transport,
  );

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    _setupAndroidTransport(prefs);

    bool hasSeenOnboarding = await _authManager.hasSeenOnboarding();
    
    _updateState((s) => s.copyWith(hasSeenOnboarding: hasSeenOnboarding));

    if (Platform.isMacOS) {
      bool isPaired = await _authManager.isPaired();
      String? hmacSecret;

      if (isPaired) {
        hmacSecret = await _authManager.getHmacSecret();
        if (hmacSecret == null) {
          isPaired = false;
        } else {
          await _connectionManager.startConnection(hmacSecret);
        }
      }

      _updateState((s) => s.copyWith(isPaired: isPaired, isLoading: false));

      _ws.onConnectionChange = (connected) {
        if (!connected) {
          _updateState((s) => s.copyWith(sessionState: DeviceSessionState.disconnected));
        }
      };

      _ws.onDeviceStateChanged = (newState) async {
        if (!_state.isPaired && newState == DeviceSessionState.connected) {
          await _authManager.setPaired(true);
          _updateState((s) => s.copyWith(isPaired: true));
        }
        _platformService.updateMacOsMenuBarStatus(newState.name);
        _updateState((s) => s.copyWith(sessionState: newState));
      };

      _ws.onUnpair = () async {
        await clearAllPairedState(prefs);
        _ws.reset();
        navigatorKey.currentState?.pushNamedAndRemoveUntil('/', (route) => false);
      };

    } else {
      bool isPaired = await _authManager.isPaired();
      
      if (isPaired) {
        final hmacSecret = await _authManager.getHmacSecret();
        if (hmacSecret == null) {
          isPaired = false;
        }
      }

      if (isPaired) {
        await _platformService.startAndroidPhoneStateService();
      }
      
      _updateState((s) => s.copyWith(isPaired: isPaired, isLoading: false));
    }
  }

  void _setupAndroidTransport(SharedPreferences prefs) {
    if (Platform.isAndroid && _transport is MethodChannelTransport) {
      final t = _transport as MethodChannelTransport;
      t.onUnpaired = () async {
        final wasPaired = prefs.getBool('paired') ?? false;
        if (wasPaired) {
          await clearAllPairedState(prefs);
          navigatorKey.currentState?.pushNamedAndRemoveUntil('/', (route) => false);
        }
      };
    }
  }

  void _updateState(StartupState Function(StartupState) updater) {
    _state = updater(_state);
    notifyListeners();
  }
}
