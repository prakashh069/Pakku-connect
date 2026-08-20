import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../interfaces/auth_manager.dart';
import '../interfaces/connection_manager.dart';
import '../interfaces/platform_integration.dart';
import '../interfaces/startup_coordinator.dart';
import '../interfaces/device_transport.dart';
import '../interfaces/native_platform_bridge.dart';
import '../constants/app_constants.dart';
import '../../features/auth/services/pairing_service.dart';
import '../navigation/navigation_service.dart';

class AppInitializationCoordinator extends ChangeNotifier implements StartupCoordinator {
  final AuthManager _authManager;
  final ConnectionManager _connectionManager;
  final DeviceTransport _ws;
  final PlatformIntegration _platformService;
  final NativePlatformBridge? _nativeBridge;

  StartupState _state = StartupState();
  StartupState get state => _state;

  AppInitializationCoordinator(
    this._authManager,
    this._connectionManager,
    this._ws,
    this._platformService,
    this._nativeBridge,
  );

  Future<void> initialize() async {
    debugPrint('[INIT_START] AppInitializationCoordinator.initialize() called. platform=macOS:${Platform.isMacOS}');
    final prefs = await SharedPreferences.getInstance();

    _setupAndroidTransport(prefs);

    bool hasSeenOnboarding = await _authManager.hasSeenOnboarding();
    debugPrint('[AUTH_STATE] hasSeenOnboarding=$hasSeenOnboarding');
    
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

      debugPrint('[AUTH_STATE] isPaired(raw)=$isPaired hmacSecret=${hmacSecret != null ? "present" : "null"}');
      _updateState((s) => s.copyWith(isPaired: isPaired, isLoading: false));
      debugPrint('[PAIRING_STATE] macOS final state: isPaired=$isPaired isLoading=false');

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
        resetToUnpaired();
        navigatorKey.currentState?.pushNamedAndRemoveUntil('/', (route) => false);
      };

    } else {
      bool isPaired = await _authManager.isPaired();
      debugPrint('[AUTH_STATE] Android isPaired(raw)=$isPaired');
      
      if (isPaired) {
        final hmacSecret = await _authManager.getHmacSecret();
        debugPrint('[AUTH_STATE] Android hmacSecret=${hmacSecret != null ? "present" : "null"}');
        if (hmacSecret == null) {
          isPaired = false;
        }
      }

      if (isPaired) {
        await _platformService.startAndroidPhoneStateService();
      }
      
      _updateState((s) => s.copyWith(isPaired: isPaired, isLoading: false));
      debugPrint('[PAIRING_STATE] Android final state: isPaired=$isPaired isLoading=false');
    }
  }

  void _setupAndroidTransport(SharedPreferences prefs) {
    if (Platform.isAndroid && _nativeBridge != null) {
      _nativeBridge!.onUnpaired = () async {
        final wasPaired = prefs.getBool('paired') ?? false;
        if (wasPaired) {
          await clearAllPairedState(prefs);
        }
        resetToUnpaired();
        navigatorKey.currentState?.pushNamedAndRemoveUntil('/', (route) => false);
      };
    }
  }

  void _updateState(StartupState Function(StartupState) updater) {
    _state = updater(_state);
    notifyListeners();
  }

  @override
  void resetToUnpaired() {
    _updateState((s) => s.copyWith(isPaired: false, sessionState: DeviceSessionState.disconnected));
  }

  Future<void> refreshAuthState() async {
    bool hasSeenOnboarding = await _authManager.hasSeenOnboarding();
    bool isPaired = await _authManager.isPaired();
    if (isPaired) {
      final hmacSecret = await _authManager.getHmacSecret();
      if (hmacSecret == null) {
        isPaired = false;
      }
    }
    _updateState((s) => s.copyWith(
      hasSeenOnboarding: hasSeenOnboarding,
      isPaired: isPaired,
    ));
  }
}
