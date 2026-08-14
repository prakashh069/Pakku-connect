import 'dart:io';
import 'dart:convert';
import 'package:connecto/features/relay/services/relay_server.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

String generateTestJWT(String hmacSecret, String jti, DateTime now, {bool invalidSig = false}) {
  final header = {'alg': 'HS256', 'typ': 'JWT'};
  final payload = {
    'iss': 'connecto',
    'aud': 'connecto_client',
    'exp': now.add(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000,
    'nbf': now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/ 1000,
    'jti': jti,
    'device_id': 'AndroidSimulator',
    'device_name': 'Android Simulator',
    'platform': 'android'
  };

  final headerB64 = base64UrlEncode(utf8.encode(jsonEncode(header))).replaceAll('=', '');
  final payloadB64 = base64UrlEncode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');

  final hmac = Hmac(sha256, utf8.encode(hmacSecret));
  final sigB64 = base64UrlEncode(hmac.convert(utf8.encode('$headerB64.$payloadB64')).bytes).replaceAll('=', '');

  return '$headerB64.$payloadB64.${invalidSig ? "bad" : sigB64}';
}

void main() {
  group('RelayServer Integration', () {
    late RelayServer server;
    final int port = 8089;
    final String hmacSecret = 'test_secret_key_123';
    
    setUpAll(() async {
      server = RelayServer();
      // Ensure the test is run from Connecto/apps/connecto_app
      await server.start(port: port, certPath: 'certs/device.crt', keyPath: 'certs/device.key');
      server.setSecret(hmacSecret);
    });

    tearDownAll(() async {
      await server.stop();
    });

    Future<WebSocket> connectClient() async {
      // Allow self-signed certs for testing
      final httpClient = HttpClient();
      httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
      return await WebSocket.connect('wss://127.0.0.1:$port', customClient: httpClient);
    }

    test('should reject connection if unauthenticated within 5 seconds', () async {
      final ws = await connectClient();
      bool isClosed = false;
      ws.listen(
        (data) {},
        onDone: () => isClosed = true,
      );
      // Wait for handshake timeout (5s in RelayConfig)
      await Future.delayed(const Duration(seconds: 6));
      expect(isClosed, isTrue);
      expect(ws.closeCode, 1008);
      expect(ws.closeReason, 'Authentication timeout');
    });

    test('should close with 1008 if JWT signature is invalid', () async {
      final ws = await connectClient();
      bool isClosed = false;
      
      ws.listen(
        (data) {},
        onDone: () => isClosed = true,
      );

      final jwt = generateTestJWT(hmacSecret, 'jti_bad', DateTime.now(), invalidSig: true);
      ws.add(jsonEncode({'type': 'hello', 'jwt': jwt}));
      
      await Future.delayed(const Duration(milliseconds: 500));
      expect(isClosed, isTrue);
      expect(ws.closeCode, 1008);
    });

    test('should authenticate with valid JWT', () async {
      final ws = await connectClient();
      bool isClosed = false;
      
      ws.listen(
        (data) {},
        onDone: () {
          isClosed = true;
          print('Closed unexpectedly with code ${ws.closeCode} and reason: ${ws.closeReason}');
        },
      );

      final jwt = generateTestJWT(hmacSecret, 'jti_good', DateTime.now());
      ws.add(jsonEncode({'type': 'hello', 'jwt': jwt}));
      
      await Future.delayed(const Duration(milliseconds: 500));
      expect(isClosed, isFalse);
      ws.close();
    });

    test('should close with 1009 for oversized payload', () async {
      final ws = await connectClient();
      bool isClosed = false;
      
      ws.listen((data) {}, onDone: () => isClosed = true);

      final jwt = generateTestJWT(hmacSecret, 'jti_oversize', DateTime.now());
      ws.add(jsonEncode({'type': 'hello', 'jwt': jwt}));
      await Future.delayed(const Duration(milliseconds: 500));
      expect(isClosed, isFalse);

      // Send a payload > 5MB
      final largeString = 'a' * (5 * 1024 * 1024 + 10);
      ws.add(largeString);

      await Future.delayed(const Duration(milliseconds: 500));
      expect(isClosed, isTrue);
      expect(ws.closeCode, 1009);
    });

    test('should route messages between authenticated clients', () async {
      final wsAndroid = await connectClient();
      final wsMac = await connectClient();

      final jwt1 = generateTestJWT(hmacSecret, 'jti_route_1', DateTime.now());
      wsAndroid.add(jsonEncode({'type': 'hello', 'jwt': jwt1}));
      
      final jwt2 = generateTestJWT(hmacSecret, 'jti_route_2', DateTime.now());
      // Make it appear as a Mac for directionality checks
      final headerB64 = base64UrlEncode(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'}))).replaceAll('=', '');
      final payloadB64 = base64UrlEncode(utf8.encode(jsonEncode({'exp': DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000, 'nbf': DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/ 1000, 'jti': 'jti_route_2', 'device_id': 'Mac', 'device_name': 'Mac', 'platform': 'macos'}))).replaceAll('=', '');
      final hmac = Hmac(sha256, utf8.encode(hmacSecret));
      final sigB64 = base64UrlEncode(hmac.convert(utf8.encode('$headerB64.$payloadB64')).bytes).replaceAll('=', '');
      final jwtMac = '$headerB64.$payloadB64.$sigB64';
      
      wsMac.add(jsonEncode({'type': 'hello', 'jwt': jwtMac}));

      await Future.delayed(const Duration(milliseconds: 500));

      bool macReceived = false;
      wsMac.listen((data) {
        final decoded = jsonDecode(data);
        if (decoded['type'] == 'incoming_call') {
          macReceived = true;
        }
      });

      // Android sends incoming_call
      wsAndroid.add(jsonEncode({'type': 'incoming_call', 'number': '1234'}));

      await Future.delayed(const Duration(milliseconds: 500));
      expect(macReceived, isTrue);

      wsAndroid.close();
      wsMac.close();
    });
  });
}
