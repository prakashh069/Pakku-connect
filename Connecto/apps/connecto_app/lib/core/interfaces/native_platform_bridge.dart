import 'dart:async';

abstract class NativePlatformBridge {
  void send(Map<String, dynamic> message);
  Stream<Map<String, dynamic>> get messages;
  void Function()? onUnpaired;
  void dispose();
}
