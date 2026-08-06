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
    // We no longer dismiss the native panel when the app window is visible, 
    // because the native panel is now the only call interface.
  }

  @override
  void dispose() {
    windowVisibilityService.removeListener(_onWindowVisibilityChanged);
    super.dispose();
  }

  Call? get currentCall => _currentCall;

  bool _isSamePhoneNumber(String a, String b) {
    final cleanA = a.replaceAll(RegExp(r'\D'), '');
    final cleanB = b.replaceAll(RegExp(r'\D'), '');
    if (cleanA.isEmpty || cleanB.isEmpty) return false;
    if (cleanA == cleanB) return true;
    // Country code fallback: compare the ends if they are reasonably long (>= 7 digits)
    if (cleanA.length >= 7 && cleanB.length >= 7) {
      if (cleanA.endsWith(cleanB) || cleanB.endsWith(cleanA)) {
        return true;
      }
    }
    return false;
  }

  String? _resolveContactName(String phoneNumber, String? providedName) {
    if (providedName != null && providedName.isNotEmpty) {
      return providedName;
    }
    for (final contact in wsService.cachedContacts) {
      for (final p in contact.phones) {
        if (_isSamePhoneNumber(p.number, phoneNumber)) {
          return contact.displayName;
        }
      }
    }
    return providedName;
  }

  void handleIncoming(String phoneNumber, String? contactName) {
    if (_currentCall?.state == CallState.ringing) return;
    lastNativeError = null;

    final resolvedName = _resolveContactName(phoneNumber, contactName);

    _currentCall = Call(
      phoneNumber: phoneNumber,
      contactName: resolvedName,
      direction: CallDirection.incoming,
    );
    notifyListeners();

    callPresenter?.showCall(_currentCall!);
  }

  void handleCallState(String state) {
    if (state == 'answered') {
      if (_currentCall?.state == CallState.answeredRemotely) return;
      _currentCall?.state = CallState.answeredRemotely;

      _stopwatch.start();
      _durationTimer?.cancel();
      callPresenter?.updateCall(_currentCall!, elapsedSeconds: callDuration.inSeconds);

      _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        callDuration = _stopwatch.elapsed;
        notifyListeners();
        callPresenter?.updateCall(_currentCall!, elapsedSeconds: callDuration.inSeconds);
      });

      notifyListeners();
    } else if (state == 'dialing') {
      notifyListeners();
    } else if (state == 'ended') {
      if (_currentCall?.state == CallState.ended) return;
      _durationTimer?.cancel();
      _stopwatch.stop();
      _currentCall?.state = CallState.ended;
      isEnding = false;
      notifyListeners();

      callPresenter?.updateCall(_currentCall!, elapsedSeconds: callDuration.inSeconds);

      Future.delayed(const Duration(seconds: 3), () {
        callPresenter?.dismissCall();
      });

      Future.delayed(const Duration(seconds: 4), _clear);
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
    if (_currentCall == null) return;
    lastNativeError = null;
    notifyListeners();
    wsService.send({'type': MessageTypes.rejectCall});
  }

  Future<void> cancelOutgoingCall() async {
    if (_currentCall == null || _currentCall!.direction != CallDirection.outgoing) return;
    lastNativeError = null;
    notifyListeners();
    wsService.send({'type': MessageTypes.rejectCall});
  }

  Future<void> endCall() async {
    if (_currentCall == null) return;
    isEnding = true;
    lastNativeError = null;
    notifyListeners();
    wsService.send({'type': MessageTypes.endCall});
  }

  Future<void> dial(String number, {String? contactName}) async {
    final cleanNumber = number.replaceAll(RegExp(r'[^\d+]'), '');
    final resolvedName = _resolveContactName(cleanNumber, contactName);

    _currentCall = Call(
      phoneNumber: cleanNumber,
      contactName: resolvedName,
      direction: CallDirection.outgoing,
      state: CallState.ringing,
    );
    notifyListeners();

    callPresenter?.showCall(_currentCall!);

    if (Platform.isAndroid || Platform.isIOS) {
      try {
        await _platform.invokeMethod('makeCall', {'phoneNumber': cleanNumber});
      } catch (e) {
        lastNativeError = 'Unable to place call';
        notifyListeners();
      }
    } else {
      wsService.send({'type': MessageTypes.dial, 'number': cleanNumber});
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
