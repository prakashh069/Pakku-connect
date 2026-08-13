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
        final hasNotifAccess =
            await _platform.invokeMethod<bool>('hasNotificationAccess') ?? false;
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
          _error =
              'READ_PHONE_STATE is required for remote call control.\n\n'
              'READ_CONTACTS is required for contact synchronization.\n\n'
              'Please grant these permissions in Android Settings to use the app.';
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
    final colors = Theme.of(context).extension<CustomColors>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Header & overlay colours — brand-aware
    final headerBg = isDark ? colors.surface : colors.surface;
    final headerText = colors.textSecondary;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: headerBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Image.asset(
          isDark
              ? 'assets/images/connecto_logo_dark.png'
              : 'assets/images/connecto_logo_light.png',
          height: 28,
          fit: BoxFit.contain,
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Camera feed
          MobileScanner(
            controller: controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              debugPrint(
                  'ScanScreen: MobileScanner errorBuilder triggered: ${error.errorCode} - ${error.errorDetails?.message}');
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline,
                        color: colors.danger, size: 52),
                    const SizedBox(height: 12),
                    Text(
                      'Scanner Error: ${error.errorCode}',
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ],
                ),
              );
            },
          ),

          // Translucent overlay with branded scan hole
          Positioned.fill(
            child: CustomPaint(
              painter: _ScannerOverlayPainter(
                borderColor: colors.primary,
                accentColor: colors.accent,
              ),
            ),
          ),

          // Top instructional banner
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: headerBg.withAlpha(230),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              child: Text(
                'Open the Connecto Mac app on your computer to pair.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: headerText,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          ),

          // Verifying spinner
          if (_verifying)
            const Center(
                child: CircularProgressIndicator(color: Colors.white)),

          // Error card
          if (_error != null)
            Center(
              child: Container(
                padding: const EdgeInsets.all(28),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline,
                        color: colors.danger, size: 36),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 14,
                          height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 12),
                      ),
                      onPressed: () {
                        setState(() => _error = null);
                        controller.start();
                      },
                      child: const Text('Try Again',
                          style: TextStyle(fontWeight: FontWeight.w600)),
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

// ---------------------------------------------------------------------------
// Branded scanner overlay
// ---------------------------------------------------------------------------
class _ScannerOverlayPainter extends CustomPainter {
  final Color borderColor;
  final Color accentColor;

  const _ScannerOverlayPainter({
    required this.borderColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPath =
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final scanAreaSize = size.width * 0.70;
    final scanAreaRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: scanAreaSize,
      height: scanAreaSize,
    );
    final holePath = Path()
      ..addRRect(RRect.fromRectAndRadius(
          scanAreaRect, const Radius.circular(16)));

    final path =
        Path.combine(PathOperation.difference, backgroundPath, holePath);
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.60);
    canvas.drawPath(path, paint);

    // Branded corner brackets
    _drawCorners(canvas, scanAreaRect);
  }

  void _drawCorners(Canvas canvas, Rect rect) {
    const cornerLen = 24.0;
    const strokeWidth = 3.0;
    const r = 4.0;

    final paint = Paint()
      ..color = borderColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Top-left
    canvas.drawLine(
        rect.topLeft + const Offset(r, 0),
        rect.topLeft + const Offset(cornerLen, 0),
        paint);
    canvas.drawLine(
        rect.topLeft + const Offset(0, r),
        rect.topLeft + const Offset(0, cornerLen),
        paint);

    // Top-right
    canvas.drawLine(
        rect.topRight - const Offset(cornerLen, 0),
        rect.topRight - const Offset(r, 0),
        paint);
    canvas.drawLine(
        rect.topRight + const Offset(0, r),
        rect.topRight + const Offset(0, cornerLen),
        paint);

    // Bottom-left
    canvas.drawLine(
        rect.bottomLeft + const Offset(r, 0),
        rect.bottomLeft + const Offset(cornerLen, 0),
        paint);
    canvas.drawLine(
        rect.bottomLeft - const Offset(0, cornerLen),
        rect.bottomLeft - const Offset(0, r),
        paint);

    // Bottom-right
    canvas.drawLine(
        rect.bottomRight - const Offset(cornerLen, 0),
        rect.bottomRight - const Offset(r, 0),
        paint);
    canvas.drawLine(
        rect.bottomRight - const Offset(0, cornerLen),
        rect.bottomRight - const Offset(0, r),
        paint);
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) =>
      oldDelegate.borderColor != borderColor ||
      oldDelegate.accentColor != accentColor;
}
