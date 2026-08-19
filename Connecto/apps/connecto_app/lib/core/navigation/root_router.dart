import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/screens/qr_pairing_screen.dart';
import '../../features/auth/screens/scan_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/clipboard/services/clipboard_sync_manager.dart';
import '../../features/relay/services/relay_manager.dart';
import '../app/app_bootstrap_service.dart';
import '../auth/device_auth_manager.dart';
import '../../features/auth/services/pairing_service.dart';
import '../services/websocket_service.dart';
import '../services/platform_transport.dart';
import '../services/crypto_service.dart';
import '../constants/app_constants.dart';
import 'navigation_service.dart';

class RootRouter extends StatefulWidget {
  const RootRouter({super.key});

  @override
  State<RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<RootRouter> {
  bool _isLoading = true;
  bool _isPaired = false;
  bool _hasSeenOnboarding = false;
  DeviceSessionState _sessionState = DeviceSessionState.disconnected;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _setup());

    if (Platform.isAndroid) {
      // Fix: route onUnpaired through MethodChannelTransport which already owns
      // the channel, instead of registering a competing setMethodCallHandler here.
      final transport = context.read<PlatformTransport>();
      if (transport is MethodChannelTransport) {
        transport.onUnpaired = () async {
          final prefs = await SharedPreferences.getInstance();
          final wasPaired = prefs.getBool('paired') ?? false;
          if (wasPaired) {
            await clearAllPairedState(prefs);
            navigatorKey.currentState
                ?.pushNamedAndRemoveUntil('/', (route) => false);
          }
        };
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _setup() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    // Ensure background bootstrap service is instantiated
    context.read<AppBootstrapService>();

    final authManager = context.read<DeviceAuthManager>();
    _hasSeenOnboarding = await authManager.hasSeenOnboarding();

    if (Platform.isMacOS) {
      _isPaired = await authManager.isPaired();
      String? hmacSecret;

      if (_isPaired) {
        hmacSecret = await authManager.getHmacSecret();
        if (hmacSecret == null) {
          _isPaired = false;
        }
      }

      setState(() {
        _isLoading = false;
      });

      final ws = context.read<WebSocketService>();

      ws.onConnectionChange = (connected) async {
        if (!connected && mounted) {
          setState(() {
            _sessionState = DeviceSessionState.disconnected;
          });
        }
        // NOTE: do NOT trigger pairing here. On macOS, pairing completes only
        // when the Android phone's device_state:connected message arrives.
      };

      ws.onDeviceStateChanged = (newState) async {
        // Only transition to Home on the FIRST Android connection after QR scan.
        // _isPaired starts false; once we set it true we never retrigger this.
        if (!_isPaired && newState == DeviceSessionState.connected) {
          await _handleInitialPairingCompletion(authManager);
        }
        _handleSessionUpdate(newState);
      };

      ws.onUnpair = () async {
        await clearAllPairedState(prefs);
        ws.reset(); // Clears credentials so we don't reconnect with stale secret
        navigatorKey.currentState
            ?.pushNamedAndRemoveUntil('/', (route) => false);
      };


      final port = '$kRelayPort';
      
      String? certFp;
      try {
        certFp = await CryptoService.certFingerprint('certs/device.der');
      } catch (e) {
        debugPrint('WebSocketService: Could not compute local certFp: $e');
      }
      
      if (hmacSecret != null && hmacSecret.isNotEmpty) {
        if (mounted) {
          context.read<RelayManager>().setSecret(hmacSecret);
        }
        ws.connect('wss://127.0.0.1:$port', hmacSecret: hmacSecret, certFp: certFp);
      } else {
        debugPrint('Main: Waiting for pairing before WebSocket connection.');
      }
    } else {
      _isPaired = await authManager.isPaired();
      
      if (_isPaired) {
        final hmacSecret = await authManager.getHmacSecret();
        if (hmacSecret == null) {
          _isPaired = false;
        }
      }

      if (_isPaired) {
        try {
          const platform = MethodChannel('com.connecto.app/platform');
          await platform.invokeMethod('startPhoneStateService');
          // Request call screening role for caller ID on Samsung Android 16+
          try {
            await platform.invokeMethod('requestCallScreeningRole');
          } catch (_) {}
        } catch (e, st) {
          debugPrint('Failed to start PhoneStateService: $e\n$st');
        }
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleInitialPairingCompletion(DeviceAuthManager authManager) async {
    await authManager.setPaired(true);
    if (mounted) {
      setState(() {
        _isPaired = true;
      });
    }
  }

  void _handleSessionUpdate(DeviceSessionState newState) {
    if (Platform.isMacOS) {
      const menuBarChannel = MethodChannel('com.connecto.app/menuBar');
      menuBarChannel.invokeMethod('updateStatus', {'state': newState.name});
    }
    if (mounted) {
      setState(() {
        _sessionState = newState;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
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

    if (!_hasSeenOnboarding) {
      return const OnboardingScreen();
    }

    if (Platform.isMacOS) {
      if (!_isPaired) {
        return const QrPairingScreen();
      } else {
        return HomeScreen(sessionState: _sessionState);
      }
    }
    
    if (!_isPaired) {
      return const ScanScreen();
    } else {
      return HomeScreen(sessionState: _sessionState);
    }
  }
}
