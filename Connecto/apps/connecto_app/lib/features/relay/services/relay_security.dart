import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

class FailureEntry {
  int count;
  int windowStart;
  FailureEntry({required this.count, required this.windowStart});
}

class RelaySecurity {
  final Map<InternetAddress, FailureEntry> _failureTracker = {};
  final Map<InternetAddress, int> _blacklist = {}; // IP -> expiry epoch ms
  final Map<String, int> _seenNonces = {}; // JTI -> expiry epoch seconds
  late final Timer _nonceCleanupTimer;
  
  // Rate limiting config constants passed via DI or fixed
  final Duration rateLimitWindow;
  final int rateLimitMaxFailures;
  final Duration blacklistDuration;

  RelaySecurity({
    this.rateLimitWindow = const Duration(milliseconds: 60000),
    this.rateLimitMaxFailures = 5,
    this.blacklistDuration = const Duration(milliseconds: 60000),
  }) {
    _nonceCleanupTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _cleanupNonces();
    });
  }

  void dispose() {
    _nonceCleanupTimer.cancel();
  }

  void _cleanupNonces() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _seenNonces.removeWhere((jti, exp) => now > exp);
  }

  bool isBlacklisted(InternetAddress ip) {
    final expires = _blacklist[ip];
    if (expires == null) return false;
    if (DateTime.now().millisecondsSinceEpoch > expires) {
      _blacklist.remove(ip);
      return false;
    }
    return true;
  }

  void recordFailure(InternetAddress ip) {
    final now = DateTime.now().millisecondsSinceEpoch;
    var entry = _failureTracker[ip];
    if (entry == null) {
      entry = FailureEntry(count: 0, windowStart: now);
      _failureTracker[ip] = entry;
    }

    if (now - entry.windowStart > rateLimitWindow.inMilliseconds) {
      entry.count = 0;
      entry.windowStart = now;
    }

    entry.count++;

    if (entry.count >= rateLimitMaxFailures) {
      _blacklist[ip] = now + blacklistDuration.inMilliseconds;
    }
  }

  /// Constant-time string comparison to prevent timing attacks
  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  /// Parses and validates the JWT without third-party packages, matching Node `server.js` exactly.
  String? validateJwt(String jwt, String hmacSecret, InternetAddress ip) {
    jwt = jwt.trim();
    final parts = jwt.split('.');
    if (parts.length != 3) {
      recordFailure(ip);
      return 'Invalid JWT format';
    }

    final headerB64 = parts[0];
    final payloadB64 = parts[1];
    final signatureB64 = parts[2];

    // Compute expected signature
    final hmac = Hmac(sha256, utf8.encode(hmacSecret));
    final digest = hmac.convert(utf8.encode('$headerB64.$payloadB64'));
    
    // Convert to base64url without padding (which matches Node's 'base64url' digest)
    final expectedSig = base64Encode(digest.bytes).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');

    if (!_constantTimeEquals(signatureB64, expectedSig)) {
      recordFailure(ip);
      return 'Invalid signature';
    }

    // Decode Payload
    Map<String, dynamic> payload;
    try {
      // Add padding back if necessary for Dart's base64Url decoder
      String normalizedPayloadB64 = payloadB64;
      while (normalizedPayloadB64.length % 4 != 0) {
        normalizedPayloadB64 += '=';
      }
      final decodedPayload = utf8.decode(base64Url.decode(normalizedPayloadB64));
      payload = jsonDecode(decodedPayload);
    } catch (e) {
      recordFailure(ip);
      return 'Invalid JWT Payload';
    }

    final nowSecs = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (payload['exp'] == null || nowSecs > payload['exp']) {
      recordFailure(ip);
      return 'Token expired';
    }

    if (payload['nbf'] != null && nowSecs < payload['nbf']) {
      recordFailure(ip);
      return 'Token not yet valid';
    }

    final jti = payload['jti'];
    if (jti == null) {
      recordFailure(ip);
      return 'Missing JTI';
    }

    if (_seenNonces.containsKey(jti)) {
      recordFailure(ip);
      return 'Replay detected';
    }

    // Cache the JTI nonce
    _seenNonces[jti] = payload['exp'];

    return null; // Null means success
  }
}
