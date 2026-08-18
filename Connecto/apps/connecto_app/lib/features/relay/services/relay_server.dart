import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

import '../models/relay_client.dart';
import '../models/relay_config.dart';
import 'relay_router.dart';
import 'relay_security.dart';

class RelayServer {
  HttpServer? _server;
  final List<RelayClient> _clients = [];
  final RelaySecurity _security = RelaySecurity();
  final RelayRouter _router = RelayRouter();
  String _hmacSecret = '';

  int get unauthenticatedCount => _clients.where((c) => !c.authenticated).length;

  void Function(Object error)? onError;

  void setSecret(String secret) {
    if (_hmacSecret == secret) return;
    _hmacSecret = secret;
    // Disconnect currently authenticated clients so they re-auth
    final toDisconnect = _clients.where((c) => c.authenticated).toList();
    for (var client in toDisconnect) {
      _closeSocket(client.socket, 1008, 'Secret rotated');
    }
  }

  Future<void> start({
    required int port,
    required String certPath,
    required String keyPath,
  }) async {
    final certData = await rootBundle.load(certPath);
    final keyData = await rootBundle.load(keyPath);
    final context = SecurityContext()
      ..useCertificateChainBytes(certData.buffer.asUint8List())
      ..usePrivateKeyBytes(keyData.buffer.asUint8List());

    _server = await HttpServer.bindSecure(InternetAddress.anyIPv4, port, context);
    
    _server!.listen((HttpRequest request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        await _handleUpgrade(request);
      } else {
        request.response
          ..statusCode = HttpStatus.forbidden
          ..close();
      }
    }, onError: (e) {
      print('RelayServer: HttpServer error: $e');
      onError?.call(e);
    });
  }

  Future<void> stop() async {
    for (var client in _clients.toList()) {
      _closeSocket(client.socket, 1001, 'Server shutting down');
    }
    _clients.clear();
    _security.dispose();
    await _server?.close(force: true);
    _server = null;
  }

  void _closeSocket(WebSocket ws, int code, String reason) {
    try {
      ws.close(code, reason);
    } catch (_) {}
  }

  Future<void> _handleUpgrade(HttpRequest request) async {
    final ip = request.connectionInfo?.remoteAddress ?? InternetAddress('0.0.0.0');

    if (_security.isBlacklisted(ip)) {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..close();
      return;
    }

    if (unauthenticatedCount >= RelayConfig.maxUnauthenticated) {
      request.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..close();
      return;
    }

    WebSocket ws;
    try {
      ws = await WebSocketTransformer.upgrade(
        request,
        compression: CompressionOptions.compressionOff,
      );
    } catch (e) {
      return;
    }

    ws.pingInterval = RelayConfig.heartbeatInterval;

    print('RelayServer: New connection from $ip');
    final client = RelayClient(socket: ws, ip: ip);
    _clients.add(client);

    Timer? handshakeTimer = Timer(RelayConfig.handshakeTimeout, () {
      if (!client.authenticated) {
        _security.recordFailure(ip);
        _closeSocket(ws, 1008, 'Authentication timeout');
      }
    });

    void cleanup() {
      handshakeTimer?.cancel();
      _clients.remove(client);

      if (client.authenticated) {
        final disconnectMsg = jsonEncode({
          'type': 'device_state',
          'state': 'disconnected'
        });
        for (var c in _clients) {
          if (c.authenticated) {
            try {
              c.socket.add(disconnectMsg);
            } catch (_) {}
          }
        }
      }
    }

    ws.listen((data) {
      print('RelayServer: [TRACE] Received WebSocket data');
      try {
        if (data is! String) {
          print('RelayServer: [TRACE] Error: not a string');
          _security.recordFailure(ip);
          _closeSocket(ws, 1007, 'Invalid payload type');
          return;
        }

        print('RelayServer: [TRACE] Data is string, checking size');
        if (utf8.encode(data).length > RelayConfig.maxPayloadBytes) {
          print('RelayServer: [TRACE] Error: too large');
          _closeSocket(ws, 1009, 'Message too large');
          return;
        }

        print('RelayServer: [TRACE] Decoding JSON');
        Map<String, dynamic> jsonMsg;
        try {
          jsonMsg = jsonDecode(data);
        } catch (e) {
          print('RelayServer: [TRACE] Error: Invalid JSON');
          _security.recordFailure(ip);
          _closeSocket(ws, 1007, 'Invalid JSON');
          return;
        }

        final type = jsonMsg['type'];
        print('RelayServer: [TRACE] Message type: $type');
        if (type is! String || type.trim().isEmpty) {
          print('RelayServer: [TRACE] Error: Missing type');
          _security.recordFailure(ip);
          _closeSocket(ws, 1007, 'Missing message type');
          return;
        }

        if (!client.authenticated) {
          print('RelayServer: [TRACE] Client is unauthenticated, processing hello...');


          if (type != 'hello') {
            print('RelayServer: [TRACE] Error: auth required for type $type');
            _security.recordFailure(ip);
            _closeSocket(ws, 1008, 'Authentication required');
            return;
          }

          print('RelayServer: [TRACE] Checking if _hmacSecret is empty');
          if (_hmacSecret.isEmpty) {
            print('RelayServer: [TRACE] Error: _hmacSecret is empty!');
            _security.recordFailure(ip);
            _closeSocket(ws, 1008, 'Server not fully provisioned');
            return;
          }

          final jwt = jsonMsg['jwt'];
          print('RelayServer: [TRACE] JWT present? ${jwt != null}');
          if (jwt is! String) {
            print('RelayServer: [TRACE] Error: JWT is not a string');
            _security.recordFailure(ip);
            _closeSocket(ws, 1008, 'Missing JWT');
            return;
          }

          print('RelayServer: [TRACE] Validating JWT... (secret length: ${_hmacSecret.length})');
          final error = _security.validateJwt(jwt, _hmacSecret, ip);
          print('RelayServer: [TRACE] validateJwt result: $error');
          if (error != null) {
            print('RelayServer: [TRACE] Error from validateJwt: $error');
            _closeSocket(ws, 1008, error);
            return;
          }

          print('RelayServer: [TRACE] Authenticated! Setting client.authenticated = true');
          client.authenticated = true;
          handshakeTimer?.cancel();

          print('RelayServer: [TRACE] Sanitizing deviceName');
          String deviceName = jsonMsg['deviceName']?.toString() ?? 'Unknown Device';
          deviceName = deviceName.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
          if (deviceName.length > 64) {
            deviceName = deviceName.substring(0, 64);
          }
          jsonMsg['deviceName'] = deviceName;

          print('RelayServer: [TRACE] Normalizing platform');
          String platform = jsonMsg['platform']?.toString() ?? '';
          if (platform.toLowerCase() == 'macos') {
            jsonMsg['platform'] = 'macOS';
          } else {
            jsonMsg['platform'] = 'Android';
          }

          print('RelayServer: [TRACE] Generating rawPayload');
          final rawPayload = jsonEncode(jsonMsg);

          print('RelayServer: [TRACE] Determining clientName');
          // Determine client role for logging/routing
          if (RelayConfig.macOnlyTypes.contains(type) || type == 'hello') {
            if (['dial', 'reject_call', 'end_call', 'answer_call', 'contacts_request'].contains(type)) {
              client.clientName = 'macOS';
            } else {
              client.clientName = jsonMsg['platform'];
            }
          }

          print('RelayServer: [TRACE] Adding auth_ack to socket');
          ws.add(jsonEncode({'type': 'auth_ack'}));
          
          print('RelayServer: [TRACE] Forwarding hello via router');
          // Forward hello to other clients
          _router.routeMessage(rawPayload, jsonMsg, client, _clients);
          print('RelayServer: [TRACE] Hello processing complete');
          return;
        }

        print('RelayServer: [TRACE] Handling authenticated message of type $type');
        // Already authenticated
        
        if (client.clientName == null) {
          if (RelayConfig.macOnlyTypes.contains(type)) {
            client.clientName = 'macOS';
          } else if (RelayConfig.androidOnlyTypes.contains(type)) {
            client.clientName = 'Android';
          } else {
            client.clientName = 'Unknown';
          }
        }

        _router.routeMessage(data, jsonMsg, client, _clients);
      } catch (e) {
        _security.recordFailure(ip);
        _closeSocket(ws, 1011, 'Internal server error');
      }
      
    }, onDone: () {
      cleanup();
    }, onError: (e) {
      cleanup();
    }, cancelOnError: true);
  }
}
