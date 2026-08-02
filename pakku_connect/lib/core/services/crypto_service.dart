import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class CryptoService {
  static String get _secret {
    final s = dotenv.env['PAKKU_SECRET'];
    if (s == null || s.isEmpty) {
      throw Exception('PAKKU_SECRET not set in .env');
    }
    return s;
  }

  /// Computes the SHA-256 fingerprint of the DER-encoded certificate at
  /// [derPath], as a lowercase hex string. This MUST be computed from the
  /// DER file (certs/device.der), not the PEM file — Android's
  /// X509Certificate.getEncoded() returns DER, and a mismatch here means
  /// certificate pinning will always fail in production mode.
  static Future<String> certFingerprint(String derPath) async {
    final bytes = await File(derPath).readAsBytes();
    final digest = sha256.convert(bytes);
    return digest.toString(); // crypto's Digest.toString() is lowercase hex
  }

  static String generateJWT({
    required String deviceId,
    required String deviceName,
    required String platform,
    String? wsIp,
    int? wsPort,
    String? certFp,
    Duration expiry = const Duration(minutes: 5),
  }) {
    final header = {'alg': 'HS256', 'typ': 'JWT'};
    final now = DateTime.now();
    final payload = <String, dynamic>{
      'iss': 'pakku_connect',
      'sub': deviceId,
      'aud': 'pakku_connect_client',
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      'exp': now.add(expiry).millisecondsSinceEpoch ~/ 1000,
      'nbf': now.millisecondsSinceEpoch ~/ 1000,
      'device_id': deviceId,
      'device_name': deviceName,
      'platform': platform,
      'nonce': _generateNonce(),
    };
    if (wsIp != null) payload['ws_ip'] = wsIp;
    if (wsPort != null) payload['ws_port'] = wsPort;
    if (certFp != null) payload['cert_fp'] = certFp;

    final h = _b64(json.encode(header));
    final p = _b64(json.encode(payload));
    final sig = _sign('$h.$p');
    return '$h.$p.$sig';
  }

  static Map<String, dynamic>? verifyJWT(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) {
        debugPrint('CryptoService: Invalid JWT structure (expected 3 parts)');
        return null;
      }
      
      if (_sign('${parts[0]}.${parts[1]}') != parts[2]) {
        debugPrint('CryptoService: JWT signature mismatch');
        return null;
      }
      
      final payload = json.decode(_unb64(parts[1])) as Map<String, dynamic>;
      
      // Verify required standard claims
      if (payload['iss'] != 'pakku_connect') {
        debugPrint('CryptoService: Invalid issuer: ${payload['iss']}');
        return null;
      }
      if (payload['aud'] != 'pakku_connect_client') {
        debugPrint('CryptoService: Invalid audience: ${payload['aud']}');
        return null;
      }
      
      final exp = payload['exp'] as int?;
      final nbf = payload['nbf'] as int?;
      final nowSecs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      
      if (exp == null || nowSecs > exp) {
        debugPrint('CryptoService: Token expired (or exp missing)');
        return null;
      }
      
      if (nbf == null || nowSecs < nbf) {
        debugPrint('CryptoService: Token not yet valid (or nbf missing)');
        return null;
      }
      
      // Verify presence of required custom claims
      final requiredKeys = ['sub', 'iat', 'device_id', 'device_name', 'platform', 'nonce'];
      for (final key in requiredKeys) {
        if (!payload.containsKey(key)) {
          debugPrint('CryptoService: Missing required claim: $key');
          return null;
        }
      }

      return payload;
    } catch (e, st) {
      debugPrint('CryptoService: JWT verification failed: $e\n$st');
      return null;
    }
  }

  static String _generateNonce() {
    final bytes = List<int>.generate(12, (_) => Random.secure().nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _sign(String data) {
    final digest = Hmac(sha256, utf8.encode(_secret)).convert(utf8.encode(data));
    return _b64Bytes(digest.bytes);
  }

  static String _b64(String s) => _b64Bytes(utf8.encode(s));
  static String _b64Bytes(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static String _unb64(String s) {
    var out = s;
    while (out.length % 4 != 0) {
      out += '=';
    }
    return utf8.decode(base64Url.decode(out));
  }
}
