import 'dart:io';
import 'package:connecto/features/relay/services/relay_security.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

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
  final sigB64 = base64UrlEncode(hmac.convert(utf8.encode('\$headerB64.\$payloadB64')).bytes).replaceAll('=', '');

  return '\$headerB64.\$payloadB64.\${invalidSig ? "bad" : sigB64}';
}

void main() {
  final hmacSecret = 'test_secret_key_123';
  final jwt = generateTestJWT(hmacSecret, 'jti_test', DateTime.now());
  
  final security = RelaySecurity();
  final error = security.validateJwt(jwt, hmacSecret, InternetAddress('127.0.0.1'));
  
  print('Error: \$error');
}
