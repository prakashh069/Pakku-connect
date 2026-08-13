import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/services/crypto_service.dart';
import '../../../core/constants/app_theme.dart';
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
  // Regeneration only happens on first load (no existing secret) or when
  // the user explicitly taps "Generate New Code".
  String? _sessionHmacSecret;

  // Shared SecureStorage instance so both load and write use identical options.
  static const _secureStorage = FlutterSecureStorage(
    mOptions: MacOsOptions(
      usesDataProtectionKeychain: !kDebugMode,
    ),
  );

  @override
  void initState() {
    super.initState();
    // On screen open: load the existing secret first so an in-progress pairing
    // session is never broken by a screen rebuild or back-navigation.
    // forceNew=false means "use Keychain secret if available, generate only
    // if nothing exists yet."
    _loadExistingSecretOrGenerate();
  }

  /// Reads the current hmacSecret from the Keychain.
  /// - If a secret is found, reuses it for the QR so an existing pairing
  ///   session stays valid across screen rebuilds.
  /// - If no secret exists, falls through to _generateQR which creates one.
  Future<void> _loadExistingSecretOrGenerate() async {
    try {
      final existing = await _secureStorage.read(key: 'hmacSecret');
      if (existing != null && existing.isNotEmpty) {
        debugPrint('QrPairingScreen: Reusing existing Keychain secret.');
        _sessionHmacSecret = existing;
        // Render the QR using the existing secret without writing a new one.
        await _generateQR(forceNew: false);
        return;
      }
    } catch (e) {
      debugPrint('QrPairingScreen: Could not read Keychain during init: $e');
    }
    // No existing secret — generate a fresh one for first-time pairing.
    await _generateQR(forceNew: true);
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

    // Generate a new secret only when explicitly forced (user tapped
    // "Generate New Code") OR when no in-memory secret exists yet.
    if (forceNew || _sessionHmacSecret == null) {
      _sessionHmacSecret = CryptoService.generateHmacSecret();

      // Persist the new secret — Keychain only, no plaintext fallback.
      try {
        await _secureStorage.write(key: 'hmacSecret', value: _sessionHmacSecret);
        debugPrint('Keychain write success');
      } catch (e) {
        debugPrint('QrPairingScreen: Keychain failed ($e)');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Security Error: Unable to access Keychain. Ensure macOS entitlements are configured.'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _generating = false;
            _error = 'Security Error: Unable to access Keychain. Ensure macOS entitlements are configured.';
          });
        }
        return; // Prevent QR generation if secret is not safely stored.
      }
    }

    // Provision the relay with the current secret.
    if (mounted) {
      try {
        final ws = Provider.of<WebSocketService>(context, listen: false);
        ws.connect('wss://127.0.0.1:$port', hmacSecret: _sessionHmacSecret, certFp: certFp);
      } catch (_) {}
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
    final borderColor = isDark ? Colors.white24 : colors.primary;
    final cardColor = isDark ? colors.surface : Colors.white;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Logo
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Image.asset(
                      Theme.of(context).brightness == Brightness.dark
                          ? 'assets/images/connecto_logo_dark.png'
                          : 'assets/images/connecto_logo_light.png',
                      height: 42,
                      fit: BoxFit.contain,
                    ),
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
                                color: colors.accent,
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.underline,
                                decorationColor: colors.accent,
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),
                          
                          InkWell(
                            onTap: _generating ? null : () => _generateQR(forceNew: true),
                            child: Text(
                              'Generate new code >',
                              style: TextStyle(
                                color: colors.primary,
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.underline,
                                decorationColor: colors.primary,
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
                            color: Color(0xFF122C25),
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Color(0xFF122C25),
                          ),
                        ),
                      )
                    else if (_generating)
                      const SizedBox(
                        width: 288,
                        height: 288,
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else
                      SizedBox(
                        width: 288,
                        height: 288,
                        child: Center(
                          child: Icon(Icons.error_outline, color: colors.danger, size: 48),
                        ),
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
        _buildStepItem(1, 'Open Connecto on your phone', hasLine: true, textColor: textColor, borderColor: borderColor),
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
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: borderColor,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    number.toString(),
                    style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                        fontWeight: FontWeight.w600),
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
