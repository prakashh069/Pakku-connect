import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/constants/app_theme.dart';
import 'core/services/websocket_service.dart';
import 'features/calling/services/call_manager.dart';
import 'features/calling/widgets/call_popup.dart';
import 'features/auth/screens/qr_pairing_screen.dart';
import 'features/auth/screens/scan_screen.dart';
import 'features/contacts/screens/contacts_tab.dart';

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
        Provider(create: (_) => WebSocketService()),
        ChangeNotifierProxyProvider<WebSocketService, CallManager>(
          create: (ctx) => CallManager(ctx.read<WebSocketService>()),
          update: (_, ws, previous) => previous ?? CallManager(ws),
        ),
      ],
      child: MaterialApp(
        title: 'Pakku Connect',
        theme: buildAppTheme(),
        builder: (context, child) {
          return Stack(
            children: [
              child!,
              const CallPopup(),
            ],
          );
        },
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _setup());
  }

  Future<void> _setup() async {
    final prefs = await SharedPreferences.getInstance();
    
    if (!mounted) return;

    if (Platform.isMacOS) {
      _isPaired = prefs.getBool('paired') ?? false;
      setState(() {
        _isLoading = false;
      });

      final ws = context.read<WebSocketService>();
      final manager = context.read<CallManager>();

      ws.onIncomingCall = (number, name) {
        manager.handleIncoming(number, name);
      };
      
      ws.onCallState = (state) {
        manager.handleCallState(state);
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

      final port = dotenv.env['PAKKU_WS_PORT'] ?? '8080';
      ws.connect('wss://127.0.0.1:$port');
    } else {
      _isPaired = prefs.getBool('paired') ?? false;
      if (_isPaired) {
        try {
          const platform = MethodChannel('com.pakku.connect/platform');
          await platform.invokeMethod('startPhoneStateService');
        } catch (e, st) {
          debugPrint('Failed to start PhoneStateService: $e\n$st');
        }
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      } else {
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

class HomeScreen extends StatelessWidget {
  final DeviceSessionState sessionState;

  const HomeScreen({
    super.key, 
    this.sessionState = DeviceSessionState.connected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CustomColors>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pakku Connect'),
      ),
      body: Platform.isMacOS
          ? Column(
              children: [
                if (sessionState == DeviceSessionState.disconnected)
                  Container(
                    width: double.infinity,
                    color: Colors.red.shade900,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: const Text(
                      'Phone is offline',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                const Expanded(child: ContactsTab()),
              ],
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.phonelink_ring,
                      size: 64,
                      color: colors?.accent ?? Colors.blue,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Pakku Connect Active',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colors?.lightText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Background service is running and ready to handle call & contact requests.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors?.lightText.withAlpha(178) ?? Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
