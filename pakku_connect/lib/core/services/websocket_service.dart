import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../constants/message_types.dart';
import '../models/contact.dart';
import 'platform_transport.dart';

enum DeviceSessionState {
  connected,
  disconnected,
  connecting,
  reconnecting,
  paused,
}

class WebSocketService implements PlatformTransport {
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  int _attempt = 0;
  String? _url;
  bool _isIntentionalDisconnect = false;
  bool _paused = false;
  bool _authenticated = false;
  
  bool get isConnected => _authenticated;

  final StreamController<Map<String, dynamic>> _messageController = StreamController.broadcast();

  @override
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  void Function(String callId, String phoneNumber, String? contactName)? onIncomingCall;
  void Function(String callId, String state)? onCallState; // "answered" | "ended"
  void Function(bool connected)? onConnectionChange;
  void Function(DeviceSessionState state)? onDeviceStateChanged;
  void Function(List<RemoteContact> contacts)? onContactsReceived;
  List<RemoteContact> cachedContacts = [];
  void Function(String action, bool success, String? error)? onActionResult;
  void Function()? onUnpair;
  void Function(Map<String, dynamic> data)? onPlatformMessage;

  WebSocketService({
    this.onIncomingCall,
    this.onCallState,
    this.onDeviceStateChanged,
    this.onConnectionChange,
    this.onContactsReceived,
    this.onActionResult,
    this.onUnpair,
  });

  void connect(String url) {
    _url = url;
    _attempt = 0;
    _isIntentionalDisconnect = false;
    _paused = false;
    onDeviceStateChanged?.call(DeviceSessionState.connecting);
    _connectInternal();
  }

  void _connectInternal() {
    if (_url == null || _paused) return;
    _channel?.sink.close();

    try {
      final client = HttpClient();
      
      // DEV ONLY. This accepts any certificate, including a spoofed one.
      // Production trust on macOS is established once via Keychain
      // Access (see docs/04_IMPLEMENTATION_GUIDE.md §13).
      // The kDebugMode gate ensures this bypass is stripped from release builds,
      // forcing the app to rely on Keychain trust in production.
      if (kDebugMode) {
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
      }

      debugPrint('WebSocketService: WebSocket CONNECT');
      _channel = IOWebSocketChannel.connect(
        Uri.parse(_url!),
        customClient: client,
        pingInterval: const Duration(seconds: 30),
      );

      debugPrint('WebSocketService: WebSocket OPEN');
      debugPrint('WebSocketService: SEND hello');
      _channel!.sink.add(jsonEncode({
        'type': 'hello',
        'deviceName': Platform.isMacOS ? 'Mac' : 'Unknown',
        'platform': Platform.operatingSystem,
      }));
      _authenticated = true;
      debugPrint('WebSocketService: Connection ready');

      _channel!.stream.listen(
        _onMessage,
        onError: (e, st) {
          debugPrint('WebSocketService: Connection error: $e\n$st');
          _authenticated = false;
          onConnectionChange?.call(false);
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('WebSocketService: Connection closed');
          _authenticated = false;
          onConnectionChange?.call(false);
          _scheduleReconnect();
        },
      );
      _attempt = 0;
      onConnectionChange?.call(true);
    } catch (e, st) {
      debugPrint('WebSocketService: Failed to connect: $e\n$st');
      _authenticated = false;
      onConnectionChange?.call(false);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_isIntentionalDisconnect || _paused) return;
    
    _reconnectTimer?.cancel();
    final delay = Duration(seconds: (_attempt < 5) ? (1 << _attempt) : 30);
    _attempt++;
    onDeviceStateChanged?.call(DeviceSessionState.reconnecting);
    _reconnectTimer = Timer(delay, _connectInternal);
  }

  void _onMessage(dynamic raw) {
    try {
      String payload;
      if (raw is String) {
        payload = raw;
      } else if (raw is List<int>) {
        payload = utf8.decode(raw);
      } else {
        return;
      }
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final type = data['type'] as String?;
      if (type == MessageTypes.incomingCall) {
        onIncomingCall?.call(
          data['callId'] as String? ?? '',
          data['phoneNumber'] as String? ?? 'Unknown',
          data['contactName'] as String?,
        );
      } else if (type == MessageTypes.callState) {
        onCallState?.call(data['callId'] as String? ?? '', data['state'] as String? ?? 'ended');
      } else if (type == MessageTypes.deviceState) {
        final state = data['state'];
        
        if (state is! String) {
          return;
        }

        switch (state) {
          case 'connected':
            onDeviceStateChanged?.call(DeviceSessionState.connected);
            break;
          case 'disconnected':
            onDeviceStateChanged?.call(DeviceSessionState.disconnected);
            break;
          default:
            break;
        }
      } else if (type == MessageTypes.contacts) {
        final contactsData = data['contacts'] as List?;
        if (contactsData != null) {
          final contacts = contactsData
              .map((e) => RemoteContact.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          cachedContacts = contacts;
          onContactsReceived?.call(contacts);
        }
      } else if (type == MessageTypes.actionResult) {
        final action = data['action'] as String?;
        final success = data['success'] as bool? ?? false;
        final error = data['error'] as String?;
        if (action != null) {
          onActionResult?.call(action, success, error);
        }
      } else if (type == MessageTypes.unpair) {
        onUnpair?.call();
      } else {
        // Generic dispatch for feature-specific message types (e.g. share.clipboard).
        // WebSocketService does not inspect these types — subscribers filter on their own.
        onPlatformMessage?.call(data);
      }

      _messageController.add(data);
    } catch (e) {
      debugPrint('WebSocketService: Failed to parse incoming message.');
    }
  }

  @override
  Future<void> send(Map<String, dynamic> data) async {
    if (!_authenticated) {
      debugPrint('WebSocketService: Dropping outbound ${data['type']} message (unauthenticated).');
      return;
    }
    debugPrint('WebSocketService: SEND outbound message (${data['type']})');
    _channel?.sink.add(jsonEncode(data));
  }

  void requestContacts() {
    send({'type': MessageTypes.contactsRequest});
  }

  void disconnect() {
    _isIntentionalDisconnect = true;
    _authenticated = false;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    onDeviceStateChanged?.call(DeviceSessionState.disconnected);
  }

  void pause() {
    _paused = true;
    _isIntentionalDisconnect = true;
    _authenticated = false;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    onDeviceStateChanged?.call(DeviceSessionState.paused);
  }

  void resume() {
    if (!_paused || _url == null) return;
    _paused = false;
    connect(_url!);
  }

  @override
  void dispose() {
    _messageController.close();
    disconnect();
  }
}
