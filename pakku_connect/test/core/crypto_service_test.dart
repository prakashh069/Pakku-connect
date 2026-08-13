import 'package:flutter_test/flutter_test.dart';
import 'package:connecto/core/services/crypto_service.dart';

void main() {
  const testSecret = 'test_secret_key_123456';

  test('generate + verify round-trip', () {
    final token = CryptoService.generateJWT(
      deviceId: 'd1', deviceName: 'test', platform: 'android', hmacSecret: testSecret);
    final payload = CryptoService.verifyJWT(token, testSecret);
    expect(payload, isNotNull);
    expect(payload!['device_id'], 'd1');
  });

  test('generate + verify round-trip with cert_fp', () {
    final token = CryptoService.generateJWT(
      deviceId: 'd1', deviceName: 'test', platform: 'android', hmacSecret: testSecret,
      certFp: 'aa'.padRight(64, '0'));
    final payload = CryptoService.verifyJWT(token, testSecret);
    expect(payload, isNotNull);
    expect(payload!['cert_fp'], 'aa'.padRight(64, '0'));
  });

  test('expired token fails', () {
    final token = CryptoService.generateJWT(
      deviceId: 'd1', deviceName: 'test', platform: 'android', hmacSecret: testSecret,
      expiry: const Duration(seconds: -1));
    expect(CryptoService.verifyJWT(token, testSecret), isNull);
  });

  test('tampered token fails', () {
    final token = CryptoService.generateJWT(
      deviceId: 'd1', deviceName: 'test', platform: 'android', hmacSecret: testSecret);
    final tampered = '${token.substring(0, token.length - 1)}a';
    expect(CryptoService.verifyJWT(tampered, testSecret), isNull);
  });

  test('malformed token fails', () {
    expect(CryptoService.verifyJWT('not.a.jwt', testSecret), isNull);
    expect(CryptoService.verifyJWT('invalid base64.parts.here', testSecret), isNull);
  });

  test('missing secret throws', () {
    expect(
      () => CryptoService.generateJWT(
          deviceId: 'd1', deviceName: 'test', platform: 'android', hmacSecret: ''),
      throwsArgumentError,
    );
  });
}
