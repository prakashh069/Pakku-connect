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
import '../interfaces/device_transport.dart';
import '../interfaces/native_platform_bridge.dart';
import '../messaging/message_bus.dart';
import '../messaging/app_message_bus.dart';
import '../interfaces/relay_service.dart';
import '../services/platform_transport.dart' show MethodChannelTransport;
import '../services/window_visibility_service.dart';
import '../../features/notifications/services/notification_manager.dart';
import '../../features/calling/services/call_manager.dart';
import '../../features/clipboard/services/clipboard_sync_manager.dart';
import '../app/app_bootstrap_service.dart';
import '../app/app_initialization_coordinator.dart';
import '../interfaces/auth_manager.dart';
import '../interfaces/connection_manager.dart';
import '../interfaces/platform_integration.dart';
import '../interfaces/startup_coordinator.dart';

class AppProviders extends StatelessWidget {
  final Widget child;
  const AppProviders({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthManager>(
          create: (_) => DeviceAuthManager(),
        ),
        Provider<RelayService>(
          create: (_) => RelayManager(),
          dispose: (_, rm) => (rm as RelayManager).stop(),
        ),
        Provider<DeviceTransport>(
          create: (_) => WebSocketService(),
        ),
        Provider<ConnectionManager>(
          create: (ctx) => AppConnectionManager(
            ctx.read<DeviceTransport>(),
            ctx.read<RelayService>(),
          ),
        ),
        Provider<PlatformIntegration>(
          create: (_) => PlatformIntegrationService(),
        ),
        Provider(
          create: (_) => WindowVisibilityService(),
          dispose: (_, wvs) => wvs.dispose(),
        ),
        ChangeNotifierProxyProvider2<DeviceTransport, WindowVisibilityService,
            CallManager>(
          create: (ctx) => CallManager(ctx.read<DeviceTransport>(),
              ctx.read<WindowVisibilityService>()),
          update: (_, ws, wvs, previous) => previous ?? CallManager(ws, wvs),
        ),
        ChangeNotifierProxyProvider<DeviceTransport, RecentCallsManager>(
          lazy: false,
          create: (ctx) => RecentCallsManager(ctx.read<DeviceTransport>()),
          update: (_, ws, previous) => previous ?? RecentCallsManager(ws),
        ),
        ChangeNotifierProvider(create: (_) => FavoritesService()),
        Provider<NativePlatformBridge?>(
          create: (ctx) => Platform.isMacOS
              ? null
              : MethodChannelTransport(),
          dispose: (_, pt) => pt?.dispose(),
        ),
        ChangeNotifierProvider<SettingsService>(
          create: (_) => SettingsService(),
        ),
        Provider<MessageBus>(
          lazy: false,
          create: (ctx) => AppMessageBus(
            deviceTransport: ctx.read<DeviceTransport>(),
            nativeBridge: ctx.read<NativePlatformBridge?>(),
          ),
          dispose: (_, bus) => bus.dispose(),
        ),
        ChangeNotifierProxyProvider<MessageBus, ClipboardSyncManager>(
          lazy: false,
          create: (ctx) => ClipboardSyncManager(
            messageBus: ctx.read<MessageBus>(),
          ),
          update: (_, mb, previous) => previous ?? ClipboardSyncManager(messageBus: mb),
        ),
        ProxyProvider<MessageBus, ShareManager>(
          lazy: false,
          create: (ctx) => ShareManager(
            messageBus: ctx.read<MessageBus>(),
          )..start(),
          update: (_, mb, previous) => previous ?? ShareManager(messageBus: mb),
        ),
        ProxyProvider<MessageBus, FileTransferManager>(
          lazy: false,
          create: (ctx) => FileTransferManager(
            messageBus: ctx.read<MessageBus>(),
          ),
          update: (_, mb, previous) => previous ?? FileTransferManager(messageBus: mb),
        ),
        ChangeNotifierProxyProvider<MessageBus, NotificationManager>(
          lazy: false,
          create: (ctx) => Platform.isMacOS
              ? NotificationManager(ctx.read<MessageBus>())
              : NotificationManager(null),
          update: (_, mb, previous) =>
              previous ??
              (Platform.isMacOS
                  ? NotificationManager(mb)
                  : NotificationManager(null)),
        ),
        Provider<AppBootstrapService>(
          lazy: false,
          create: (ctx) => AppBootstrapService(
            ctx.read<DeviceTransport>(),
            ctx.read<CallManager>(),
            ctx.read<ClipboardSyncManager>(),
            ctx.read<RelayService>(),
            ctx.read<WindowVisibilityService>(),
            ctx.read<ShareManager>(),
          )..initialize(),
          dispose: (_, svc) => svc.dispose(),
        ),
        ChangeNotifierProvider<StartupCoordinator>(
          lazy: false,
          create: (ctx) => AppInitializationCoordinator(
            ctx.read<AuthManager>(),
            ctx.read<ConnectionManager>(),
            ctx.read<DeviceTransport>(),
            ctx.read<PlatformIntegration>(),
            ctx.read<NativePlatformBridge?>(),
          )..initialize(),
        ),
      ],
      child: child,
    );
  }
}
