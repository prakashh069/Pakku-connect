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
    if (_currentCall == null) return;
    if (callId.isNotEmpty && _currentCall!.callId != callId) {
      // Stale or unrelated message
      return;
    }

    if (state == 'answered') {
      if (_currentCall!.state == CallState.answeredRemotely) return; // duplicate
      _currentCall!.state = CallState.answeredRemotely;

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
      // Ignore duplicate
      notifyListeners();
    } else if (state == 'ended') {
      if (_currentCall!.state == CallState.ended) return; // duplicate
      
      _transitionToEnded();
    }
  }

  void _transitionToEnding() {
    if (_currentCall == null || isEnding) return;
    
    isEnding = true;
    notifyListeners();

    _endTimeoutTimer?.cancel();
    _endTimeoutTimer = Timer(kCallEndTimeout, () {
      if (isEnding && _currentCall?.state != CallState.ended) {
        _transitionToEnded();
      }
    });
  }

  void _transitionToEnded() {
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
    if (action == 'end_call' && !success) {
      // Android failed to process end_call, but we are in Ending state.
      // We will let the timeout force the cleanup instead of leaving UI stuck.
      lastNativeError = error ?? 'Failed to end call';
      notifyListeners();
    } else if (action == 'dial' && !success) {
      lastNativeError = error ?? 'Failed to dial';
      _transitionToEnded(); // Explicitly end local tracking
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
    _transitionToEnding();
    wsService.send({'type': MessageTypes.rejectCall, 'callId': _currentCall!.callId});
  }

  Future<void> cancelOutgoingCall() async {
    if (_currentCall == null || _currentCall!.direction != CallDirection.outgoing) return;
    lastNativeError = null;
    _transitionToEnding();
    wsService.send({'type': MessageTypes.rejectCall, 'callId': _currentCall!.callId});
  }

  Future<void> endCall() async {
    if (_currentCall == null) return;
    lastNativeError = null;
    _transitionToEnding();
    wsService.send({'type': MessageTypes.endCall, 'callId': _currentCall!.callId});
  }

  Future<void> dial(String number, {String? contactName}) async {
    if (Platform.isMacOS && !wsService.isConnected) {
      lastNativeError = 'Cannot make call: Phone is disconnected';
      notifyListeners();
      return;
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
    _currentCall = null;
    notifyListeners();
    
    callPresenter?.dismissCall();
  }
}
