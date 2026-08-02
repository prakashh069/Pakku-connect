import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../constants/message_types.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  int _attempt = 0;
  String? _url;
  bool _isIntentionalDisconnect = false;

  void Function(String phoneNumber, String? contactName)? onIncomingCall;
  void Function(String state)? onCallState; // "answered" | "ended"
  void Function(bool connected)? onConnectionChange;

  void connect(String url) {
    _url = url;
    _attempt = 0;
    _isIntentionalDisconnect = false;
    _connectInternal();
  }

  void _connectInternal() {
    if (_url == null) return;
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

      _channel = IOWebSocketChannel.connect(
        Uri.parse(_url!),
        customClient: client,
        pingInterval: const Duration(seconds: 15),
      );

      _channel!.stream.listen(
        _onMessage,
        onError: (e, st) {
          debugPrint('WebSocketService: Connection error: $e\n$st');
          onConnectionChange?.call(false);
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('WebSocketService: Connection closed');
          onConnectionChange?.call(false);
          _scheduleReconnect();
        },
      );
      _attempt = 0;
      onConnectionChange?.call(true);
    } catch (e, st) {
      debugPrint('WebSocketService: Failed to connect: $e\n$st');
      onConnectionChange?.call(false);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_isIntentionalDisconnect) return;
    
    _reconnectTimer?.cancel();
    final delay = Duration(seconds: (_attempt < 5) ? (1 << _attempt) : 30);
    _attempt++;
    _reconnectTimer = Timer(delay, _connectInternal);
  }

  void _onMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = data['type'] as String?;
      if (type == MessageTypes.incomingCall) {
        onIncomingCall?.call(
          data['phoneNumber'] as String? ?? 'Unknown',
          data['contactName'] as String?,
        );
      } else if (type == MessageTypes.callState) {
        onCallState?.call(data['state'] as String? ?? 'ended');
      }
    } catch (e, st) {
      debugPrint('WebSocketService: Failed to parse message: $e\n$st');
    }
  }

  void send(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  void disconnect() {
    _isIntentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
  }
}
