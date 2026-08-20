import 'dart:async';
import '../models/contact.dart';

enum DeviceSessionState {
  connected,
  disconnected,
  connecting,
  reconnecting,
  paused,
}

abstract class DeviceTransport {
  DeviceSessionState get deviceState;
  bool get isConnected;
  Stream<Map<String, dynamic>> get messages;
  List<RemoteContact> get cachedContacts;

  void connect(String url, {String? hmacSecret, String? certFp});
  void reset();
  void send(Map<String, dynamic> message);
  void pause();
  void resume();
  void requestContacts();
  void setRingerMode(String mode);
  void sendDeviceAction(String action, {bool enabled = true});

  void Function(String callId, String phoneNumber, String? contactName)? onIncomingCall;
  void Function(String callId, String state)? onCallState;
  void Function(bool connected)? onConnectionChange;
  void Function(DeviceSessionState state)? onDeviceStateChanged;
  void Function(List<RemoteContact> contacts)? onContactsReceived;
  void Function(String action, bool success, String? error)? onActionResult;
  void Function(String action, String status, String? error, Map<String, dynamic> data)? onActionStatus;
  void Function(Map<String, dynamic> data)? onDeviceState;
  void Function()? onUnpair;
  void Function(Map<String, dynamic> data)? onPlatformMessage;
  void Function(Map<String, dynamic> batteryData)? onBatteryStatus;
}
