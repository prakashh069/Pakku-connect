import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';

abstract class PlatformTransport {
  void send(Map<String, dynamic> message);
  Stream<Map<String, dynamic>> get messages;
  void dispose();
}

class MethodChannelTransport implements PlatformTransport {
  static const MethodChannel _channel = MethodChannel('com.pakku.connect/platform');
  
  final StreamController<Map<String, dynamic>> _messageController = StreamController.broadcast();

  /// Called when the Android side broadcasts an UNPAIRED event.
  /// Set this from main.dart instead of registering a second setMethodCallHandler.
  void Function()? onUnpaired;

  MethodChannelTransport() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onMessage') {
      try {
        final payloadStr = call.arguments as String;
        final decoded = jsonDecode(payloadStr) as Map<String, dynamic>;
        _messageController.add(decoded);
      } catch (e) {
        // Silently discard malformed JSON/type mismatch as per specification
      }
    } else if (call.method == 'onUnpaired') {
      onUnpaired?.call();
    }
  }

  @override
  void send(Map<String, dynamic> message) {
    try {
      final payloadStr = jsonEncode(message);
      _channel.invokeMethod('sendPlatformMessage', payloadStr);
    } catch (e) {
      // Best-effort: ignore serialization/channel failures
    }
  }

  @override
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    _messageController.close();
  }
}
