import 'dart:convert';
import 'package:crypto/crypto.dart';

void main() {
  final hmacSecret = 'test_secret_123';
  final data = 'test.data';
  
  final hmac = Hmac(sha256, utf8.encode(hmacSecret));
  final digest = hmac.convert(utf8.encode(data));
  final expectedSig = base64Encode(digest.bytes).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
  print('Dart: ' + expectedSig);
}
