import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/settings/services/settings_service.dart';
import '../constants/app_constants.dart';
import '../auth/device_auth_manager.dart';
import '../services/websocket_service.dart';
import '../../features/calling/services/recent_calls_manager.dart';
import '../../features/contacts/services/favorites_service.dart';
import '../../features/share/services/share_manager.dart';
import '../../features/file_transfer/services/file_transfer_manager.dart';
import '../../features/relay/services/relay_manager.dart';
import '../connection/app_connection_manager.dart';
import '../platform/platform_integration_service.dart';
import '../services/window_visibility_service.dart';
import '../services/platform_transport.dart';
import '../../features/notifications/services/notification_manager.dart';
import '../../features/calling/services/call_manager.dart';
import '../../features/clipboard/services/clipboard_sync_manager.dart';
import '../app/app_bootstrap_service.dart';
import '../app/app_initialization_coordinator.dart';

class AppProviders extends StatelessWidget {
  final Widget child;
  const AppProviders({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<DeviceAuthManager>(
          create: (_) => DeviceAuthManager(),
        ),
        Provider<WebSocketService>(
          create: (_) => WebSocketService(),
        ),
        Provider<RelayManager>(
          lazy: false,
          create: (_) => RelayManager(),
          dispose: (_, rm) => rm.stop(),
        ),
        Provider<AppConnectionManager>(
          create: (ctx) => AppConnectionManager(
            ctx.read<WebSocketService>(),
            ctx.read<RelayManager>(),
          ),
        ),
        Provider<PlatformIntegrationService>(
          create: (_) => PlatformIntegrationService(),
        ),
        Provider(
          create: (_) => WindowVisibilityService(),
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
          ),
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
        Provider<AppBootstrapService>(
          lazy: false,
          create: (ctx) => AppBootstrapService(
            ctx.read<WebSocketService>(),
            ctx.read<CallManager>(),
            ctx.read<ClipboardSyncManager>(),
            ctx.read<RelayManager>(),
            ctx.read<WindowVisibilityService>(),
            ctx.read<ShareManager>(),
          )..initialize(),
          dispose: (_, svc) => svc.dispose(),
        ),
        ChangeNotifierProvider<AppInitializationCoordinator>(
          lazy: false,
          create: (ctx) => AppInitializationCoordinator(
            ctx.read<DeviceAuthManager>(),
            ctx.read<AppConnectionManager>(),
            ctx.read<WebSocketService>(),
            ctx.read<PlatformIntegrationService>(),
            ctx.read<PlatformTransport>(),
          )..initialize(),
        ),
      ],
      child: child,
    );
  }
}
