import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/settings/screens/settings_screen.dart';
import '../../features/settings/services/settings_service.dart';
import '../constants/app_theme.dart';
import '../constants/app_constants.dart';
import '../services/websocket_service.dart';
import '../../features/calling/services/recent_calls_manager.dart';
import '../../features/contacts/services/favorites_service.dart';
import '../../features/share/services/share_manager.dart';
import '../../features/file_transfer/services/file_transfer_manager.dart';
import '../../features/relay/services/relay_manager.dart';
import '../services/window_visibility_service.dart';
import '../services/platform_transport.dart';
import '../../features/notifications/services/notification_manager.dart';
import '../navigation/navigation_service.dart';
import '../../features/calling/services/call_manager.dart';
import '../../features/clipboard/services/clipboard_sync_manager.dart';
import '../../features/home/screens/home_screen.dart';
import '../navigation/root_router.dart';

WebSocketService? _wsService;

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
                port: kRelayPort,
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
        ChangeNotifierProvider<SettingsService>(
          create: (_) => SettingsService(),
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
        Provider<FileTransferManager>(
          lazy: false,
          create: (ctx) => FileTransferManager(
            ctx.read<PlatformTransport>()
          ),
          dispose: (_, manager) => manager.dispose(),
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
          '/settings': (context) => const SettingsScreen(),
          '/': (_) => const RootRouter(),
          '/home': (_) => const HomeScreen(),
        },
      ),
    );
  }
}
