import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:crypto/crypto.dart';
import 'crypto_service.dart';
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
  String? _hmacSecret;
  String? _certFp;
  
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
  void Function(String action, String status, String? error, Map<String, dynamic> data)? onActionStatus;
  void Function(Map<String, dynamic> data)? onDeviceState;
  void Function()? onUnpair;
  void Function(Map<String, dynamic> data)? onPlatformMessage;
  void Function(Map<String, dynamic> batteryData)? onBatteryStatus;

  WebSocketService({
    this.onIncomingCall,
    this.onCallState,
    this.onDeviceStateChanged,
    this.onConnectionChange,
    this.onContactsReceived,
    this.onActionResult,
    this.onUnpair,
  });

  void connect(String url, {String? hmacSecret, String? certFp}) {
    _url = url;
    if (hmacSecret != null) {
      _hmacSecret = hmacSecret;
    }
    if (certFp != null) {
      _certFp = certFp;
    }
    _attempt = 0;
    _isIntentionalDisconnect = false;
    _paused = false;
    onDeviceStateChanged?.call(DeviceSessionState.connecting);
    _connectInternal();
  }

  void _connectInternal() {
    if (_url == null || _paused) return;
    // If we have no secret we can never authenticate — stop reconnecting.
    if (_hmacSecret == null) {
      debugPrint('WebSocketService: No hmacSecret — skipping connect.');
      return;
    }
    _channel?.sink.close();

    try {
      final client = HttpClient();
      
      // Enforce cert pinning if we have the fingerprint.
      client.badCertificateCallback = (X509Certificate cert, String host, int port) {
        if (_certFp != null && _certFp!.isNotEmpty) {
          final presentedFp = sha256.convert(cert.der).toString().toLowerCase();
          if (presentedFp == _certFp!.toLowerCase()) {
            return true; // Pin matches
          }
          return false; // Pin provided but mismatch -> reject
        }
        if (kDebugMode) return true; // Only allow bypass in dev if no pin
        return false; // In production, fail closed
      };

      debugPrint('WebSocketService: WebSocket CONNECT');
      final currentChannel = IOWebSocketChannel.connect(
        Uri.parse(_url!),
        customClient: client,
        pingInterval: const Duration(seconds: 30),
      );
      _channel = currentChannel;

      debugPrint('WebSocketService: WebSocket OPEN');
      
      // If macOS, try to provision the relay with the HMAC secret
      if (Platform.isMacOS && _hmacSecret != null) {
        try {
          final tokenFile = File('/tmp/pakku.token');
          if (tokenFile.existsSync()) {
            final ipcToken = tokenFile.readAsStringSync();
            debugPrint('WebSocketService: SEND set_secret');
            currentChannel.sink.add(jsonEncode({
              'type': 'set_secret',
              'token': ipcToken,
              'secret': _hmacSecret,
            }));
          }
        } catch (e) {
          debugPrint('WebSocketService: Failed to process /tmp/pakku.token: $e');
        }
      }

      debugPrint('WebSocketService: SEND hello');
      
      final jwt = _hmacSecret != null 
          ? CryptoService.generateJWT(
              hmacSecret: _hmacSecret!,
              deviceId: Platform.isMacOS ? 'Mac' : 'Android',
              deviceName: Platform.isMacOS ? 'Mac' : 'Unknown',
              platform: Platform.operatingSystem,
            )
          : 'unprovisioned';

      currentChannel.sink.add(jsonEncode({
        'type': 'hello',
        'deviceName': Platform.isMacOS ? 'Mac' : 'Unknown',
        'platform': Platform.operatingSystem,
        'jwt': jwt,
      }));
      // Authentication is now strictly handled by 'auth_ack' from the relay
      debugPrint('WebSocketService: Waiting for auth_ack');

      currentChannel.stream.listen(
        (msg) {
          if (_channel == currentChannel) {
            _onMessage(msg);
          }
        },
        onError: (e, st) {
          if (_channel != currentChannel) return;
          debugPrint('WebSocketService: Connection error: $e\n$st');
          _authenticated = false;
          onConnectionChange?.call(false);
          _scheduleReconnect();
        },
        onDone: () {
          if (_channel != currentChannel) return;
          debugPrint('WebSocketService: Connection closed');
          _authenticated = false;
          onConnectionChange?.call(false);
          _scheduleReconnect();
        },
      );
      // Do NOT call onConnectionChange(true) here — wait for auth_ack
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
      debugPrint('WebSocketService: Received payload: $payload');
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final type = data['type'] as String?;
      if (type == 'auth_ack') {
        _authenticated = true;
        onConnectionChange?.call(true);
      } else if (type == 'hello') {
        onDeviceStateChanged?.call(DeviceSessionState.connected);
      } else if (type == MessageTypes.incomingCall) {
        onIncomingCall?.call(
          data['callId'] as String? ?? '',
          data['phoneNumber'] as String? ?? 'Unknown',
          data['contactName'] as String?,
        );
      } else if (type == MessageTypes.callState) {
        onCallState?.call(data['callId'] as String? ?? '', data['state'] as String? ?? 'ended');
      } else if (type == MessageTypes.deviceState) {
        final state = data['state'];
        
        if (state is String) {
          switch (state) {
            case 'connected':
              onDeviceStateChanged?.call(DeviceSessionState.connected);
              break;
            case 'disconnected':
              onDeviceStateChanged?.call(DeviceSessionState.disconnected);
              break;
          }
        }
        
        onDeviceState?.call(data);
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
        final status = data['status'] as String?;
        final success = data['success'] as bool? ?? (status == 'success');
        final error = data['error'] as String?;
        if (action != null) {
          onActionResult?.call(action, success, error);
          onActionStatus?.call(action, status ?? (success ? 'success' : 'error'), error, data);
        }
      } else if (type == 'device_state') {
        onDeviceState?.call(data);
      } else if (type == 'battery_status') {
        onBatteryStatus?.call(data);
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

  void setRingerMode(String mode) {
    if (!_authenticated) return;
    _channel?.sink.add(jsonEncode({
      'type': 'set_ringer_mode',
      'mode': mode,
    }));
  }

  void sendDeviceAction(String action, {bool? enabled}) {
    if (!_authenticated) return;
    final Map<String, dynamic> payload = {
      'type': 'device_action',
      'action': action,
    };
    if (enabled != null) {
      payload['enabled'] = enabled;
    }
    _channel?.sink.add(jsonEncode(payload));
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

  /// Full reset: clears stored credentials and stops all reconnection attempts.
  /// Call this on logout so the service can't reconnect with stale secrets.
  void reset() {
    disconnect();
    _hmacSecret = null;
    _url = null;
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
