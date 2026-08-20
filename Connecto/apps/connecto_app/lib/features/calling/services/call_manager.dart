import 'dart:io' show Platform;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/models/call.dart';
import '../../../core/constants/message_types.dart';
import '../../../core/interfaces/device_transport.dart';
import '../../../core/services/window_visibility_service.dart';
import '../../../core/call/call_presenter.dart';
import '../../../core/call/mac_call_presenter.dart';

class CallManager extends ChangeNotifier {
  Call? _currentCall;
  final DeviceTransport wsService;
  final WindowVisibilityService windowVisibilityService;
  CallPresenter? callPresenter;
  final MethodChannel _platform =
      const MethodChannel('com.connecto.app/platform');
  final MethodChannel _callPanelChannel =
      const MethodChannel('com.connecto.app/callPanel');

  String? lastNativeError;

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _durationTimer;
  Duration callDuration = Duration.zero;
  bool isEnding = false;
  bool _isEnded = false; // Guards against _transitionToEnded() being called multiple times

  final List<Call> _callHistory = [];
  List<Call> get callHistory => List.unmodifiable(_callHistory);

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

  static const kCallEndTimeout = Duration(seconds: 3);
  Timer? _endTimeoutTimer;

  void handleIncoming(String callId, String phoneNumber, String? contactName) {
    if (_currentCall != null) {
      if (_currentCall!.callId == callId) return; // duplicate
      if (!isEnding) return; // ignore incoming if we have an active call
    }
    
    lastNativeError = null;
    final resolvedName = _resolveContactName(phoneNumber, contactName);

    _currentCall = Call(
      callId: callId.isEmpty ? null : callId,
      phoneNumber: phoneNumber,
      contactName: resolvedName,
      direction: CallDirection.incoming,
      state: CallState.ringing,
    );
    notifyListeners();
    callPresenter?.showCall(_currentCall!);
  }

  void handleCallState(String callId, String state) {
    debugPrint('CALL_EVENT_RECEIVED: state=$state callId=$callId currentCallId=${_currentCall?.callId}');
    
    if (_currentCall == null) {
      if (state == 'ended') {
        _transitionToEnded(); // ensure cleanup just in case
      }
      return;
    }

    if (callId.isNotEmpty && _currentCall!.callId != callId) {
      // Stale or unrelated message
      return;
    }

    if (state == 'ended') {
      if (_currentCall!.state == CallState.ended) return; // duplicate
      _transitionToEnded();
      return;
    }

    if (state == 'active') {
      if (_currentCall!.state == CallState.active) return; // duplicate
      _currentCall!.state = CallState.active;

      _stopwatch.reset(); // Ensure stopwatch is fresh when call goes active
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
      // Do not start the timer while dialing. 
      // The UI already shows "Calling..." from the initial showCall.
    }
  }


  void _transitionToEnded() {
    if (_currentCall == null) return;
    
    // Idempotency guard — prevents double-dismiss when both action_result
    // and call_state:ended arrive in rapid succession.
    if (_isEnded) return;
    _isEnded = true;

    _endTimeoutTimer?.cancel();
    _durationTimer?.cancel();
    _stopwatch.stop();

    if (_currentCall != null) {
      _currentCall!.state = CallState.ended;
      isEnding = false;
      _callHistory.insert(0, _currentCall!);
      if (_callHistory.length > 100) {
        _callHistory.removeLast();
      }
      callPresenter?.updateCall(_currentCall!, elapsedSeconds: callDuration.inSeconds);
    }
    
    notifyListeners();

    // Dismiss panel slightly after updating it with "Ended"
    Future.delayed(const Duration(milliseconds: 1500), () {
      callPresenter?.dismissCall();
    });

    // Cleanup state completely
    Future.delayed(const Duration(milliseconds: 2000), _clear);
  }

  void handleActionResult(String action, bool success, String? error) {
    if ((action == 'end_call' || action == 'reject_call') && !success) {
      // Android failed to process end/reject call.
      lastNativeError = error ?? 'Failed to $action';
      notifyListeners();
    } else if ((action == 'dial' || action == 'answer_call') && !success) {
      lastNativeError = error ?? 'Failed to $action';
      _transitionToEnded(); // Explicitly end local tracking
    } else if (action == 'answer_call' && success) {
      debugPrint('CallManager: answer_call successful, waiting for call_state: active from Android');
    }
  }

  Future<void> answerCall() async {
    if (_currentCall == null) return;
    lastNativeError = null;
    notifyListeners();
    wsService.send({'type': MessageTypes.answerCall, 'callId': _currentCall!.callId});
  }

  Future<void> rejectCall() async {
    if (_currentCall == null) return;
    lastNativeError = null;
    wsService.send({'type': MessageTypes.rejectCall, 'callId': _currentCall!.callId});
  }

  Future<void> cancelOutgoingCall() async {
    if (_currentCall == null || _currentCall!.direction != CallDirection.outgoing) return;
    lastNativeError = null;
    wsService.send({'type': MessageTypes.rejectCall, 'callId': _currentCall!.callId});
  }

  Future<void> endCall() async {
    if (_currentCall == null) return;
    lastNativeError = null;
    wsService.send({'type': MessageTypes.endCall, 'callId': _currentCall!.callId});
  }

  Future<void> dial(String number, {String? contactName}) async {
    if (Platform.isMacOS) {
      if (!wsService.isConnected || wsService.deviceState != DeviceSessionState.connected) {
        lastNativeError = 'Phone is offline. Connect your phone to make calls.';
        notifyListeners();
        return;
      }
    }

    if (_currentCall != null && !isEnding) {
      // Intercept accidental double dial, reshow the current call popup
      callPresenter?.showCall(_currentCall!);
      return;
    }

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
        await _platform.invokeMethod('makeCall', {'phoneNumber': cleanNumber, 'callId': _currentCall!.callId});
      } catch (e) {
        lastNativeError = 'Unable to place call';
        _transitionToEnded();
      }
    } else {
      wsService.send({'type': MessageTypes.dial, 'number': cleanNumber, 'callId': _currentCall!.callId});
    }
  }

  void _clear() {
    _endTimeoutTimer?.cancel();
    _durationTimer?.cancel();
    _stopwatch.stop();
    _stopwatch.reset();
    callDuration = Duration.zero;
    isEnding = false;
    _isEnded = false; // Reset so the next call can use _transitionToEnded() cleanly
    _currentCall = null;
    notifyListeners();
    
    callPresenter?.dismissCall();
  }
}
