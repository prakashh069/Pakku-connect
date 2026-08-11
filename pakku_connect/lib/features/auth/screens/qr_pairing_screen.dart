import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/services/crypto_service.dart';
import '../../../core/constants/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../../core/services/websocket_service.dart';

class QrPairingScreen extends StatefulWidget {
  const QrPairingScreen({super.key});

  @override
  State<QrPairingScreen> createState() => _QrPairingScreenState();
}

class _QrPairingScreenState extends State<QrPairingScreen> {
  String? _qrData;
  String? _error;
  bool _generating = false;

  // Keep the secret in memory for this session so rebuilds don't regenerate it.
  // Regeneration only happens on first load or when user taps "Generate New Code".
  String? _sessionHmacSecret;

  @override
  void initState() {
    super.initState();
    _generateQR(forceNew: true);
  }

  Future<void> _generateQR({bool forceNew = false}) async {
    if (_generating) return;
    setState(() {
      _generating = true;
      _error = null;
    });

    final info = NetworkInfo();
    String? ip;
    try {
      ip = await info.getWifiIP();
    } catch (e, st) {
      debugPrint('QrPairingScreen: Failed to get WiFi IP: $e\n$st');
    }

    if (ip == null || ip == '127.0.0.1' || ip.isEmpty) {
      setState(() {
        _generating = false;
        _error = 'Could not determine WiFi IP address. Please connect to a WiFi network.';
      });
      return;
    }

    final port = 8080;

    String? certFp;
    try {
      certFp = await CryptoService.certFingerprint('certs/device.der');
    } catch (e, st) {
      debugPrint('QrPairingScreen: Failed to read cert fingerprint: $e\n$st');
    }

    // Only generate a new secret when forced (first load or "Generate New Code").
    // Widget rebuilds reuse _sessionHmacSecret so the QR stays valid.
    if (forceNew || _sessionHmacSecret == null) {
      _sessionHmacSecret = CryptoService.generateHmacSecret();

      // Persist the secret — try Keychain first, fall back to SharedPreferences.
      try {
        const secureStorage = FlutterSecureStorage();
        await secureStorage.write(key: 'hmacSecret', value: _sessionHmacSecret);
      } catch (e) {
        debugPrint('QrPairingScreen: Keychain failed ($e), saving to SharedPreferences');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('hmacSecret', _sessionHmacSecret!);
      }

      // Provision the relay with the new secret.
      if (mounted) {
        try {
          final ws = Provider.of<WebSocketService>(context, listen: false);
          ws.connect('wss://127.0.0.1:$port', hmacSecret: _sessionHmacSecret, certFp: certFp);
        } catch (_) {}
      }
    }

    // Build the QR JWT using the current session secret.
    final token = CryptoService.generateJWT(
      hmacSecret: _sessionHmacSecret!,
      deviceId: 'macos_${Platform.localHostname}',
      deviceName: Platform.localHostname,
      platform: 'macOS',
      wsIp: ip,
      wsPort: port,
      certFp: certFp,
      includeSecretInPayload: true,
    );

    if (mounted) {
      setState(() {
        _qrData = token;
        _generating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CustomColors>()!;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        centerTitle: true,
        title: Image.asset('assets/images/app_logo.png', height: 32),
        backgroundColor: colors.surface,
      ),
      body: Center(
        child: SingleChildScrollView(
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
                    size: 350,
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
              onPressed: _generating ? null : () => _generateQR(forceNew: true),
              child: const Text('Generate New Code'),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
