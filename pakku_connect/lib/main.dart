import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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
import 'core/services/window_visibility_service.dart';
import 'core/services/platform_transport.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
WebSocketService? _wsService;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const PakkuApp());
}

class PakkuApp extends StatelessWidget {
  const PakkuApp({super.key});

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
      ],
      child: MaterialApp(
        title: 'Pakku Connect',
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
            await prefs.setBool('paired', false);
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

      ws.onConnectionChange = (connected) {
        if (!connected && mounted) {
          setState(() {
            _sessionState = DeviceSessionState.disconnected;
          });
        }
      };

      ws.onDeviceStateChanged = (newState) async {
        if (!_isPaired && newState == DeviceSessionState.connected) {
          await _handleInitialPairingCompletion(prefs);
        }
        _handleSessionUpdate(newState);
      };

      ws.onUnpair = () async {
        await prefs.setBool('paired', false);
        ws.disconnect();
        navigatorKey.currentState
            ?.pushNamedAndRemoveUntil('/', (route) => false);
      };

      const menuBarChannel = MethodChannel('com.pakku.connect/menuBar');
      menuBarChannel.setMethodCallHandler((call) async {
        if (call.method == 'pause') {
          ws.pause();
        } else if (call.method == 'resume') {
          ws.resume();
        }
      });

      final port = dotenv.env['PAKKU_WS_PORT'] ?? '8080';
      ws.connect('wss://127.0.0.1:$port');
    } else {
      _isPaired = prefs.getBool('paired') ?? false;
      if (_isPaired) {
        try {
          const platform = MethodChannel('com.pakku.connect/platform');
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
      const menuBarChannel = MethodChannel('com.pakku.connect/menuBar');
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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

  Widget _buildAndroidLayout(
      BuildContext context, CustomColors colors, WebSocketService ws) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.phonelink_ring,
              size: 64,
              color: colors.accent,
            ),
            const SizedBox(height: 16),
            Text(
              'Pakku Connect Active',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colors.lightText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Background service is running and ready to handle call & contact requests.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.lightText.withAlpha(178),
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
        ? '🟢 Connected'
        : (widget.sessionState == DeviceSessionState.paused
            ? '⏸ Paused'
            : '🔴 Offline');
    final contactCount = ws.cachedContacts.length;

    return Container(
      color: colors.background.withAlpha(240),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(statusText,
                style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ),
          const SizedBox(height: 8),
          Divider(color: colors.surface, thickness: 1, height: 1),
          const SizedBox(height: 16),
          _buildMacStatusRow('Device', 'Unknown', colors),
          _buildMacStatusRow('Contacts', '$contactCount', colors),
          _buildMacStatusRow('Last Sync', 'Unknown', colors),
        ],
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
                ? Colors.orange.shade900
                : (widget.sessionState == DeviceSessionState.connecting ||
                        widget.sessionState == DeviceSessionState.reconnecting)
                    ? Colors.blue.shade900
                    : Colors.red.shade900,
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
                        children: const [
                          KeypadTab(),
                          RecentCallsTab(),
                          ContactsTab(),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pakku Connect'),
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
                                        'com.pakku.connect/platform');
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
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('paired', false);

              if (Platform.isMacOS) {
                if (context.mounted) {
                  ws.send({'type': 'unpair'});
                  await Future.delayed(const Duration(milliseconds: 500));
                  ws.disconnect();
                }
              } else {
                const platform = MethodChannel('com.pakku.connect/platform');
                await platform.invokeMethod('unpair');
              }

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
