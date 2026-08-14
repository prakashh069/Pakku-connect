import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:connecto/features/relay/services/relay_security.dart';

void main() {
  group('RelaySecurity Rate Limiting', () {
    late RelaySecurity security;
    final testIp = InternetAddress('127.0.0.1');

    setUp(() {
      security = RelaySecurity(
        rateLimitWindow: const Duration(milliseconds: 1000),
        rateLimitMaxFailures: 3,
        blacklistDuration: const Duration(milliseconds: 5000),
      );
    });

    tearDown(() {
      security.dispose();
    });

    test('should blacklist after max failures', () {
      expect(security.isBlacklisted(testIp), false);
      security.recordFailure(testIp);
      security.recordFailure(testIp);
      expect(security.isBlacklisted(testIp), false);
      
      security.recordFailure(testIp); // 3rd failure
      expect(security.isBlacklisted(testIp), true);
    });

    test('should reset failures after window', () async {
      security.recordFailure(testIp);
      security.recordFailure(testIp);
      
      await Future.delayed(const Duration(milliseconds: 1100));
      
      security.recordFailure(testIp); // This should be 1st in new window
      expect(security.isBlacklisted(testIp), false);
    });
  });

  group('RelaySecurity JWT Validation', () {
    late RelaySecurity security;
    final testIp = InternetAddress('127.0.0.2');
    const secret = 'super_secret_key_1234567890123456';

    setUp(() {
      security = RelaySecurity();
    });

    tearDown(() {
      security.dispose();
    });

    String generateJwt(Map<String, dynamic> payload, String key) {
      final header = base64UrlEncode(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'}))).replaceAll('=', '');
      final p = base64UrlEncode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
      final hmac = Hmac(sha256, utf8.encode(key));
      final sig = base64UrlEncode(hmac.convert(utf8.encode('$header.$p')).bytes).replaceAll('=', '');
      return '$header.$p.$sig';
    }

    test('should reject invalid format', () {
      final error = security.validateJwt('invalid_string', secret, testIp);
      expect(error, 'Invalid JWT format');
    });

    test('should reject invalid signature', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final payload = {'exp': now + 3600, 'jti': '123'};
      final jwt = generateJwt(payload, 'wrong_secret');
      
      final error = security.validateJwt(jwt, secret, testIp);
      expect(error, 'Invalid signature');
    });

    test('should reject expired token', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final payload = {'exp': now - 3600, 'jti': '124'};
      final jwt = generateJwt(payload, secret);
      
      final error = security.validateJwt(jwt, secret, testIp);
      expect(error, 'Token expired');
    });

    test('should enforce JTI replay protection', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final payload = {'exp': now + 3600, 'jti': 'nonce_1'};
      final jwt = generateJwt(payload, secret);
      
      final error1 = security.validateJwt(jwt, secret, testIp);
      expect(error1, null); // Success

      final error2 = security.validateJwt(jwt, secret, testIp);
      expect(error2, 'Replay detected');
    });

    test('should accept valid token', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final payload = {'exp': now + 3600, 'jti': 'valid_nonce_2'};
      final jwt = generateJwt(payload, secret);
      
      final error = security.validateJwt(jwt, secret, testIp);
      expect(error, null);
    });
  });
}
