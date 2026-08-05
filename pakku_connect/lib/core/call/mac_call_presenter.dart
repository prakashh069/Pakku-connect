import 'package:flutter/services.dart';
import 'package:pakku_connect/core/models/call.dart';
import 'call_presenter.dart';

class MacCallPresenter implements CallPresenter {
  final MethodChannel _channel = const MethodChannel('com.pakku.connect/callPanel');

  @override
  void showCall(Call call) {
    _channel.invokeMethod('showCall', {
      'name': call.contactName,
      'number': call.phoneNumber,
      'state': call.state.name,
    }).catchError((e) {
      // Ignore if macOS fails to present the panel.
      // Flutter maintains the call state internally.
    });
  }

  @override
  void updateCall(Call call, {int elapsedSeconds = 0}) {
    _channel.invokeMethod('updateCall', {
      'state': call.state.name,
      'elapsedSeconds': elapsedSeconds,
    }).catchError((e) {
      // Ignore
    });
  }

  @override
  void dismissCall() {
    _channel.invokeMethod('dismissCall').catchError((e) {
      // Ignore
    });
  }
}
