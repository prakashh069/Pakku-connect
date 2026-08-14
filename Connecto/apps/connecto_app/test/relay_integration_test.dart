import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '../lib/features/relay/services/relay_server.dart';
import '../lib/core/services/crypto_service.dart';

void main() {
  test('RelayServer integration test', () async {
    final server = RelayServer();
    
    await server.start(
      port: 8080,
      certPath: 'certs/device.crt',
      keyPath: 'certs/device.key',
    );
    
    final hmacSecret = CryptoService.generateHmacSecret();
    server.setSecret(hmacSecret);
    
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;
    
    // Test 1: Invalid JWT rejection
    final wsInvalid = await WebSocket.connect('wss://127.0.0.1:8080', customClient: client);
    wsInvalid.add(jsonEncode({
      'type': 'hello',
      'jwt': 'invalid.jwt.token',
      'deviceName': 'TestClient',
      'platform': 'macOS'
    }));
    
    try {
      await wsInvalid.drain();
    } catch (e) {}
    
    expect(wsInvalid.closeCode, 1008);
    print('Invalid WS closed with code: ${wsInvalid.closeCode}');
    
    // Test 2: Relay remains alive, valid JWT connects successfully
    final validJwt = CryptoService.generateJWT(
      hmacSecret: hmacSecret,
      deviceId: 'test_device_id',
      deviceName: 'MyMacBook',
      platform: 'macOS',
      expiry: Duration(days: 1),
    );
    
    final wsValid = await WebSocket.connect('wss://127.0.0.1:8080', customClient: client);
    wsValid.add(jsonEncode({
      'type': 'hello',
      'jwt': validJwt,
      'deviceName': 'TestClient2',
      'platform': 'macOS'
    }));
    
    bool authAckReceived = false;
    final subscription = wsValid.listen((msg) {
      if (msg is String) {
        final data = jsonDecode(msg);
        if (data['type'] == 'auth_ack') {
          authAckReceived = true;
          print('auth_ack received successfully for valid client!');
        }
      }
    });
    
    await Future.delayed(Duration(seconds: 1));
    await subscription.cancel();
    await wsValid.close();
    
    expect(authAckReceived, isTrue);
    
    await server.stop();
  });
}
