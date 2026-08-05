import 'dart:io' show Platform;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/models/call.dart';
import '../../../core/constants/message_types.dart';
import '../../../core/services/websocket_service.dart';
import '../../../core/services/window_visibility_service.dart';
import '../../../core/call/call_presenter.dart';
import '../../../core/call/mac_call_presenter.dart';

class CallManager extends ChangeNotifier {
  Call? _currentCall;
  final WebSocketService wsService;
  final WindowVisibilityService windowVisibilityService;
  CallPresenter? callPresenter;
  final MethodChannel _platform =
      const MethodChannel('com.pakku.connect/platform');
  final MethodChannel _callPanelChannel =
      const MethodChannel('com.pakku.connect/callPanel');

  String? lastNativeError;

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _durationTimer;
  Duration callDuration = Duration.zero;
  bool isEnding = false;

  CallManager(this.wsService, this.windowVisibilityService) {
    wsService.onActionResult = handleActionResult;
    
    if (Platform.isMacOS) {
      callPresenter = MacCallPresenter();
    }

    _callPanelChannel.setMethodCallHandler((call) async {
      if (call.method == 'acceptCall') {
        answerCall();
      } else if (call.method == 'declineCall') {
        rejectCall();
      }
    });

    windowVisibilityService.addListener(_onWindowVisibilityChanged);
  }

  void _onWindowVisibilityChanged() {
    if (windowVisibilityService.isVisible) {
      callPresenter?.dismissCall();
    }
  }

  @override
  void dispose() {
    windowVisibilityService.removeListener(_onWindowVisibilityChanged);
    super.dispose();
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

    if (!windowVisibilityService.isVisible) {
      callPresenter?.showCall(_currentCall!);
    }
  }

  void handleCallState(String state) {
    if (state == 'answered') {
      if (_currentCall?.state == CallState.answeredRemotely) return; // ignore duplicate
      _currentCall?.state = CallState.answeredRemotely;
      
      if (_currentCall?.direction == CallDirection.incoming) {
        _stopwatch.start();
        _durationTimer?.cancel();

        if (!windowVisibilityService.isVisible) {
          callPresenter?.updateCall(_currentCall!, elapsedSeconds: callDuration.inSeconds);
        }

        _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          callDuration = _stopwatch.elapsed;
          notifyListeners();
          
          if (!windowVisibilityService.isVisible) {
            callPresenter?.updateCall(_currentCall!, elapsedSeconds: callDuration.inSeconds);
          }
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

      callPresenter?.dismissCall();

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
    
    callPresenter?.dismissCall();
  }
}
