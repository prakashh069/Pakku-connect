# Pakku Connect — Implementation Guide (v7.0)

**Target:** Working Tier‑1 only (pairing + signaling + remote accept/decline
signal + outgoing dial + contacts + native missed‑call notification)
**Strictly forbidden:** Live call audio. Never implement or claim it.
**Companion documents:** [01_SRS.md](./01_SRS.md) · [02_TDD.md](./02_TDD.md) · [03_API_PROTOCOL.md](./03_API_PROTOCOL.md) · [05_TEST_PLAN.md](./05_TEST_PLAN.md) · [ADRs](./adr/)

This guide is the "how to build it" document. It assumes you've read
[01_SRS.md](./01_SRS.md) (what it does) and [02_TDD.md](./02_TDD.md) (why
it's shaped this way) — decisions are linked inline rather than
re-justified here.

---

## Agent Rules (Mandatory)

1. Follow every step in exact order.
2. Do not invent features beyond [01_SRS.md §2.1](./01_SRS.md#21-in-scope-tier-1).
3. Never claim or implement live audio, in any form, under any framing.
4. After each major section, run the verification shown.
5. Keep `.env`, `certs/*`, and keystores out of git.
6. Prefer the simplest correct implementation.
7. When native answer/reject is unsupported, show a clear user message —
   never fail silently.
8. **Never present the development trust-all TLS path as production code.**
   Every place it appears must be visibly labeled and gated (see §11.2).

---

## 1. Project Bootstrap

```bash
mkdir -p ~/projects/pakku-connect
cd ~/projects/pakku-connect
flutter create pakku_connect --platforms=android,macos --org com.pakku
cd pakku_connect
flutter config --enable-macos-desktop
```

```bash
mkdir -p lib/core/{constants,models,services}
mkdir -p lib/features/{auth,calling,contacts}/screens
mkdir -p lib/features/calling/{services,widgets}
mkdir -p lib/shared/widgets
mkdir -p android/app/src/main/kotlin/com/pakku/connect
mkdir -p certs scripts docs test/core
touch certs/.gitkeep
```

`.gitignore`:

```
.env
certs/*
!certs/.gitkeep
*.jks
android/key.properties
build/
.dart_tool/
.idea/
*.iml
.DS_Store
node_modules/
package-lock.json
```

**Verification:** `flutter doctor` shows no blocking issues for Android
and macOS targets; `git status` shows a clean tree with `.env` and
`certs/` untracked once files are added.

---

## 2. Secrets

`scripts/generate_secret.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SECRET=$(openssl rand -base64 32 | tr -d '\n')
P12_PASS=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 24)
cat > .env <<EOF
PAKKU_SECRET=$SECRET
P12_PASSWORD=$P12_PASS
PAKKU_WS_PORT=8080
EOF
echo "Secrets written to .env — never commit"
```

```bash
chmod +x scripts/generate_secret.sh
./scripts/generate_secret.sh
```

**Verification:** `.env` exists, is git-ignored, and contains three
non-empty values.

---

## 3. Certificates

The certificate is generated in both PEM (for the TLS server) and DER
form (for the fingerprint embedded in the pairing QR — see
[ADR-004](./adr/ADR-004-self-signed-tls.md)). The fingerprint **must** be
computed from the DER bytes, because Android's
`X509Certificate.getEncoded()` returns DER — computing it from the PEM
file would silently produce a fingerprint that never matches on the phone
side.

`scripts/generate_certs.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
source .env
mkdir -p certs

openssl req -x509 -newkey rsa:4096 \
  -keyout certs/device.key \
  -out certs/device.crt \
  -days 825 -nodes \
  -subj "/CN=PakkuConnect/O=Pakku/C=US"

openssl pkcs12 -export \
  -in certs/device.crt \
  -inkey certs/device.key \
  -out certs/device.p12 \
  -passout pass:"$P12_PASSWORD"

# DER form — this is what Android's X509Certificate.getEncoded() returns,
# so the pinned fingerprint (ADR-004) must be computed from THIS file,
# not the PEM above.
openssl x509 -in certs/device.crt -outform DER -out certs/device.der

FP=$(openssl dgst -sha256 certs/device.der | awk '{print $2}')
echo "Certificate SHA-256 fingerprint (DER): $FP"
echo "Certificates ready in certs/"
```

```bash
chmod +x scripts/generate_certs.sh
./scripts/generate_certs.sh
```

**Verification:** `certs/` contains `device.key`, `device.crt`,
`device.p12`, and `device.der`. Re-running the script rotates the
fingerprint — note that any already-paired phone must re-scan a new QR
after this (see [ADR-004](./adr/ADR-004-self-signed-tls.md)).

---

## 4. Dependencies

`pubspec.yaml`:

```yaml
name: pakku_connect
description: Call control and notification bridge between Android and macOS.
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.5.0 <4.0.0'
  flutter: '>=3.24.0'

dependencies:
  flutter:
    sdk: flutter
  provider: ^6.1.2
  web_socket_channel: ^3.0.1
  qr_flutter: ^4.1.0
  mobile_scanner: ^5.2.3
  flutter_contacts: ^1.1.9
  flutter_secure_storage: ^9.2.4
  flutter_dotenv: ^5.2.1
  permission_handler: ^11.3.1
  crypto: ^3.0.6
  shared_preferences: ^2.3.4
  network_info_plus: ^6.0.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  mockito: ^5.4.4
  build_runner: ^2.4.12
  integration_test:
    sdk: flutter

flutter:
  uses-material-design: true
  assets:
    - .env
```

```bash
flutter pub get
```

`flutter_local_notifications` is intentionally absent — all Tier-1
notifications are the native Android missed-call notification, posted
directly by `PhoneStateService` (§11.3), not through a Flutter plugin.

**Verification:** `flutter pub get` completes with no version conflicts.

---

## 5. Core Files

### 5.1 `lib/core/constants/message_types.dart`

Mirrors [03_API_PROTOCOL.md §1](./03_API_PROTOCOL.md#1-message-contract)
exactly — if you add a message type, add it there first.

```dart
class MessageTypes {
  static const String incomingCall = 'incoming_call';
  static const String answerCall = 'answer_call';
  static const String rejectCall = 'reject_call';
  static const String dial = 'dial';
  static const String callState = 'call_state'; // answered | ended
  static const String error = 'error';
}
```

### 5.2 `lib/core/constants/app_theme.dart`

```dart
import 'package:flutter/material.dart';

class AppPalette {
  static const quantumCharcoal = Color(0xFF161B22);
  static const vibrantTeal = Color(0xFF14B8A6);
  static const interfaceGray = Color(0xFF30363D);
  static const lightText = Color(0xFFCED5DE);
  static const successGreen = Color(0xFF22C55E);
  static const dangerRed = Color(0xFFFF3B30);
}

class CustomColors extends ThemeExtension<CustomColors> {
  final Color background;
  final Color surface;
  final Color accent;
  final Color onAccent;
  final Color danger;
  final Color success;
  final Color lightText;

  const CustomColors({
    required this.background,
    required this.surface,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.success,
    required this.lightText,
  });

  @override
  CustomColors copyWith({
    Color? background,
    Color? surface,
    Color? accent,
    Color? onAccent,
    Color? danger,
    Color? success,
    Color? lightText,
  }) {
    return CustomColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      danger: danger ?? this.danger,
      success: success ?? this.success,
      lightText: lightText ?? this.lightText,
    );
  }

  @override
  CustomColors lerp(ThemeExtension<CustomColors>? other, double t) {
    if (other is! CustomColors) return this;
    return CustomColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
      lightText: Color.lerp(lightText, other.lightText, t)!,
    );
  }

  static const light = CustomColors(
    background: AppPalette.quantumCharcoal,
    surface: AppPalette.interfaceGray,
    accent: AppPalette.vibrantTeal,
    onAccent: Colors.white,
    danger: AppPalette.dangerRed,
    success: AppPalette.successGreen,
    lightText: AppPalette.lightText,
  );
}

ThemeData buildAppTheme() {
  return ThemeData.dark().copyWith(
    scaffoldBackgroundColor: AppPalette.quantumCharcoal,
    primaryColor: AppPalette.vibrantTeal,
    extensions: const [CustomColors.light],
  );
}
```

### 5.3 `lib/core/models/call.dart`

```dart
enum CallDirection { incoming, outgoing }
enum CallState { ringing, answeredRemotely, declinedRemotely, ended }

class Call {
  final String phoneNumber;
  final String? contactName;
  final CallDirection direction;
  CallState state;
  final DateTime startedAt;

  Call({
    required this.phoneNumber,
    this.contactName,
    required this.direction,
    this.state = CallState.ringing,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();
}
```

### 5.4 `lib/core/services/crypto_service.dart`

Updated from prior revisions to add `certFingerprint()` (reads the DER
file and computes its SHA-256 hex digest, so the QR-embedded fingerprint
and Android's runtime-computed fingerprint are guaranteed to agree — see
§3 above and [ADR-004](./adr/ADR-004-self-signed-tls.md)) and to accept an
optional `certFp` claim in `generateJWT`.

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';
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
      if (parts.length != 3) return null;
      if (_sign('${parts[0]}.${parts[1]}') != parts[2]) return null;
      final payload = json.decode(_unb64(parts[1])) as Map<String, dynamic>;
      final exp = payload['exp'] as int?;
      if (exp != null && DateTime.now().millisecondsSinceEpoch > exp * 1000) {
        return null;
      }
      return payload;
    } catch (_) {
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
    while (out.length % 4 != 0) out += '=';
    return utf8.decode(base64Url.decode(out));
  }
}
```

### 5.5 `lib/core/services/websocket_service.dart`

Unchanged in behavior from prior revisions — development mode only, as
noted inline. Production certificate pinning on macOS is handled via
Keychain trust rather than in this client (see
[02_TDD.md §6](./02_TDD.md#6-deployment-modes-development-vs-production)),
because `HttpClient` does not expose the low-level pinning hook OkHttp
provides on Android.

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../constants/message_types.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  int _attempt = 0;
  String? _url;

  void Function(String phoneNumber, String? contactName)? onIncomingCall;
  void Function(String state)? onCallState; // "answered" | "ended"
  void Function(bool connected)? onConnectionChange;

  void connect(String url) {
    _url = url;
    _attempt = 0;
    _connectInternal();
  }

  void _connectInternal() {
    if (_url == null) return;
    _channel?.sink.close();

    try {
      final client = HttpClient();
      
      // DEV ONLY. This accepts any certificate, including a spoofed one.
      // Production trust on macOS is established once via Keychain
      // Access (see docs/04_IMPLEMENTATION_GUIDE.md §13).
      // The kDebugMode gate ensures this bypass is stripped from release builds,
      // forcing the app to rely on Keychain trust in production.
      if (kDebugMode) {
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
      }

      _channel = IOWebSocketChannel.connect(
        Uri.parse(_url!),
        customClient: client,
        pingInterval: const Duration(seconds: 15),
      );

      _channel!.stream.listen(
        _onMessage,
        onError: (_) {
          onConnectionChange?.call(false);
          _scheduleReconnect();
        },
        onDone: () {
          onConnectionChange?.call(false);
          _scheduleReconnect();
        },
      );
      _attempt = 0;
      onConnectionChange?.call(true);
    } catch (_) {
      onConnectionChange?.call(false);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delay = Duration(seconds: (_attempt < 5) ? (1 << _attempt) : 30);
    _attempt++;
    _reconnectTimer = Timer(delay, _connectInternal);
  }

  void _onMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = data['type'] as String?;
      if (type == MessageTypes.incomingCall) {
        onIncomingCall?.call(
          data['phoneNumber'] as String? ?? 'Unknown',
          data['contactName'] as String?,
        );
      } else if (type == MessageTypes.callState) {
        onCallState?.call(data['state'] as String? ?? 'ended');
      }
    } catch (_) {}
  }

  void send(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
  }
}
```

**Verification for §5:** `flutter analyze` reports no errors in
`lib/core/`.

---

## 6. Call Manager

`lib/features/calling/services/call_manager.dart`

This is the Flutter-side reflection of native state described in
[ADR-003](./adr/ADR-003-native-service-source-of-truth.md) — note that
`answerCall()`/`rejectCall()` update local state immediately for UI
responsiveness, but the popup's true dismissal is driven by
`handleCallState()`, which only fires on an incoming `call_state` message
from the phone.

```dart
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '../../../core/models/call.dart';
import '../../../core/constants/message_types.dart';
import '../../../core/services/websocket_service.dart';

class CallManager extends ChangeNotifier {
  Call? _currentCall;
  final WebSocketService wsService;
  final MethodChannel _platform =
      const MethodChannel('com.pakku.connect/platform');

  String? lastNativeError;

  CallManager(this.wsService);

  Call? get currentCall => _currentCall;

  void handleIncoming(String phoneNumber, String? contactName) {
    if (_currentCall?.state == CallState.ringing) return;
    lastNativeError = null;
    _currentCall = Call(
      phoneNumber: phoneNumber,
      contactName: contactName,
      direction: CallDirection.incoming,
    );
    notifyListeners();
  }

  void handleCallState(String state) {
    if (state == 'answered') {
      _currentCall?.state = CallState.answeredRemotely;
      notifyListeners();
      Future.delayed(const Duration(seconds: 1), _clear);
    } else {
      _clear();
    }
  }

  Future<void> answerCall() async {
    if (_currentCall == null) return;
    _currentCall!.state = CallState.answeredRemotely; // optimistic UI only
    lastNativeError = null;
    notifyListeners();
    wsService.send({'type': MessageTypes.answerCall});
    // Authoritative dismissal still comes from handleCallState() above.
    // This timeout is a fallback in case the phone never confirms (e.g.
    // OEM-restricted device — see docs/02_TDD.md known limitations).
    Future.delayed(const Duration(seconds: 4), () {
      if (_currentCall?.state == CallState.answeredRemotely) _clear();
    });
  }

  Future<void> rejectCall() async {
    if (_currentCall == null) return;
    _currentCall!.state = CallState.declinedRemotely;
    lastNativeError = null;
    notifyListeners();
    wsService.send({'type': MessageTypes.rejectCall});
    _clear();
  }

  Future<void> dial(String number) async {
    _currentCall = Call(
      phoneNumber: number,
      direction: CallDirection.outgoing,
      state: CallState.answeredRemotely,
    );
    notifyListeners();

    if (Platform.isAndroid || Platform.isIOS) {
      try {
        await _platform.invokeMethod('makeCall', {'phoneNumber': number});
      } catch (e) {
        lastNativeError = 'Unable to place call';
        notifyListeners();
      }
    } else {
      // Mac: no local ack path yet — see docs/03_API_PROTOCOL.md §5 open items.
      wsService.send({'type': MessageTypes.dial, 'number': number});
    }
  }

  void _clear() {
    _currentCall = null;
    notifyListeners();
  }
}
```

**Verification:** with `PhoneStateService` mocked out
(`test/core/crypto_service_test.dart` pattern extended, or manual), tapping
Accept transitions the popup immediately and the popup clears either on a
simulated `call_state=answered` message or after the 4-second fallback,
whichever comes first.

---

## 7. Call Popup

`lib/features/calling/widgets/call_popup.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/call_manager.dart';
import '../../../core/models/call.dart';
import '../../../core/constants/app_theme.dart';

class CallPopup extends StatelessWidget {
  const CallPopup({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CustomColors>()!;
    return Consumer<CallManager>(
      builder: (context, manager, _) {
        final call = manager.currentCall;
        if (call == null || call.state == CallState.ended) {
          return const SizedBox.shrink();
        }

        return Material(
          color: Colors.black54,
          child: Center(
            child: Container(
              width: 340,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.accent, width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    call.direction == CallDirection.incoming
                        ? Icons.phone_in_talk
                        : Icons.phone_outgoing,
                    color: colors.accent,
                    size: 42,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    call.contactName ?? call.phoneNumber,
                    style: TextStyle(
                      color: colors.lightText,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    call.phoneNumber,
                    style: TextStyle(color: colors.lightText.withOpacity(0.7)),
                  ),
                  if (manager.lastNativeError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      manager.lastNativeError!,
                      style: TextStyle(color: colors.danger, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (call.state == CallState.ringing)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.call_end),
                          label: const Text('Decline'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.danger,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: manager.rejectCall,
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.call),
                          label: const Text('Accept'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.success,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: manager.answerCall,
                        ),
                      ],
                    )
                  else
                    Text(
                      'Call answered on phone',
                      style: TextStyle(color: colors.lightText),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
```

**Verification:** manually trigger `handleIncoming` → popup renders with
Accept/Decline; trigger `handleCallState('ended')` → popup disappears.

---

## 8. Pairing Screens

### 8.1 Mac QR Screen

`lib/features/auth/screens/qr_pairing_screen.dart`

Updated to embed `cert_fp` (read from `certs/device.der` via
`CryptoService.certFingerprint`) in the pairing JWT — this is what makes
production-mode certificate pinning on the phone possible (§11.2, and
[ADR-004](./adr/ADR-004-self-signed-tls.md)).

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/services/crypto_service.dart';
import '../../../core/constants/app_theme.dart';

class QrPairingScreen extends StatefulWidget {
  const QrPairingScreen({super.key});

  @override
  State<QrPairingScreen> createState() => _QrPairingScreenState();
}

class _QrPairingScreenState extends State<QrPairingScreen> {
  String? _qrData;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generateQR();
  }

  Future<void> _generateQR() async {
    setState(() => _error = null);
    final info = NetworkInfo();
    String ip = '127.0.0.1';
    try {
      ip = await info.getWifiIP() ?? '127.0.0.1';
    } catch (_) {}

    final port = int.tryParse(dotenv.env['PAKKU_WS_PORT'] ?? '8080') ?? 8080;

    String? certFp;
    try {
      // See docs/04_IMPLEMENTATION_GUIDE.md §3 — must be the DER fingerprint.
      certFp = await CryptoService.certFingerprint('certs/device.der');
    } catch (_) {
      // Non-fatal: pairing still works in development mode, but the phone
      // will have nothing to pin to in production mode. Surface this so
      // it isn't a silent gap.
      setState(() => _error =
          'Warning: could not read certs/device.der — run scripts/generate_certs.sh. '
          'Pairing will still work, but production certificate pinning will not.');
    }

    final token = CryptoService.generateJWT(
      deviceId: 'macos_${Platform.localHostname}',
      deviceName: Platform.localHostname,
      platform: 'macOS',
      wsIp: ip,
      wsPort: port,
      certFp: certFp,
    );

    setState(() => _qrData = token);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CustomColors>()!;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Pakku Connect — Pair'),
        backgroundColor: colors.surface,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_qrData != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: _qrData!,
                  size: 260,
                  backgroundColor: Colors.white,
                ),
              )
            else
              const CircularProgressIndicator(),
            const SizedBox(height: 28),
            Text(
              'Scan this QR with the Android app',
              style: TextStyle(color: colors.lightText, fontSize: 16),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _error!,
                  style: TextStyle(color: colors.danger, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextButton(
              onPressed: _generateQR,
              child: const Text('Generate New Code'),
            ),
          ],
        ),
      ),
    );
  }
}
```

### 8.2 Phone Scan Screen

`lib/features/auth/screens/scan_screen.dart`

Updated to: (1) persist `cert_fp` alongside `ws_ip`/`ws_port`, and (2)
request the runtime permissions the native service needs — including
`READ_CALL_LOG`, which `permission_handler` does not expose as its own
group, so it is requested via a dedicated native method (§11.2) — before
starting `PhoneStateService`.

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/services/crypto_service.dart';
import '../../../core/constants/app_theme.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final controller = MobileScannerController();
  final _platform = const MethodChannel('com.pakku.connect/platform');
  bool _verifying = false;
  String? _error;

  Future<void> _requestPermissions() async {
    // Covers READ_PHONE_STATE / CALL_PHONE / ANSWER_PHONE_CALLS via the
    // "phone" group, plus contacts and notifications.
    await [
      Permission.phone,
      Permission.contacts,
      Permission.notification,
    ].request();
    // READ_CALL_LOG has no permission_handler group — requested natively.
    // This call is fire-and-forget by design (see docs/02_TDD.md §5.1):
    // if denied, caller ID on eligible SDK levels gracefully falls back
    // to "Unknown" rather than the app crashing or blocking pairing.
    try {
      await _platform.invokeMethod('requestCallLogPermission');
    } catch (_) {}
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || _verifying) return;

    setState(() {
      _verifying = true;
      _error = null;
    });

    final payload = CryptoService.verifyJWT(code);
    if (payload == null) {
      setState(() {
        _verifying = false;
        _error = 'Invalid or expired QR code';
      });
      return;
    }

    final ip = payload['ws_ip'] as String?;
    final port = payload['ws_port'] as int?;
    final certFp = payload['cert_fp'] as String?;
    if (ip == null || port == null) {
      setState(() {
        _verifying = false;
        _error = 'QR missing connection details';
      });
      return;
    }

    const storage = FlutterSecureStorage();
    await storage.write(key: 'ws_ip', value: ip);
    await storage.write(key: 'ws_port', value: port.toString());
    if (certFp != null) {
      await storage.write(key: 'cert_fp', value: certFp);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('paired', true);

    await _requestPermissions();

    await _platform.invokeMethod(
      'saveWsEndpoint',
      {'ip': ip, 'port': port, 'certFp': certFp},
    );
    await _platform.invokeMethod('startPhoneStateService');

    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CustomColors>()!;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('Scan QR Code')),
      body: Stack(
        children: [
          MobileScanner(controller: controller, onDetect: _onDetect),
          if (_verifying) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, style: TextStyle(color: colors.danger)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      setState(() => _error = null);
                      controller.start();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
```

**Verification for §8:** scanning a fresh QR on a real phone stores all
three values (`ws_ip`, `ws_port`, `cert_fp`) in secure storage, prompts
for phone/contacts/notification permissions, and transitions to
`/home`; scanning a QR older than 5 minutes shows "Invalid or expired QR
code" without attempting a connection.

---

## 9. Contacts Tab

`lib/features/contacts/screens/contacts_tab.dart`

Unchanged from prior revisions.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../calling/services/call_manager.dart';
import '../../../core/constants/app_theme.dart';

class ContactsTab extends StatefulWidget {
  const ContactsTab({super.key});

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  List<Contact> _all = [];
  List<Contact> _filtered = [];
  bool _loading = true;
  bool _denied = false;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final status = await Permission.contacts.request();
    if (!status.isGranted) {
      setState(() {
        _loading = false;
        _denied = true;
      });
      return;
    }
    setState(() {
      _loading = true;
      _denied = false;
    });
    _all = await FlutterContacts.getContacts(withProperties: true);
    _filtered = List.from(_all);
    setState(() => _loading = false);
  }

  void _filter(String q) {
    setState(() {
      _filtered = _all.where((c) {
        final name = c.displayName.toLowerCase();
        final phones = c.phones.map((p) => p.number).join(' ');
        return name.contains(q.toLowerCase()) || phones.contains(q);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CustomColors>()!;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: TextField(
          controller: _search,
          onChanged: _filter,
          style: TextStyle(color: colors.lightText),
          decoration: InputDecoration(
            hintText: 'Search contacts...',
            hintStyle: TextStyle(color: colors.lightText.withOpacity(0.5)),
            border: InputBorder.none,
          ),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: colors.accent))
          : _denied
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Contacts permission denied',
                          style: TextStyle(color: colors.danger)),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _load, child: const Text('Retry')),
                      TextButton(
                        onPressed: openAppSettings,
                        child: const Text('Open Settings'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _filtered.length,
                  itemBuilder: (context, i) {
                    final c = _filtered[i];
                    return ListTile(
                      leading: Icon(Icons.person, color: colors.accent),
                      title: Text(c.displayName,
                          style: TextStyle(color: colors.lightText)),
                      subtitle: c.phones.isNotEmpty
                          ? Text(c.phones.first.number,
                              style: TextStyle(
                                  color: colors.lightText.withOpacity(0.7)))
                          : null,
                      onTap: () {
                        if (c.phones.isNotEmpty) {
                          context.read<CallManager>().dial(c.phones.first.number);
                        }
                      },
                    );
                  },
                ),
    );
  }
}
```

**Verification:** permission denial shows the retry/settings state
rather than crashing; tapping a contact with a phone number triggers
`CallManager.dial`.

---

## 10. Main Entry Point

`lib/main.dart`

Unchanged from prior revisions — wires `WebSocketService` and
`CallManager` via `provider`, and routes macOS to the QR screen / Android
to the scan screen based on pairing state.

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/constants/app_theme.dart';
import 'core/services/websocket_service.dart';
import 'features/calling/services/call_manager.dart';
import 'features/calling/widgets/call_popup.dart';
import 'features/auth/screens/qr_pairing_screen.dart';
import 'features/auth/screens/scan_screen.dart';
import 'features/contacts/screens/contacts_tab.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const PakkuApp());
}

class PakkuApp extends StatelessWidget {
  const PakkuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => WebSocketService()),
        ChangeNotifierProxyProvider<WebSocketService, CallManager>(
          create: (ctx) => CallManager(ctx.read<WebSocketService>()),
          update: (_, ws, previous) => previous ?? CallManager(ws),
        ),
      ],
      child: MaterialApp(
        title: 'Pakku Connect',
        theme: buildAppTheme(),
        builder: (context, child) {
          return Stack(
            children: [
              child!,
              const CallPopup(),
            ],
          );
        },
        initialRoute: '/',
        routes: {
          '/': (_) => const RootRouter(),
          '/home': (_) => const HomeScreen(),
        },
      ),
    );
  }
}

class RootRouter extends StatefulWidget {
  const RootRouter({super.key});

  @override
  State<RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<RootRouter> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _setup());
  }

  Future<void> _setup() async {
    if (Platform.isMacOS) {
      final ws = context.read<WebSocketService>();
      final manager = context.read<CallManager>();

      ws.onIncomingCall = (number, name) {
        manager.handleIncoming(number, name);
      };
      ws.onCallState = (state) {
        manager.handleCallState(state);
      };

      final port = dotenv.env['PAKKU_WS_PORT'] ?? '8080';
      ws.connect('wss://127.0.0.1:$port');
    } else {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('paired') ?? false) {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS) {
      return const QrPairingScreen();
    }
    return const ScanScreen();
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: ContactsTab(),
    );
  }
}
```

**Verification for §9–10:** `flutter run -d macos` shows the QR screen
and connects to a locally running relay; `flutter run` on an Android
device shows the scan screen, or jumps straight to `/home` if already
paired.

---

## 11. Native Android

This section carries the three fixes from the latest technical review, in
addition to the missed-call notification behavior:

1. **API 31+ support** — `TelephonyCallback` alongside the legacy
   `PhoneStateListener`, since the latter's callback signature changes
   meaning across SDK levels (see [02_TDD.md §5](./02_TDD.md#5-android-api-level-strategy)).
2. **Real TLS trust, not just "accept everything"** — an explicit
   development/production split in the OkHttp client, matching
   [ADR-004](./adr/ADR-004-self-signed-tls.md).
3. **Honest phone-number handling** — `READ_CALL_LOG` requested
   alongside `READ_PHONE_STATE`, with a documented, graceful "Unknown"
   fallback rather than a crash, consistent with
   [02_TDD.md §5.1](./02_TDD.md#51-known-limitation-caller-id-on-api-31).

### 11.1 Permissions + Service Declaration

`android/app/src/main/AndroidManifest.xml` (relevant excerpt):

```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.READ_PHONE_STATE"/>
<uses-permission android:name="android.permission.READ_CALL_LOG"/>
<uses-permission android:name="android.permission.CALL_PHONE"/>
<uses-permission android:name="android.permission.ANSWER_PHONE_CALLS"/>
<uses-permission android:name="android.permission.READ_CONTACTS"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_PHONE_CALL"/>
```

```xml
<service
    android:name=".PhoneStateService"
    android:foregroundServiceType="phoneCall"
    android:exported="false" />
```

`READ_CALL_LOG` is a dangerous permission with real privacy weight — it
grants access to the device's call history, not just the current ringing
number. It is requested for the narrow purpose of resolving the current
caller's number where the OS permits it (API ≤ 30 — see
[02_TDD.md §5](./02_TDD.md#5-android-api-level-strategy)); the app does
not read or transmit call history beyond that. If the user denies it,
caller display falls back to "Unknown" (§11.3) rather than blocking
pairing.

`minSdkVersion` is **26**, set in `android/app/build.gradle`.

### 11.2 `MainActivity.kt`

Adds `requestCallLogPermission` (native, since `permission_handler` has
no dedicated group for it — see §8.2) and extends `saveWsEndpoint` to
persist `certFp` for use by the production trust path in §11.3.

```kotlin
package com.pakku.connect

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.pakku.connect/platform"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "makeCall" -> {
                        val number = call.argument<String>("phoneNumber")
                        if (number == null) {
                            result.error("INVALID", "phoneNumber required", null)
                            return@setMethodCallHandler
                        }
                        if (ContextCompat.checkSelfPermission(
                                this, Manifest.permission.CALL_PHONE
                            ) == PackageManager.PERMISSION_GRANTED
                        ) {
                            startActivity(Intent(Intent.ACTION_CALL, Uri.parse("tel:$number")))
                            result.success(true)
                        } else {
                            ActivityCompat.requestPermissions(
                                this, arrayOf(Manifest.permission.CALL_PHONE), REQ_CALL_PHONE)
                            result.error("PERMISSION", "CALL_PHONE not granted", null)
                        }
                    }
                    "saveWsEndpoint" -> {
                        val ip = call.argument<String>("ip")
                        val port = call.argument<Int>("port") ?: 8080
                        val certFp = call.argument<String>("certFp")
                        getSharedPreferences("pakku_prefs", Context.MODE_PRIVATE)
                            .edit()
                            .putString("ws_ip", ip)
                            .putInt("ws_port", port)
                            .putString("cert_fp", certFp)
                            .apply()
                        result.success(true)
                    }
                    "requestCallLogPermission" -> {
                        // Fire-and-forget by design — see docs/04_IMPLEMENTATION_GUIDE.md
                        // §8.2 and docs/02_TDD.md §5.1. Denial degrades caller-ID display
                        // to "Unknown"; it never blocks pairing or crashes the service.
                        if (ContextCompat.checkSelfPermission(
                                this, Manifest.permission.READ_CALL_LOG
                            ) != PackageManager.PERMISSION_GRANTED
                        ) {
                            ActivityCompat.requestPermissions(
                                this, arrayOf(Manifest.permission.READ_CALL_LOG), REQ_CALL_LOG)
                        }
                        result.success(true)
                    }
                    "startPhoneStateService" -> {
                        val intent = Intent(this, PhoneStateService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    companion object {
        private const val REQ_CALL_PHONE = 101
        private const val REQ_CALL_LOG = 102
    }
}
```

**Verification:** `saveWsEndpoint` round-trips all three values —
inspect via `adb shell run-as com.pakku.connect cat
/data/data/com.pakku.connect/shared_prefs/pakku_prefs.xml` on a debug
build and confirm `ws_ip`, `ws_port`, and `cert_fp` are all present.

### 11.3 `PhoneStateService.kt`

The full rewrite. Read the inline comments — they carry real decisions,
not decoration. Three things changed structurally from earlier revisions:

- `startPhoneListener()` now branches on `Build.VERSION.SDK_INT` and
  funnels both paths into one shared `handleStateChange()`.
- `buildOkHttpClient()` replaces the single "accept everything" client
  with an explicit dev/prod branch (§6 of
  [02_TDD.md](./02_TDD.md#6-deployment-modes-development-vs-production)).
  **The production branch is the one that actually ships** — the dev
  branch exists only to make local development possible without
  installing a CA cert into the Android system trust store on every
  test device.
- Caller number resolution honestly reflects what the OS will and won't
  give the app per SDK level (§5.1).

```kotlin
package com.pakku.connect

import android.app.*
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.telecom.TelecomManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import okhttp3.*
import org.json.JSONObject
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

class PhoneStateService : Service() {
    private var webSocket: WebSocket? = null
    private var telephonyManager: TelephonyManager? = null

    // Legacy path (SDK < 31)
    private var legacyListener: PhoneStateListener? = null

    // Modern path (SDK 31+)
    private var telephonyCallback: TelephonyCallback? = null

    private var lastState = TelephonyManager.CALL_STATE_IDLE
    private var missedCallNotificationId = 100

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Pakku Connect")
            .setContentText("Listening for calls")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
        startForeground(1, notification)

        startWebSocket()
        startPhoneListener()
        return START_STICKY
    }

    // ---------------------------------------------------------------
    // TLS trust — dev vs prod. See docs/02_TDD.md §6 and ADR-004.
    // ---------------------------------------------------------------

    /**
     * DEVELOPMENT ONLY. Trusts any certificate presented by the server.
     * This exists purely so local development doesn't require installing
     * a CA cert into the Android system trust store on every test device
     * or emulator wipe. It must never be reachable in a release build —
     * enforced here via BuildConfig.DEBUG, which is false in release
     * builds by the Android Gradle Plugin's default signing config.
     */
    private fun buildDevTrustAllClient(): OkHttpClient {
        val trustAllCerts = arrayOf<TrustManager>(object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
            override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
        })
        val sslContext = SSLContext.getInstance("TLS").apply {
            init(null, trustAllCerts, SecureRandom())
        }
        return OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .pingInterval(15, TimeUnit.SECONDS)
            .sslSocketFactory(sslContext.socketFactory, trustAllCerts[0] as X509TrustManager)
            .hostnameVerifier { _, _ -> true }
            .build()
    }

    /**
     * PRODUCTION. Pins the server's certificate by exact SHA-256
     * fingerprint (of the DER encoding — matches how the fingerprint was
     * generated on the Mac side, see docs/04_IMPLEMENTATION_GUIDE.md §3),
     * captured at pairing time from the QR's JWT payload and stored in
     * SharedPreferences as "cert_fp" (see MainActivity.saveWsEndpoint).
     *
     * This is trust-on-first-use, not chain-of-trust — there is no CA
     * involved. A self-signed certificate is accepted if and only if its
     * fingerprint exactly matches what was captured at pairing. Anything
     * else — including a legitimate-looking but different certificate —
     * is rejected, which is the correct behavior for a possible MITM.
     */
    private fun buildProdPinnedClient(pinnedFingerprint: String): OkHttpClient {
        val pinningTrustManager = object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
                val cert = chain?.firstOrNull()
                    ?: throw CertificateException("No certificate presented")
                val digest = MessageDigest.getInstance("SHA-256").digest(cert.encoded)
                val hex = digest.joinToString("") { "%02x".format(it) }
                if (!hex.equals(pinnedFingerprint, ignoreCase = true)) {
                    throw CertificateException(
                        "Certificate fingerprint mismatch — refusing connection " +
                        "(expected=$pinnedFingerprint actual=$hex)")
                }
            }
            override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
        }
        val sslContext = SSLContext.getInstance("TLS").apply {
            init(null, arrayOf(pinningTrustManager), SecureRandom())
        }
        return OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .pingInterval(15, TimeUnit.SECONDS)
            .sslSocketFactory(sslContext.socketFactory, pinningTrustManager)
            // Hostname verification is meaningless here: we connect by raw
            // LAN IP, and identity is established by the fingerprint pin
            // above, not by a hostname/SAN match.
            .hostnameVerifier { _, _ -> true }
            .build()
    }

    private fun buildOkHttpClient(pinnedFingerprint: String?): OkHttpClient {
        return if (!pinnedFingerprint.isNullOrEmpty()) {
            buildProdPinnedClient(pinnedFingerprint)
        } else if (BuildConfig.DEBUG) {
            Log.w(TAG, "No cert_fp available — falling back to DEV trust-all client. " +
                "This must never happen in a release build.")
            buildDevTrustAllClient()
        } else {
            Log.e(TAG, "No cert_fp available and this is a release build — refusing to " +
                "connect insecurely. Re-pair via a fresh QR code.")
            throw IllegalStateException("Missing cert_fp in production build")
        }
    }

    // ---------------------------------------------------------------
    // WebSocket lifecycle
    // ---------------------------------------------------------------

    private fun startWebSocket() {
        val prefs = getSharedPreferences("pakku_prefs", Context.MODE_PRIVATE)
        val ip = prefs.getString("ws_ip", null) ?: return
        val port = prefs.getInt("ws_port", 8080)
        val certFp = prefs.getString("cert_fp", null)
        val url = "wss://$ip:$port"

        val client = try {
            buildOkHttpClient(certFp)
        } catch (e: IllegalStateException) {
            Log.e(TAG, "Cannot start WebSocket: ${e.message}")
            return
        }

        val request = Request.Builder().url(url).build()
        webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.d(TAG, "WSS connected")
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e(TAG, "WSS failure: ${t.message}")
                android.os.Handler(mainLooper).postDelayed({ startWebSocket() }, 5000)
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                try {
                    val json = JSONObject(text)
                    when (json.optString("type")) {
                        "answer_call" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                val tm = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                                tm.acceptRingingCall()
                                Log.d(TAG, "Native answer executed")
                            } else {
                                Log.w(TAG, "acceptRingingCall requires API 28+")
                            }
                            // NOTE: success is NOT assumed here. The Mac only
                            // treats the call as answered once it receives the
                            // subsequent call_state=answered message, driven by
                            // an actual OFFHOOK observation below — see ADR-003.
                        }
                        "reject_call" -> {
                            val tm = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                tm.endCall()
                            } else {
                                tm.silenceRinger()
                            }
                            Log.d(TAG, "Native reject executed")
                        }
                        "dial" -> {
                            val number = json.optString("number")
                            if (number.isNotEmpty()) {
                                val intent = Intent(Intent.ACTION_CALL, Uri.parse("tel:$number"))
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                Log.d(TAG, "Native dial executed")
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to handle control message: ${e.message}")
                }
            }
        })
    }

    // ---------------------------------------------------------------
    // Telephony state — API-level branching. See docs/02_TDD.md §5.
    // ---------------------------------------------------------------

    private fun startPhoneListener() {
        telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // API 31+: PhoneStateListener is deprecated in favor of
            // TelephonyCallback. IMPORTANT: this callback signature does
            // NOT include the caller's phone number at all (Google removed
            // it for privacy) — see docs/02_TDD.md §5.1. We pass null and
            // let handleStateChange's existing "Unknown" fallback do its job.
            val executor = ContextCompat.getMainExecutor(this)
            val callback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                override fun onCallStateChanged(state: Int) {
                    handleStateChange(state, null)
                }
            }
            telephonyCallback = callback
            telephonyManager?.registerTelephonyCallback(executor, callback)
        } else {
            // SDK < 31: legacy PhoneStateListener. The phoneNumber parameter
            // requires READ_PHONE_STATE, and on API 29-30 ALSO requires
            // READ_CALL_LOG (or READ_PHONE_NUMBERS) to be non-null — see
            // AndroidManifest.xml in §11.1. If READ_CALL_LOG was denied,
            // this parameter comes through as null/empty and we fall back
            // to "Unknown" the same way the API 31+ path does.
            @Suppress("DEPRECATION")
            val listener = object : PhoneStateListener() {
                @Suppress("DEPRECATION")
                override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                    handleStateChange(state, phoneNumber)
                }
            }
            legacyListener = listener
            @Suppress("DEPRECATION")
            telephonyManager?.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
        }
    }

    /** Shared by both the legacy and modern telephony callback paths. */
    private fun handleStateChange(state: Int, phoneNumber: String?) {
        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> {
                val number = phoneNumber ?: "Unknown"
                val msg = """{"type":"incoming_call","phoneNumber":"$number","contactName":""}"""
                webSocket?.send(msg)
                Log.d(TAG, "Sent incoming_call ($number)")
            }
            TelephonyManager.CALL_STATE_OFFHOOK -> {
                if (lastState == TelephonyManager.CALL_STATE_RINGING) {
                    webSocket?.send("""{"type":"call_state","state":"answered"}""")
                    Log.d(TAG, "Sent call_state=answered")
                }
            }
            TelephonyManager.CALL_STATE_IDLE -> {
                if (lastState == TelephonyManager.CALL_STATE_RINGING ||
                    lastState == TelephonyManager.CALL_STATE_OFFHOOK
                ) {
                    webSocket?.send("""{"type":"call_state","state":"ended"}""")
                    Log.d(TAG, "Sent call_state=ended")
                }
                // Missed call: went straight from RINGING to IDLE, never OFFHOOK.
                if (lastState == TelephonyManager.CALL_STATE_RINGING) {
                    showMissedCallNotification(phoneNumber ?: "Unknown")
                }
            }
        }
        lastState = state
    }

    private fun showMissedCallNotification(phoneNumber: String) {
        val manager = getSystemService(NotificationManager::class.java)
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Missed Call")
            .setContentText(phoneNumber)
            .setSmallIcon(android.R.drawable.stat_notify_missed_call)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()
        manager.notify(missedCallNotificationId++, notification)
    }

    override fun onDestroy() {
        webSocket?.close(1000, "destroyed")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            telephonyCallback?.let { telephonyManager?.unregisterTelephonyCallback(it) }
        } else {
            @Suppress("DEPRECATION")
            legacyListener?.let { telephonyManager?.listen(it, PhoneStateListener.LISTEN_NONE) }
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Call Service", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    companion object {
        private const val TAG = "PhoneStateService"
        private const val CHANNEL_ID = "pakku_call_service"
    }
}
```

Add to `android/app/build.gradle`:

```gradle
implementation 'com.squareup.okhttp3:okhttp:4.12.0'
```

Set `minSdkVersion 26`.

> **Known limitations (restated from [02_TDD.md](./02_TDD.md), not new
> information — kept here too since this is where an implementer will be
> looking when debugging them):**
> - `TelecomManager.acceptRingingCall()` and `endCall()` do not work on
>   every OEM. When they fail, the user must answer/decline on the phone.
>   The Mac popup still auto-dismisses correctly via `call_state`.
> - On API 31+, the caller's phone number is not delivered by
>   `TelephonyCallback` at all — the popup will show "Unknown" regardless
>   of permissions granted. This is a platform constraint, not a bug in
>   this service.
> - If `cert_fp` is missing in a release build, the service intentionally
>   refuses to connect rather than silently downgrading to trust-all —
>   the fix is always "re-pair via a fresh QR," never "loosen the trust
>   check."

**Verification for §11.3:**
- On an API 30 (or lower) device/emulator with `READ_CALL_LOG` granted, a
  real incoming call shows the actual number in `incoming_call`.
- On an API 31+ device, the same call shows `"Unknown"` — expected, not a
  regression.
- Building a **release** variant with no prior pairing (`cert_fp` absent)
  logs the refusal message and does not open a socket — confirm via
  `adb logcat -s PhoneStateService`.
- Deliberately editing `cert_fp` in `pakku_prefs.xml` to a wrong value and
  restarting the service produces a `CertificateException` in logcat and
  no successful connection — this is the pinning check working as
  intended.

---

## 12. Node.js Relay Server

`server.js` (project root). See [ADR-005](./adr/ADR-005-node-vs-dart-server.md)
for why this is a separate Node process rather than a Dart server.

```javascript
const fs = require('fs');
const https = require('https');
const WebSocket = require('ws');
require('dotenv').config();

const cert = fs.readFileSync('certs/device.crt');
const key = fs.readFileSync('certs/device.key');

const server = https.createServer({ cert, key });
const wss = new WebSocket.Server({ server });

wss.on('connection', (ws) => {
  console.log('Client connected');
  ws.on('message', (raw) => {
    try {
      const data = JSON.parse(raw.toString());
      wss.clients.forEach((client) => {
        if (client !== ws && client.readyState === WebSocket.OPEN) {
          client.send(JSON.stringify(data));
        }
      });
    } catch (e) {
      ws.send(JSON.stringify({ type: 'error', payload: 'Invalid JSON' }));
    }
  });
  ws.on('close', () => console.log('Client disconnected'));
});

const port = process.env.PAKKU_WS_PORT || 8080;
server.listen(port, () => {
  console.log(`WSS server listening on port ${port}`);
});
```

```bash
npm init -y
npm install ws dotenv
node server.js
```

The relay is intentionally not "hardened" beyond TLS — it forwards
whatever it receives, to whoever else is connected, per the message
contract in [03_API_PROTOCOL.md](./03_API_PROTOCOL.md). It does not
validate message shape, does not authenticate clients beyond the TLS
handshake, and does not limit connection count. This is an accepted
consequence of the LAN-trust threat model in
[02_TDD.md §7](./02_TDD.md#7-threat-model), not an oversight — do not
"fix" it by adding server-side auth without first updating that threat
model and [01_SRS.md](./01_SRS.md), since that would be a real scope
change (the relay would need its own identity and trust story).

**Verification:** `node server.js` logs "WSS server listening on port
8080"; connecting two `wscat -n` (or equivalent) clients confirms a
message sent by one arrives verbatim at the other.

---

## 13. Certificate Trust

### 13.1 Development

**macOS**
1. Open `certs/device.crt` in Keychain Access.
2. Drag into the **System** keychain.
3. Double-click → Trust → "When using this certificate" = **Always
   Trust**.

**Android**
1. Copy `certs/device.crt` to the device.
2. Settings → Security → Encryption & credentials → Install a
   certificate → CA certificate.
3. Select the file.

This manual CA-install step is only needed if you are exercising the
*development* trust-all path deliberately without a `cert_fp` — in normal
operation (§11.2/§11.3), the Android app never needs the certificate
installed into the system trust store at all, because it validates the
fingerprint itself rather than relying on the OS's CA chain. This
manual-install step is a debugging convenience, not a requirement for the
app to function.

### 13.2 Production / distribution notes

- **macOS still requires the one-time Keychain trust step above** in any
  distribution model, because Dart's `HttpClient` has no equivalent to
  OkHttp's fingerprint-pinning hook (see
  [ADR-006](./adr/ADR-006-flutter-for-desktop.md)). Document this as a
  required first-run step for end users, not an optional troubleshooting
  tip.
- **Android requires no manual cert install** in production — the
  fingerprint arrives via the pairing QR and is validated at connection
  time (§11.3). This is the entire point of
  [ADR-004](./adr/ADR-004-self-signed-tls.md).
- **Every time `scripts/generate_certs.sh` is re-run**, the fingerprint
  changes. Any already-paired phone will refuse to connect (by design —
  §11.3's pinning check fails closed) until it re-scans a fresh QR. Treat
  certificate rotation as equivalent to "re-pair all devices," and say so
  in release notes if this is ever automated (e.g. a scheduled cert
  rotation job) — silently rotating certs without warning users would
  turn a security feature into a confusing outage.

**Verification:** after a fresh `generate_certs.sh` run, an
already-paired phone's `PhoneStateService` logs a `CertificateException`
on its next reconnect attempt (§11.3's own verification step) — confirm
this is what actually happens rather than a silent fallback to
trust-all.

---

## 14. Unit Test

`test/core/crypto_service_test.dart`

```dart
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
    final tampered = token.substring(0, token.length - 1) + 'a';
    expect(CryptoService.verifyJWT(tampered), isNull);
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
```

```bash
flutter test
```

The rest of the test surface — the manual verification checklist and
Definition of Done — has moved to its own document so it can be run and
updated independently of implementation changes: see
[05_TEST_PLAN.md](./05_TEST_PLAN.md).

**Stop. Do not implement Tier 2 audio.**
