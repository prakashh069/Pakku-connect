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

  bool _isSamePhoneNumber(String a, String b) {
    final cleanA = a.replaceAll(RegExp(r'\D'), '');
    final cleanB = b.replaceAll(RegExp(r'\D'), '');
    debugPrint("DEBUG-CALL: Comparing cleanA=$cleanA with cleanB=$cleanB");
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
    debugPrint("DEBUG-CALL: Resolving contact for incoming phone number: $phoneNumber");
    if (providedName != null && providedName.isNotEmpty) {
      debugPrint("DEBUG-CALL: Provided name exists: $providedName");
      return providedName;
    }
    final cleanTarget = phoneNumber.replaceAll(RegExp(r'\D'), '');
    debugPrint("DEBUG-CALL: Normalized phone number: $cleanTarget");
    debugPrint("DEBUG-CALL: Number of synchronized contacts: ${wsService.cachedContacts.length}");
    
    for (final contact in wsService.cachedContacts) {
      for (final p in contact.phones) {
        if (_isSamePhoneNumber(p.number, phoneNumber)) {
          debugPrint("DEBUG-CALL: Matching contact found: true");
          debugPrint("DEBUG-CALL: Resolved contact name: ${contact.displayName}");
          return contact.displayName;
        }
      }
    }
    debugPrint("DEBUG-CALL: Matching contact found: false");
    debugPrint("DEBUG-CALL: Resolved contact name: Unknown");
    return providedName;
  }

  void handleIncoming(String phoneNumber, String? contactName) {
    final timestamp = DateTime.now().toIso8601String();
    debugPrint("[$timestamp] INSTRUMENTATION-CHAIN: ENTER CallManager.handleIncoming(phoneNumber: $phoneNumber)");
    
    if (_currentCall?.state == CallState.ringing) {
      debugPrint("[$timestamp] INSTRUMENTATION-CHAIN: EXIT CallManager.handleIncoming (already ringing)");
      return;
    }
    lastNativeError = null;
    
    final resolvedName = _resolveContactName(phoneNumber, contactName);

    _currentCall = Call(
      phoneNumber: phoneNumber,
      contactName: resolvedName,
      direction: CallDirection.incoming,
    );
    notifyListeners();

    final isVisible = windowVisibilityService.isVisible;
    debugPrint("[$timestamp] INSTRUMENTATION-CHAIN: windowVisibilityService.isVisible = $isVisible");
    
    debugPrint("[$timestamp] INSTRUMENTATION-CHAIN: Calling CallPresenter.showCall()");
    callPresenter?.showCall(_currentCall!);
    
    debugPrint("[$timestamp] INSTRUMENTATION-CHAIN: EXIT CallManager.handleIncoming");
  }

  void handleCallState(String state) {
    final timestamp = DateTime.now().toIso8601String();
    debugPrint("[$timestamp] INSTRUMENTATION-CHAIN: ENTER CallManager.handleCallState(state: $state)");
    
    if (state == 'answered') {
      if (_currentCall?.state == CallState.answeredRemotely) {
        debugPrint("[$timestamp] INSTRUMENTATION-CHAIN: EXIT CallManager.handleCallState (already answeredRemotely)");
        return;
      }
      _currentCall?.state = CallState.answeredRemotely;
      
      _stopwatch.start();
      _durationTimer?.cancel();

      debugPrint("[$timestamp] INSTRUMENTATION-CHAIN: Calling CallPresenter.updateCall (0s)");
      callPresenter?.updateCall(_currentCall!, elapsedSeconds: callDuration.inSeconds);

      _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        callDuration = _stopwatch.elapsed;
        notifyListeners();
        
        callPresenter?.updateCall(_currentCall!, elapsedSeconds: callDuration.inSeconds);
      });
      
      notifyListeners();
    } else if (state == 'dialing') {
      // Outgoing call started dialing — keep "Calling..." state, no timer
      // Timer will start when Android detects the receiver picks up (audio mode change)
      // and sends 'answered'
      debugPrint("[$timestamp] INSTRUMENTATION-CHAIN: Outgoing call dialing (waiting for receiver to pick up)");
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

  Future<void> dial(String number, {String? contactName}) async {
    final cleanNumber = number.replaceAll(RegExp(r'[^\d+]'), '');
    debugPrint("INSTRUMENTATION: dial invoked for number: $number (cleaned: $cleanNumber)");
    
    final resolvedName = _resolveContactName(cleanNumber, contactName);

    _currentCall = Call(
      phoneNumber: cleanNumber,
      contactName: resolvedName,
      direction: CallDirection.outgoing,
      state: CallState.ringing,
    );
    notifyListeners();

    // Show native popup for outgoing call
    callPresenter?.showCall(_currentCall!);

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
