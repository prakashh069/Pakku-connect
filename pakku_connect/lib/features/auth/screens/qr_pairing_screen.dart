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
    final bgColor = const Color(0xFFF9F7F4); // Light beige background

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Left Logo Area
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset('assets/images/app_logo.png', width: 32, height: 32),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Pakku Connect',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            // Main Card
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Container(
                    width: 900,
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    padding: const EdgeInsets.all(48),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Side - Instructions
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Scan to log in',
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w300,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 40),
                              _buildStep(1, 'Open Pakku Connect on your phone'),
                              const SizedBox(height: 24),
                              _buildStep(2, 'Tap the scan button to open the camera'),
                              const SizedBox(height: 24),
                              _buildStep(3, 'Point your phone to this screen to pair'),
                              const SizedBox(height: 48),
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 24),
                                  child: Text(
                                    _error!,
                                    style: TextStyle(color: colors.danger, fontSize: 14),
                                  ),
                                ),
                              TextButton(
                                onPressed: _generating ? null : () => _generateQR(forceNew: true),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  backgroundColor: colors.accent.withOpacity(0.1),
                                ),
                                child: Text(
                                  'Generate New Code',
                                  style: TextStyle(color: colors.accent, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Right Side - QR Code
                        const SizedBox(width: 48),
                        if (_qrData != null)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: QrImageView(
                              data: _qrData!,
                              size: 300,
                              backgroundColor: Colors.white,
                              embeddedImage: const AssetImage('assets/images/app_logo.png'),
                              embeddedImageStyle: const QrEmbeddedImageStyle(
                                size: Size(64, 64),
                              ),
                              eyeStyle: const QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: Colors.black87,
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: Colors.black87,
                              ),
                            ),
                          )
                        else
                          const SizedBox(
                            width: 332,
                            height: 332,
                            child: Center(child: CircularProgressIndicator()),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(int number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black54),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number.toString(),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 18, color: Colors.black87, height: 1.3),
          ),
        ),
      ],
    );
  }
}
