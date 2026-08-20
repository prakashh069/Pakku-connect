import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../interfaces/device_transport.dart';
import '../interfaces/relay_service.dart';
import '../constants/app_constants.dart';
import '../../features/calling/services/call_manager.dart';
import '../../features/clipboard/services/clipboard_sync_manager.dart';
import '../../features/clipboard/services/clipboard_share_coordinator.dart';
import '../services/window_visibility_service.dart';
import '../../features/share/services/share_manager.dart';

class AppBootstrapService {
  final DeviceTransport _ws;
  final CallManager _callManager;
  final ClipboardSyncManager _clipboardManager;
  final RelayService _relayManager;
  final WindowVisibilityService _windowVisibilityService;
  final ShareManager _shareManager;

  ClipboardShareCoordinator? _clipboardCoordinator;

  AppBootstrapService(
    this._ws,
    this._callManager,
    this._clipboardManager,
    this._relayManager,
    this._windowVisibilityService,
    this._shareManager,
  );

  void initialize() {
    _clipboardCoordinator = ClipboardShareCoordinator();
    _clipboardCoordinator!.attach(_clipboardManager.inboundShares);

    if (Platform.isMacOS) {
      _relayManager.start(
        port: kRelayPort,
        certPath: 'certs/device.crt',
        keyPath: 'certs/device.key',
      ).catchError((e) {
        debugPrint('Failed to start Dart Relay: $e');
      });
    }

    _windowVisibilityService.init();
    _shareManager.start();


    _ws.onIncomingCall = (callId, number, name) {
      _callManager.handleIncoming(callId, number, name);
    };

    _ws.onCallState = (callId, state) {
      _callManager.handleCallState(callId, state);
    };

    _ws.onActionResult = (action, success, error) {
      _callManager.handleActionResult(action, success, error);
    };

    const menuBarChannel = MethodChannel('com.connecto.app/menuBar');
    menuBarChannel.setMethodCallHandler((call) async {
      if (call.method == 'pause') {
        _ws.pause();
      } else if (call.method == 'resume') {
        _ws.resume();
      }
    });
  }

  void dispose() {
    _clipboardCoordinator?.dispose();
  }
}
