import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pakku_connect/core/models/call.dart';
import 'call_presenter.dart';

class MacCallPresenter implements CallPresenter {
  final MethodChannel _channel = const MethodChannel('com.pakku.connect/callPanel');

  @override
  void showCall(Call call) {
    final timestamp = DateTime.now().toIso8601String();
    debugPrint("[$timestamp] INSTRUMENTATION-CHAIN: ENTER MacCallPresenter.showCall()");
    debugPrint("[$timestamp] INSTRUMENTATION-CHAIN: Payload: name=${call.contactName}, number=${call.phoneNumber}, state=${call.state.name}");
    
    _channel.invokeMethod('showCall', {
      'name': call.contactName,
      'number': call.phoneNumber,
      'state': call.state.name,
    }).then((_) {
      debugPrint("[$timestamp] INSTRUMENTATION-CHAIN: EXIT MacCallPresenter.showCall (MethodChannel success)");
    }).catchError((e) {
      debugPrint("[$timestamp] INSTRUMENTATION-CHAIN: EXIT MacCallPresenter.showCall (MethodChannel error: $e)");
    });
  }

  @override
  void updateCall(Call call, {int elapsedSeconds = 0}) {
    final timestamp = DateTime.now().toIso8601String();
    debugPrint("[$timestamp] INSTRUMENTATION-CHAIN: ENTER MacCallPresenter.updateCall(state: ${call.state.name}, elapsed: $elapsedSeconds)");
    _channel.invokeMethod('updateCall', {
      'state': call.state.name,
      'elapsedSeconds': elapsedSeconds,
    }).then((_) {
      debugPrint("[$timestamp] INSTRUMENTATION-CHAIN: EXIT MacCallPresenter.updateCall (MethodChannel success)");
    }).catchError((e) {
      debugPrint("[$timestamp] INSTRUMENTATION-CHAIN: EXIT MacCallPresenter.updateCall (MethodChannel error: $e)");
    });
  }

  @override
  void dismissCall() {
    _channel.invokeMethod('dismissCall').catchError((e) {
      // Ignore
    });
  }
}
