import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/constants/app_theme.dart';
import 'core/services/websocket_service.dart';
import 'features/calling/services/call_manager.dart';
import 'features/calling/services/recent_calls_manager.dart';
import 'features/auth/screens/qr_pairing_screen.dart';
import 'features/auth/screens/scan_screen.dart';
import 'features/calling/screens/keypad_tab.dart';
import 'features/calling/screens/recent_calls_tab.dart';
import 'features/contacts/screens/contacts_tab.dart';
import 'features/contacts/services/favorites_service.dart';
import 'features/clipboard/services/clipboard_sync_manager.dart';
import 'features/clipboard/services/clipboard_share_coordinator.dart';
import 'features/share/services/share_manager.dart';
import 'features/relay/services/relay_manager.dart';
import 'core/services/window_visibility_service.dart';
import 'core/services/platform_transport.dart';
import 'core/services/crypto_service.dart';
import 'features/notifications/services/notification_manager.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
WebSocketService? _wsService;

Future<void> clearAllPairedState(SharedPreferences prefs) async {
  await prefs.setBool('paired', false);
  try {
    const secureStorage = FlutterSecureStorage(
      mOptions: MacOsOptions(
        usesDataProtectionKeychain: !kDebugMode,
      ),
    );
    await secureStorage.delete(key: 'hmacSecret');
    await secureStorage.delete(key: 'ws_ip');
    await secureStorage.delete(key: 'ws_port');
    await secureStorage.delete(key: 'cert_fp');
  } catch (_) {}
  await prefs.remove('hmacSecret');
  await prefs.remove('ws_ip');
  await prefs.remove('ws_port');
  await prefs.remove('cert_fp');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ConnectoApp());
}

class ConnectoApp extends StatelessWidget {
  const ConnectoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<WebSocketService>(
          create: (_) {
            _wsService = WebSocketService();
            return _wsService!;
          },
        ),
        Provider<RelayManager>(
          lazy: false,
          create: (_) {
            final rm = RelayManager();
            if (Platform.isMacOS) {
              rm.start(
                port: 8080,
                certPath: 'certs/device.crt',
                keyPath: 'certs/device.key',
              ).catchError((e) {
                debugPrint('Failed to start Dart Relay: $e');
              });
            }
            return rm;
          },
          dispose: (_, rm) => rm.stop(),
        ),
        Provider(
          create: (_) => WindowVisibilityService()..init(),
          dispose: (_, wvs) => wvs.dispose(),
        ),
        ChangeNotifierProxyProvider2<WebSocketService, WindowVisibilityService,
            CallManager>(
          create: (ctx) => CallManager(ctx.read<WebSocketService>(),
              ctx.read<WindowVisibilityService>()),
          update: (_, ws, wvs, previous) => previous ?? CallManager(ws, wvs),
        ),
        ChangeNotifierProxyProvider<WebSocketService, RecentCallsManager>(
          lazy: false,
          create: (ctx) => RecentCallsManager(ctx.read<WebSocketService>()),
          update: (_, ws, previous) => previous ?? RecentCallsManager(ws),
        ),
        ChangeNotifierProvider(create: (_) => FavoritesService()),
        Provider<PlatformTransport>(
          create: (ctx) => Platform.isMacOS
              ? ctx.read<WebSocketService>()
              : MethodChannelTransport(),
          dispose: (_, pt) => pt.dispose(),
        ),
        ChangeNotifierProxyProvider<PlatformTransport, ClipboardSyncManager>(
          lazy: false,
          create: (ctx) => ClipboardSyncManager(ctx.read<PlatformTransport>()),
          update: (_, pt, previous) => previous ?? ClipboardSyncManager(pt),
        ),
        Provider<ShareManager>(
          lazy: false,
          create: (ctx) => ShareManager(
            ctx.read<PlatformTransport>()
          )..start(),
          dispose: (_, sm) => sm.stop(),
        ),
        ChangeNotifierProxyProvider<PlatformTransport, NotificationManager>(
          lazy: false,
          create: (ctx) =>
              NotificationManager(ctx.read<PlatformTransport>()),
          update: (_, pt, previous) => previous ?? NotificationManager(pt),
        ),
      ],
      child: MaterialApp(
        title: 'Connecto',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: buildAppTheme(isDark: false),
        darkTheme: buildAppTheme(isDark: true),
        themeMode: ThemeMode.system,
        initialRoute: '/',
        routes: {
          '/': (_) => const RootRouter(),
          '/home': (_) => const HomeScreen(),
        },
      ),
    );
  }
}

class RootRouter extends StatefulWidget {
  const RootRouter({super.key});

  @override
  State<RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<RootRouter> {
  bool _isLoading = true;
  bool _isPaired = false;
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

      final port = '8080';
      
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

    if (Platform.isMacOS) {
      if (!_isPaired) {
        return const QrPairingScreen();
      } else {
        return HomeScreen(sessionState: _sessionState);
      }
    }
    return const ScanScreen();
  }
}

class HomeScreen extends StatefulWidget {
  final DeviceSessionState sessionState;

  const HomeScreen({
    super.key,
    this.sessionState = DeviceSessionState.connected,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 2; // Default to Contacts
  Map<String, dynamic>? _batteryData;
  String _phoneMode = 'normal';
  String _previousPhoneMode = 'normal';
  bool _phoneModeUpdating = false;
  bool _flashlightOn = false;
  bool _isRinging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ws = context.read<WebSocketService>();
      ws.onBatteryStatus = (data) {
        if (mounted) {
          setState(() {
            _batteryData = data;
          });
        }
      };
      ws.onDeviceState = (data) {
        if (mounted) {
          setState(() {
            if (data['ringing'] != null) _isRinging = data['ringing'] == true;
            if (data['flashlight'] != null) _flashlightOn = data['flashlight'] == true;
          });
        }
      };
      ws.onActionStatus = (action, status, error, data) {
        if (!mounted) return;
        if (action == 'ring') {
          if (status == 'success' && data['enabled'] != null) {
            setState(() {
              _isRinging = data['enabled'] == true;
            });
          }
        } else if (action == 'flashlight') {
          if (status == 'success' && data['enabled'] != null) {
            setState(() {
              _flashlightOn = data['enabled'] == true;
            });
          }
        } else if (action == 'set_ringer_mode') {
          if (status == 'permission_required') {
            setState(() { _phoneMode = _previousPhoneMode; _phoneModeUpdating = false; });
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Grant Do Not Disturb access on your phone.')));
          } else if (status == 'success') {
            setState(() => _phoneModeUpdating = false);
          } else {
            setState(() { _phoneMode = _previousPhoneMode; _phoneModeUpdating = false; });
          }
        } else if (action == 'lock' && status == 'permission_required') {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enable Device Admin on your phone.')));
        } else if (status == 'error') {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $error')));
        }
      };
    });
  }

  Widget _buildAndroidLayout(
      BuildContext context, CustomColors colors, WebSocketService ws) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: colors.success.withAlpha(26),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.phonelink_ring,
                        size: 28, color: colors.success),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Connecto Active',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Background service running',
                    style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    height: 1,
                    color: colors.border,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.circle,
                          size: 8, color: colors.success),
                      const SizedBox(width: 8),
                      Text(
                        'Ready for call & contact requests',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('paired', false);
                if (context.mounted) {
                  Navigator.of(context).pushReplacementNamed('/');
                }
              },
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Unpair & Scan New Mac'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.primary,
                side: BorderSide(color: colors.primary.withAlpha(160)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMacStatusRow(String label, String value, CustomColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(color: colors.lightText, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                  color: colors.lightText.withAlpha(178), fontSize: 13),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacStatusPanel(
      BuildContext context, CustomColors colors, WebSocketService ws) {
    final isConnected = widget.sessionState == DeviceSessionState.connected;
    final statusText = isConnected
        ? '● Connected'
        : (widget.sessionState == DeviceSessionState.paused
            ? '● Paused'
            : '● Offline');
    final statusColor = isConnected
        ? Colors.green
        : (widget.sessionState == DeviceSessionState.paused ? Colors.orange : Colors.red);
    final contactCount = ws.cachedContacts.length;

    Widget batteryWidget = const SizedBox();
    if (_batteryData != null) {
      final level = _batteryData!['level'] as int? ?? 0;
      final charging = _batteryData!['charging'] as bool? ?? false;
      
      batteryWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('$level%', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: colors.lightText)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(charging ? Icons.battery_charging_full : Icons.battery_full, size: 16, color: colors.lightText.withAlpha(150)),
              const SizedBox(width: 6),
              Text('Battery', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: colors.lightText.withAlpha(150))),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: level / 100.0,
              minHeight: 4,
              backgroundColor: Colors.white.withAlpha(20),
              valueColor: AlwaysStoppedAnimation<Color>(charging ? colors.accent : Colors.white.withAlpha(200)),
            ),
          ),
          if (charging) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bolt, size: 16, color: colors.accent),
                const SizedBox(width: 4),
                Text('Charging', style: TextStyle(fontSize: 13, color: colors.accent, fontWeight: FontWeight.w500)),
              ],
            )
          ],
        ],
      );
    } else {
      batteryWidget = const Center(child: Text('Battery\nUnknown', textAlign: TextAlign.center, style: TextStyle(fontSize: 13)));
    }

    return Container(
      width: 280,
      color: colors.background.withAlpha(240),
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
      child: ListView(
        children: [
          Row(
            children: [
              Text(statusText,
                  style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
            ],
          ),
          const SizedBox(height: 32),
          batteryWidget,
          const SizedBox(height: 32),
          Text('Phone Mode', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: colors.lightText)),
          const SizedBox(height: 12),
          _buildPhoneModeSegmentedControl(colors, ws),
          const SizedBox(height: 32),
          Text('Quick Actions', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: colors.lightText)),
          const SizedBox(height: 12),
          _buildQuickActions(colors, ws),
          const SizedBox(height: 32),
          _buildMacStatusRow('Contacts', '$contactCount', colors),
          const SizedBox(height: 8),
          _buildMacStatusRow('Last Sync', 'Just now', colors),
        ],
      ),
    );
  }

  Widget _buildPhoneModeSegmentedControl(CustomColors colors, WebSocketService ws) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: colors.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              _buildPhoneModeSegment('normal', Icons.notifications_none, 'Normal', colors, ws),
              _buildPhoneModeSegment('vibrate', Icons.vibration, 'Vibrate', colors, ws),
              _buildPhoneModeSegment('silent', Icons.notifications_off, 'Silent', colors, ws),
            ],
          ),
        ),
        if (_phoneModeUpdating)
          const CircularProgressIndicator(),
      ],
    );
  }

  Widget _buildPhoneModeSegment(String mode, IconData icon, String tooltip, CustomColors colors, WebSocketService ws) {
    final isSelected = _phoneMode == mode;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _previousPhoneMode = _phoneMode;
            _phoneMode = mode;
            _phoneModeUpdating = true;
          });
          ws.setRingerMode(mode);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? colors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(2),
          child: Center(
            child: Icon(
              icon,
              size: 20,
              color: isSelected ? Colors.white : colors.lightText.withAlpha(120),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(CustomColors colors, WebSocketService ws) {
    return Column(
      children: [
        _buildActionTile(
          icon: Icons.flashlight_on,
          title: 'Flashlight',
          isActive: _flashlightOn,
          colors: colors,
          onTap: () {
            ws.sendDeviceAction('flashlight', enabled: !_flashlightOn);
          },
        ),
        _buildActionTile(
          icon: Icons.notifications_active,
          title: 'Ring Phone',
          isActive: _isRinging,
          colors: colors,
          onTap: () {
            ws.sendDeviceAction('ring', enabled: !_isRinging);
          },
        ),
        _buildActionTile(
          icon: Icons.lock_outline,
          title: 'Lock',
          isActive: false,
          colors: colors,
          onTap: () => ws.sendDeviceAction('lock'),
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required bool isActive,
    required CustomColors colors,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 56,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colors.surface2,
            border: Border.all(
              color: isActive ? colors.accent.withAlpha(150) : colors.border,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: colors.accent.withAlpha(50),
                      blurRadius: 12,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: isActive ? colors.accent : colors.lightText),
              const SizedBox(width: 12),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    maxLines: 1,
                    style: TextStyle(
                      color: isActive ? colors.accent : colors.lightText,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMacLayout(
      BuildContext context, CustomColors colors, WebSocketService ws) {
    return Column(
      children: [
        if (widget.sessionState == DeviceSessionState.disconnected ||
            widget.sessionState == DeviceSessionState.reconnecting ||
            widget.sessionState == DeviceSessionState.connecting ||
            widget.sessionState == DeviceSessionState.paused)
          Container(
            width: double.infinity,
            color: widget.sessionState == DeviceSessionState.paused
                ? colors.warning.withAlpha(220)
                : (widget.sessionState == DeviceSessionState.connecting ||
                        widget.sessionState == DeviceSessionState.reconnecting)
                    ? colors.primary.withAlpha(220)
                    : colors.danger.withAlpha(220),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              widget.sessionState == DeviceSessionState.paused
                  ? 'Connection paused'
                  : (widget.sessionState == DeviceSessionState.connecting ||
                          widget.sessionState ==
                              DeviceSessionState.reconnecting)
                      ? 'Connecting...'
                      : 'Phone is offline',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IndexedStack(
                        index: _currentIndex,
                        children: [
                          KeypadTab(isActive: _currentIndex == 0),
                          const RecentCallsTab(),
                          const ContactsTab(),
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Container(
                          width: 260, // concise width
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(50),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(30),
                            child: NavigationBar(
                              selectedIndex: _currentIndex,
                              onDestinationSelected: (idx) {
                                setState(() {
                                  _currentIndex = idx;
                                });
                                if (idx != 0) {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                }
                              },
                              height: 52, // smaller height
                              elevation: 0,
                              backgroundColor: Colors.transparent,
                              indicatorColor: colors.accent.withAlpha(80),
                              labelBehavior:
                                  NavigationDestinationLabelBehavior.alwaysHide,
                              destinations: const [
                                NavigationDestination(
                                    icon: Icon(Icons.dialpad, size: 22),
                                    label: 'Keypad'),
                                NavigationDestination(
                                    icon: Icon(Icons.history, size: 22),
                                    label: 'Recents'),
                                NavigationDestination(
                                    icon: Icon(Icons.contacts, size: 22),
                                    label: 'Contacts'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, color: colors.surface),
              SizedBox(
                  width: 180, child: _buildMacStatusPanel(context, colors, ws)),
            ],
          ),
        ),

      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CustomColors>()!;
    final ws = context.watch<WebSocketService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logoAsset = isDark
        ? 'assets/images/connecto_logo_dark.png'
        : 'assets/images/connecto_logo_light.png';

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 50,
        title: Image.asset(
          logoAsset,
          height: 34,
          fit: BoxFit.contain,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) {
                  return AlertDialog(
                    title: const Text('Settings'),
                    content: Consumer<ClipboardSyncManager>(
                      builder: (context, clipboardManager, child) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CheckboxListTile(
                              title: const Text('Enable Universal Clipboard'),
                              value: clipboardManager.enabled,
                              onChanged: (val) {
                                if (val != null) {
                                  clipboardManager.setEnabled(val);
                                }
                              },
                            ),
                            if (Platform.isAndroid)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0, vertical: 8.0),
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.flash_on),
                                  label: const Text('Enable Auto-Paste'),
                                  onPressed: () {
                                    const platform = MethodChannel(
                                        'com.connecto.app/platform');
                                    platform.invokeMethod(
                                        'requestOverlayPermission');
                                  },
                                ),
                              ),
                            if (Platform.isAndroid)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16.0),
                                child: Text(
                                  'Requires "Display over other apps" permission to instantly paste text copied from your Mac in the background.',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Disconnect',
            onPressed: () async {
              // Step 1: Try to notify other device (best-effort, non-blocking) before closing socket
              if (Platform.isMacOS) {
                try {
                  await ws.send({'type': 'unpair'});
                  await Future.delayed(const Duration(milliseconds: 100)); // allow flush
                } catch (_) {}
              } else {
                try {
                  const platform = MethodChannel('com.connecto.app/platform');
                  platform.invokeMethod('unpair');
                } catch (_) {}
              }

              // Step 2: Clear all local paired state immediately (no network needed)
              final prefs = await SharedPreferences.getInstance();
              await clearAllPairedState(prefs);
              ws.reset(); // Clears credentials so we can't reconnect with stale secret

              // Step 3: Always navigate away regardless of network state
              if (context.mounted) {
                Navigator.of(context)
                    .pushNamedAndRemoveUntil('/', (route) => false);
              }
            },
          ),
        ],
      ),
      body: Platform.isMacOS
          ? _buildMacLayout(context, colors, ws)
          : _buildAndroidLayout(context, colors, ws),
    );
  }
}
