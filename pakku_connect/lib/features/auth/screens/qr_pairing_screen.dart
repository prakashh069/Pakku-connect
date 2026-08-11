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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;
    final borderColor = isDark ? Colors.white24 : Colors.black12;
    final cardColor = isDark ? colors.surface : Colors.white;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Logo
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset('assets/images/app_logo.png', width: 32, height: 32),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Pakku Connect',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colors.success, // Use green color
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                // Main Card
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  padding: const EdgeInsets.all(48),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor, width: 1),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    // Left Side - Instructions
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Scan to log in',
                            style: TextStyle(
                              fontSize: 28,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 40),
                          
                          // Custom Steps List with vertical lines
                          _buildStepsList(textColor, borderColor),

                          const SizedBox(height: 32),
                          InkWell(
                            onTap: () {},
                            child: Text(
                              'Need help? ↗',
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.underline,
                                decorationColor: textColor,
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),
                          
                          InkWell(
                            onTap: _generating ? null : () => _generateQR(forceNew: true),
                            child: Text(
                              'Generate new code >',
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.underline,
                                decorationColor: textColor,
                              ),
                            ),
                          ),
                          if (_error != null) ...[
                             const SizedBox(height: 16),
                             Text(_error!, style: TextStyle(color: colors.danger, fontSize: 14)),
                          ],
                        ],
                      ),
                    ),
                    
                    const SizedBox(width: 48),
                    
                    // Right Side - QR Code
                    if (_qrData != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: QrImageView(
                          data: _qrData!,
                          size: 264,
                          backgroundColor: Colors.white,
                          embeddedImage: const AssetImage('assets/images/app_logo.png'),
                          embeddedImageStyle: const QrEmbeddedImageStyle(
                            size: Size(56, 56),
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
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildStepsList(Color textColor, Color borderColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepItem(1, 'Open Pakku Connect on your phone', hasLine: true, textColor: textColor, borderColor: borderColor),
        _buildStepItem(2, 'Tap the scan button to open the camera', hasLine: true, textColor: textColor, borderColor: borderColor),
        _buildStepItem(3, 'Point your phone to this screen to pair', hasLine: false, textColor: textColor, borderColor: borderColor),
      ],
    );
  }

  Widget _buildStepItem(int number, String text, {required bool hasLine, required Color textColor, required Color borderColor}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  border: Border.all(color: borderColor),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    number.toString(),
                    style: TextStyle(fontSize: 12, color: textColor),
                  ),
                ),
              ),
              if (hasLine)
                Expanded(
                  child: Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: borderColor,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Text(
                text,
                style: TextStyle(fontSize: 16, color: textColor),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
