import 'dart:io' show Platform;
import 'dart:async';
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

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _durationTimer;
  Duration callDuration = Duration.zero;
  bool isEnding = false;

  CallManager(this.wsService) {
    wsService.onActionResult = handleActionResult;
  }

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
      if (_currentCall?.state == CallState.answeredRemotely) return; // ignore duplicate
      _currentCall?.state = CallState.answeredRemotely;
      
      if (_currentCall?.direction == CallDirection.incoming) {
        _stopwatch.start();
        _durationTimer?.cancel();
        _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          callDuration = _stopwatch.elapsed;
          notifyListeners();
        });
      }
      
      notifyListeners();
    } else if (state == 'ended') {
      if (_currentCall?.state == CallState.ended) return; // ignore duplicate
      _durationTimer?.cancel();
      _stopwatch.stop();
      _currentCall?.state = CallState.ended;
      isEnding = false;
      notifyListeners();
      Future.delayed(const Duration(seconds: 2), _clear);
    }
  }

  void handleActionResult(String action, bool success, String? error) {
    if (action == 'end_call' && !success) {
      isEnding = false;
      lastNativeError = error ?? 'Failed to end call';
      notifyListeners();
    }
  }

  Future<void> answerCall() async {
    if (_currentCall == null) return;
    // Don't optimistically set answeredRemotely. Let the source of truth handle it.
    lastNativeError = null;
    notifyListeners();
    wsService.send({'type': MessageTypes.answerCall});
  }

  Future<void> rejectCall() async {
    debugPrint("INSTRUMENTATION: rejectCall invoked.");
    if (_currentCall == null) return;
    lastNativeError = null;
    notifyListeners();
    debugPrint("INSTRUMENTATION: rejectCall sending reject_call over wsService");
    wsService.send({'type': MessageTypes.rejectCall});
  }

  Future<void> cancelOutgoingCall() async {
    final timestamp = DateTime.now().toIso8601String();
    debugPrint("[$timestamp] INSTRUMENTATION: cancelOutgoingCall invoked.");
    if (_currentCall == null || _currentCall!.direction != CallDirection.outgoing) {
        debugPrint("[$timestamp] INSTRUMENTATION: cancelOutgoingCall aborted. _currentCall=$_currentCall");
        return;
    }
    lastNativeError = null;
    notifyListeners();
    final payload = {'type': MessageTypes.rejectCall};
    debugPrint("[$timestamp] INSTRUMENTATION: cancelOutgoingCall sending JSON payload over wsService: $payload");
    wsService.send(payload);
  }

  Future<void> endCall() async {
    final timestamp = DateTime.now().toIso8601String();
    debugPrint("[$timestamp] INSTRUMENTATION: endCall invoked.");
    if (_currentCall == null) return;
    isEnding = true;
    lastNativeError = null;
    notifyListeners();
    final payload = {'type': MessageTypes.endCall};
    debugPrint("[$timestamp] INSTRUMENTATION: endCall sending JSON payload over wsService: $payload");
    wsService.send(payload);
  }

  Future<void> dial(String number) async {
    final cleanNumber = number.replaceAll(RegExp(r'[^\d+]'), '');
    debugPrint("INSTRUMENTATION: dial invoked for number: $number (cleaned: $cleanNumber)");
    _currentCall = Call(
      phoneNumber: cleanNumber,
      direction: CallDirection.outgoing,
      state: CallState.ringing,
    );
    notifyListeners();

    if (Platform.isAndroid || Platform.isIOS) {
      try {
        await _platform.invokeMethod('makeCall', {'phoneNumber': cleanNumber});
      } catch (e) {
        lastNativeError = 'Unable to place call';
        notifyListeners();
      }
    } else {
      debugPrint('INSTRUMENTATION: dial sending dial over wsService'); wsService.send({'type': MessageTypes.dial, 'number': cleanNumber});
    }
  }

  void _clear() {
    _durationTimer?.cancel();
    _stopwatch.stop();
    _stopwatch.reset();
    callDuration = Duration.zero;
    isEnding = false;
    _currentCall = null;
    notifyListeners();
  }
}
