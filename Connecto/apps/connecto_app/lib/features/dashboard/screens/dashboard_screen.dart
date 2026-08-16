import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/services/websocket_service.dart';
import 'package:flutter/services.dart';

class DashboardScreen extends StatefulWidget {
  final DeviceSessionState sessionState;

  const DashboardScreen({
    super.key,
    this.sessionState = DeviceSessionState.connected,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _batteryData;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ws = context.read<WebSocketService>();
      ws.onBatteryStatus = (data) {
        if (mounted) {
          setState(() {
            _batteryData = data;
          });
        }
      };
    });
  }

  Future<void> _unpair() async {
    final ws = context.read<WebSocketService>();
    if (Platform.isMacOS) {
      try {
        await ws.send({'type': 'unpair'});
        await Future.delayed(const Duration(milliseconds: 100)); // allow flush
      } catch (_) {}
    } else {
      try {
        const platform = MethodChannel('com.connecto.app/platform');
        platform.invokeMethod('unpair');
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('paired', false);
    await prefs.remove('hmacSecret');
    await prefs.remove('ws_ip');
    await prefs.remove('ws_port');
    await prefs.remove('cert_fp');
    
    ws.reset();

    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CustomColors>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isConnected = widget.sessionState == DeviceSessionState.connected;
    
    // Fallback names for now
    final deviceName = Platform.isMacOS ? "Android Device" : "MacBook";
    
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Image.asset(
          isDark
              ? 'assets/images/connecto_logo_dark.png'
              : 'assets/images/connecto_logo_light.png',
          height: 32,
          fit: BoxFit.contain,
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings_outlined, color: colors.lightText),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).pushNamed('/settings');
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Devices',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: colors.textSecondary.withAlpha(180),
                ).copyWith(fontFamily: '.SF Pro Text'),
              ),
              const SizedBox(height: 32),
              
              // Device Status Card
              Container(
                width: 320,
                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(isDark ? 40 : 10),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    )
                  ],
                  border: Border.all(color: colors.border.withAlpha(isDark ? 30 : 60)),
                ),
                child: Column(
                  children: [
                    // Device Icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: isConnected ? colors.success.withAlpha(20) : colors.danger.withAlpha(20),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Platform.isMacOS ? Icons.phone_android : Icons.laptop_mac,
                        size: 40,
                        color: isConnected ? colors.success : colors.danger,
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Device Name
                    Text(
                      deviceName,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                        letterSpacing: -0.5,
                      ).copyWith(fontFamily: '.SF Pro Display'),
                    ),
                    const SizedBox(height: 8),
                    
                    // Connection Status
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isConnected ? Icons.check_circle : Icons.error_outline,
                          size: 16,
                          color: isConnected ? colors.success : colors.danger,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isConnected ? 'Connected' : 'Offline',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: isConnected ? colors.success : colors.danger,
                          ).copyWith(fontFamily: '.SF Pro Text'),
                        ),
                      ],
                    ),
                    
                    if (_batteryData != null && isConnected) ...[
                      const SizedBox(height: 32),
                      Container(height: 1, color: colors.border.withAlpha(100)),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            (_batteryData!['charging'] as bool? ?? false) 
                                ? Icons.battery_charging_full 
                                : Icons.battery_full,
                            size: 18,
                            color: colors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_batteryData!['level'] ?? 0}%',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Last Synced
              Text(
                'Last synced:\nJust now',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                ).copyWith(fontFamily: '.SF Pro Text'),
              ),
              
              const SizedBox(height: 48),
              
              // Unpair Button
              TextButton.icon(
                onPressed: _unpair,
                icon: Icon(Icons.link_off, size: 18, color: colors.danger.withAlpha(200)),
                label: Text(
                  'Disconnect Device',
                  style: TextStyle(color: colors.danger.withAlpha(200)),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: colors.danger.withAlpha(20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
