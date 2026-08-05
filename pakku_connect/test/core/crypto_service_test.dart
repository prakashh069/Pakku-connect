import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:pakku_connect/core/services/crypto_service.dart';

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: 'PAKKU_SECRET=test_secret_key_123456');
  });

  test('generate + verify round-trip', () {
    final token = CryptoService.generateJWT(
      deviceId: 'd1', deviceName: 'test', platform: 'android');
    final payload = CryptoService.verifyJWT(token);
    expect(payload, isNotNull);
    expect(payload!['device_id'], 'd1');
  });

  test('generate + verify round-trip with cert_fp', () {
    final token = CryptoService.generateJWT(
      deviceId: 'd1', deviceName: 'test', platform: 'android',
      certFp: 'aa'.padRight(64, '0'));
    final payload = CryptoService.verifyJWT(token);
    expect(payload, isNotNull);
    expect(payload!['cert_fp'], 'aa'.padRight(64, '0'));
  });

  test('expired token fails', () {
    final token = CryptoService.generateJWT(
      deviceId: 'd1', deviceName: 'test', platform: 'android',
      expiry: const Duration(seconds: -1));
    expect(CryptoService.verifyJWT(token), isNull);
  });

  test('tampered token fails', () {
    final token = CryptoService.generateJWT(
      deviceId: 'd1', deviceName: 'test', platform: 'android');
    final tampered = '${token.substring(0, token.length - 1)}a';
    expect(CryptoService.verifyJWT(tampered), isNull);
  });

  test('malformed token fails', () {
    expect(CryptoService.verifyJWT('not.a.jwt'), isNull);
    expect(CryptoService.verifyJWT('invalid base64.parts.here'), isNull);
  });

  test('missing secret throws', () {
    dotenv.testLoad(fileInput: 'PAKKU_SECRET=');
    expect(
      () => CryptoService.generateJWT(
          deviceId: 'd1', deviceName: 'test', platform: 'android'),
      throwsException,
    );
  });
}
