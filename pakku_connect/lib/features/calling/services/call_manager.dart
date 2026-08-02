import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/models/call.dart';
import '../../../core/constants/message_types.dart';
import '../../../core/services/websocket_service.dart';

class CallManager extends ChangeNotifier {
  Call? _currentCall;
  final WebSocketService wsService;
  final MethodChannel _platform =
      const MethodChannel('com.pakku.connect/platform');

  String? lastNativeError;

  CallManager(this.wsService);

  Call? get currentCall => _currentCall;

  void handleIncoming(String phoneNumber, String? contactName) {
    if (_currentCall?.state == CallState.ringing) return;
    lastNativeError = null;
    _currentCall = Call(
      phoneNumber: phoneNumber,
      contactName: contactName,
      direction: CallDirection.incoming,
    );
    notifyListeners();
  }

  void handleCallState(String state) {
    if (state == 'answered') {
      _currentCall?.state = CallState.answeredRemotely;
      notifyListeners();
      Future.delayed(const Duration(seconds: 1), _clear);
    } else {
      _clear();
    }
  }

  Future<void> answerCall() async {
    if (_currentCall == null) return;
    _currentCall!.state = CallState.answeredRemotely; // optimistic UI only
    lastNativeError = null;
    notifyListeners();
    wsService.send({'type': MessageTypes.answerCall});
    // Authoritative dismissal still comes from handleCallState() above.
    // This timeout is a fallback in case the phone never confirms (e.g.
    // OEM-restricted device — see docs/02_TDD.md known limitations).
    Future.delayed(const Duration(seconds: 4), () {
      if (_currentCall?.state == CallState.answeredRemotely) _clear();
    });
  }

  Future<void> rejectCall() async {
    if (_currentCall == null) return;
    _currentCall!.state = CallState.declinedRemotely;
    lastNativeError = null;
    notifyListeners();
    wsService.send({'type': MessageTypes.rejectCall});
    _clear();
  }

  Future<void> dial(String number) async {
    _currentCall = Call(
      phoneNumber: number,
      direction: CallDirection.outgoing,
      state: CallState.ringing,
    );
    notifyListeners();

    if (Platform.isAndroid || Platform.isIOS) {
      try {
        await _platform.invokeMethod('makeCall', {'phoneNumber': number});
      } catch (e) {
        lastNativeError = 'Unable to place call';
        notifyListeners();
      }
    } else {
      // Mac: no local ack path yet — see docs/03_API_PROTOCOL.md §5 open items.
      wsService.send({'type': MessageTypes.dial, 'number': number});
    }
  }

  void _clear() {
    _currentCall = null;
    notifyListeners();
  }
}
