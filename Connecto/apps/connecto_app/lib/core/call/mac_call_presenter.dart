import 'package:flutter/services.dart';
import 'package:connecto/core/models/call.dart';
import 'call_presenter.dart';

class MacCallPresenter implements CallPresenter {
  final MethodChannel _channel = const MethodChannel('com.connecto.app/callPanel');

  @override
  void showCall(Call call) {
    _channel.invokeMethod('showCall', {
      'name': call.contactName,
      'number': call.phoneNumber,
      'state': call.state.name,
      'direction': call.direction.name,
    }).catchError((e) {
      // Channel errors are non-fatal; the panel simply won't appear.
    });
  }

  @override
  void updateCall(Call call, {int elapsedSeconds = 0}) {
    _channel.invokeMethod('updateCall', {
      'state': call.state.name,
      'elapsedSeconds': elapsedSeconds,
    }).catchError((e) {
      // Channel errors are non-fatal.
    });
  }

  @override
  void dismissCall() {
    _channel.invokeMethod('dismissCall').catchError((e) {
      // Ignore.
    });
  }
}
