import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  @override
  void initState() {
    super.initState();
    debugPrint('ScanScreen: initState called');
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<bool> _requestPermissions() async {
    try {
      final granted = await _platform.invokeMethod<bool>('requestAllPermissions');
      return granted ?? false;
    } catch (e, st) {
      debugPrint('ScanScreen: requestAllPermissions failed: $e\n$st');
      return false;
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    debugPrint('ScanScreen: _onDetect called');
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || _verifying) return;

    setState(() {
      _verifying = true;
      _error = null;
    });

    final unverified = CryptoService.extractUnverifiedPayload(code);
    final hmacSecret = unverified?['hmac_secret'] as String?;

    if (hmacSecret == null) {
      setState(() {
        _verifying = false;
        _error = 'QR missing security provisioning (hmac_secret)';
      });
      return;
    }

    final payload = CryptoService.verifyJWT(code, hmacSecret);
    if (payload == null) {
      setState(() {
        _verifying = false;
        _error = 'Invalid or expired QR code';
      });
      return;
    }

    final ip = payload['ws_ip'] as String?;
    final portRaw = payload['ws_port'];
    final port = portRaw is int ? portRaw : int.tryParse(portRaw?.toString() ?? '');
    final certFp = payload['cert_fp'] as String?;
    if (ip == null || port == null || port < 1 || port > 65535) {
      setState(() {
        _verifying = false;
        _error = 'QR missing valid connection details';
      });
      return;
    }

    try {
      await _platform.invokeMethod(
        'saveWsEndpoint',
        {'ip': ip, 'port': port, 'certFp': certFp, 'hmacSecret': hmacSecret},
      );
      
      const storage = FlutterSecureStorage();
      await storage.write(key: 'ws_ip', value: ip);
      await storage.write(key: 'ws_port', value: port.toString());
      await storage.write(key: 'hmacSecret', value: hmacSecret);
      if (certFp != null) {
        await storage.write(key: 'cert_fp', value: certFp);
      }
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('paired', true);

      final granted = await _requestPermissions();

      if (granted) {
        final hasNotifAccess = await _platform.invokeMethod<bool>('hasNotificationAccess') ?? false;
        if (!hasNotifAccess) {
            await _platform.invokeMethod('requestNotificationAccess');
        }

        await _platform.invokeMethod('startPhoneStateService');
        // Request call screening role so CallScreeningPrototypeService
        // can provide caller ID on Samsung Android 16+
        try {
          await _platform.invokeMethod('requestCallScreeningRole');
        } catch (e) {
          debugPrint('ScanScreen: requestCallScreeningRole failed (non-fatal): $e');
        }
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      } else {
        setState(() {
          _verifying = false;
          _error = 'READ_PHONE_STATE is required for remote call control.\n\nREAD_CONTACTS is required for contact synchronization.\n\nPlease grant these permissions in Android Settings to use the app.';
        });
      }
    } catch (e, st) {
      debugPrint('ScanScreen: Native setup failed: $e\n$st');
      setState(() {
        _verifying = false;
        _error = 'Failed to configure native service. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan QR code', style: TextStyle(color: Colors.white, fontSize: 20)),
        backgroundColor: const Color(0xFF111B21),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              debugPrint('ScanScreen: MobileScanner errorBuilder triggered: ${error.errorCode} - ${error.errorDetails?.message}');
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error, color: Colors.white, size: 50),
                    const SizedBox(height: 12),
                    Text(
                      'Scanner Error: ${error.errorCode}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              );
            },
          ),
          
          // Translucent overlay with a clear square hole
          Positioned.fill(
            child: CustomPaint(
              painter: ScannerOverlayPainter(),
            ),
          ),

          // Top instructional text background
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: const Color(0xFF111B21),
              padding: const EdgeInsets.only(left: 32, right: 32, top: 16, bottom: 24),
              child: const Text(
                'Open the Connecto Mac app on your computer to pair.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                ),
              ),
            ),
          ),

          if (_verifying) const Center(child: CircularProgressIndicator(color: Colors.white)),
          if (_error != null)
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: const Color(0xFF111B21),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 16), textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () {
                        setState(() => _error = null);
                        controller.start();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    
    // QR Code scanner hole size
    final scanAreaSize = size.width * 0.70; 
    final scanAreaRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: scanAreaSize,
      height: scanAreaSize,
    );
    final holePath = Path()..addRRect(RRect.fromRectAndRadius(scanAreaRect, const Radius.circular(12)));

    // Create a path that is the background minus the hole
    final path = Path.combine(PathOperation.difference, backgroundPath, holePath);
    
    final paint = Paint()..color = Colors.black.withOpacity(0.55);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
