import 'dart:io';
import 'package:flutter/material.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _setup());
  }

  Future<void> _setup() async {
    if (Platform.isMacOS) {
      final ws = context.read<WebSocketService>();
      final manager = context.read<CallManager>();

      ws.onIncomingCall = (number, name) {
        manager.handleIncoming(number, name);
      };
      ws.onCallState = (state) {
        manager.handleCallState(state);
      };

      final port = dotenv.env['PAKKU_WS_PORT'] ?? '8080';
      ws.connect('wss://127.0.0.1:$port');
    } else {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('paired') ?? false) {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS) {
      return const QrPairingScreen();
    }
    return const ScanScreen();
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: ContactsTab(),
    );
  }
}
