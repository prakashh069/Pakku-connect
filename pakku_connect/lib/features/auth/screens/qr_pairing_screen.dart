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
    String? ip;
    try {
      ip = await info.getWifiIP();
    } catch (e, st) {
      debugPrint('QrPairingScreen: Failed to get WiFi IP: $e\n$st');
    }
    
    if (ip == null || ip == '127.0.0.1' || ip.isEmpty) {
      setState(() => _error = 'Could not determine WiFi IP address. Please ensure you are connected to a network.');
      return;
    }

    final port = int.tryParse(dotenv.env['PAKKU_WS_PORT'] ?? '8080') ?? 8080;

    String? certFp;
    try {
      // See docs/04_IMPLEMENTATION_GUIDE.md §3 — must be the DER fingerprint.
      certFp = await CryptoService.certFingerprint('certs/device.der');
    } catch (e, st) {
      debugPrint('QrPairingScreen: Failed to read cert fingerprint: $e\n$st');
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
