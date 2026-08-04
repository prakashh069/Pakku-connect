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

  Future<void> _requestPermissions() async {
    try {
      await _platform.invokeMethod('requestCallLogPermission');
    } catch (e, st) {
      debugPrint('ScanScreen: requestCallLogPermission failed (non-fatal): $e\n$st');
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

    final payload = CryptoService.verifyJWT(code);
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

    await _requestPermissions();

    try {
      await _platform.invokeMethod(
        'saveWsEndpoint',
        {'ip': ip, 'port': port, 'certFp': certFp},
      );
      await _platform.invokeMethod('startPhoneStateService');
      
      const storage = FlutterSecureStorage();
      await storage.write(key: 'ws_ip', value: ip);
      await storage.write(key: 'ws_port', value: port.toString());
      if (certFp != null) {
        await storage.write(key: 'cert_fp', value: certFp);
      }
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('paired', true);

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
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
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('Scan QR Code')),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
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
