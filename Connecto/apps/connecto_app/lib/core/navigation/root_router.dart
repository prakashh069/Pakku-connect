import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/screens/qr_pairing_screen.dart';
import '../../features/auth/screens/scan_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/clipboard/services/clipboard_sync_manager.dart';
import '../../features/clipboard/services/clipboard_share_coordinator.dart';
import '../../features/calling/services/call_manager.dart';
import '../../features/relay/services/relay_manager.dart';
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
  ClipboardShareCoordinator? _clipboardCoordinator;

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
    _clipboardCoordinator?.dispose();
    super.dispose();
  }

  Future<void> _setup() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    // Wire ClipboardShareCoordinator to receive validated inbound clipboard events (both macOS and Android).
    final clipManager = context.read<ClipboardSyncManager>();
    _clipboardCoordinator = ClipboardShareCoordinator();
    _clipboardCoordinator!.attach(clipManager.inboundShares);
    
    _hasSeenOnboarding = prefs.getBool('onboarding_complete') ?? false;

    if (Platform.isMacOS) {
      _isPaired = prefs.getBool('paired') ?? false;
      String? hmacSecret;

      if (_isPaired) {
        try {
          const secureStorage = FlutterSecureStorage(
            mOptions: MacOsOptions(
              usesDataProtectionKeychain: !kDebugMode,
            ),
          );
          hmacSecret = await secureStorage.read(key: 'hmacSecret');
          if (hmacSecret != null) {
            debugPrint('Keychain read success');
          }
          
          // Migration from insecure SharedPreferences
          final insecureSecret = prefs.getString('hmacSecret');
          if (insecureSecret != null) {
            if (hmacSecret == null) {
              await secureStorage.write(key: 'hmacSecret', value: insecureSecret);
              hmacSecret = insecureSecret;
              debugPrint('Main: Migrated hmacSecret from SharedPreferences to Keychain');
            }
            await prefs.remove('hmacSecret');
          }
        } catch (e) {
          debugPrint('Main: Keychain failed: $e');
        }
        if (hmacSecret == null) {
          // Paired but no secret — force unpair so we don't loop forever.
          await prefs.setBool('paired', false);
          _isPaired = false;
        }
      }

      setState(() {
        _isLoading = false;
      });

      final ws = context.read<WebSocketService>();
      final manager = context.read<CallManager>();

      ws.onIncomingCall = (callId, number, name) {
        manager.handleIncoming(callId, number, name);
      };

      ws.onCallState = (callId, state) {
        manager.handleCallState(callId, state);
      };

      ws.onActionResult = (action, success, error) {
        manager.handleActionResult(action, success, error);
      };

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
          await _handleInitialPairingCompletion(prefs);
        }
        _handleSessionUpdate(newState);
      };

      ws.onUnpair = () async {
        await clearAllPairedState(prefs);
        ws.reset(); // Clears credentials so we don't reconnect with stale secret
        navigatorKey.currentState
            ?.pushNamedAndRemoveUntil('/', (route) => false);
      };

      const menuBarChannel = MethodChannel('com.connecto.app/menuBar');
      menuBarChannel.setMethodCallHandler((call) async {
        if (call.method == 'pause') {
          ws.pause();
        } else if (call.method == 'resume') {
          ws.resume();
        }
      });

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
      _isPaired = prefs.getBool('paired') ?? false;
      
      if (_isPaired) {
        const secureStorage = FlutterSecureStorage();
        String? hmacSecret;
        try {
          hmacSecret = await secureStorage.read(key: 'hmacSecret');
          
          // Migration from insecure SharedPreferences
          final insecureSecret = prefs.getString('hmacSecret');
          if (insecureSecret != null) {
            if (hmacSecret == null) {
              await secureStorage.write(key: 'hmacSecret', value: insecureSecret);
              hmacSecret = insecureSecret;
              debugPrint('Main: Migrated hmacSecret to SecureStorage');
            }
            await prefs.remove('hmacSecret');
          }
        } catch (e) {
          debugPrint('Main: secure storage failed: $e');
        }
        if (hmacSecret == null) {
          await prefs.setBool('paired', false);
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

  Future<void> _handleInitialPairingCompletion(SharedPreferences prefs) async {
    await prefs.setBool('paired', true);
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
