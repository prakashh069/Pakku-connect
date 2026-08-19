import 'package:flutter/services.dart';

import '../services/websocket_service.dart';
import '../../features/calling/services/call_manager.dart';
import '../../features/clipboard/services/clipboard_sync_manager.dart';
import '../../features/clipboard/services/clipboard_share_coordinator.dart';

class AppBootstrapService {
  final WebSocketService _ws;
  final CallManager _callManager;
  final ClipboardSyncManager _clipboardManager;

  ClipboardShareCoordinator? _clipboardCoordinator;

  AppBootstrapService(this._ws, this._callManager, this._clipboardManager);

  void initialize() {
    _clipboardCoordinator = ClipboardShareCoordinator();
    _clipboardCoordinator!.attach(_clipboardManager.inboundShares);

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
