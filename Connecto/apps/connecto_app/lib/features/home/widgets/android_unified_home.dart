import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/services/websocket_service.dart';

class AndroidUnifiedHome extends StatelessWidget {
  final DeviceSessionState sessionState;
  final Map<String, dynamic>? batteryData;

  const AndroidUnifiedHome({
    super.key,
    required this.sessionState,
    this.batteryData,
  });

  Future<void> _handleUnpair(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('paired', false);
    if (context.mounted) {
      Navigator.of(context).pushReplacementNamed('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CustomColors>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isConnected = sessionState == DeviceSessionState.connected;
    
    // Always MacBook on Android Side
    const deviceName = "MacBook";
    
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Shift content up by removing Devices title
            
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
                      Icons.laptop_mac,
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
                  
                  if (batteryData != null && isConnected) ...[
                    const SizedBox(height: 32),
                    Container(height: 1, color: colors.border.withAlpha(100)),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          (batteryData!['charging'] as bool? ?? false) 
                              ? Icons.battery_charging_full 
                              : Icons.battery_full,
                          size: 18,
                          color: colors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${batteryData!['level'] ?? 0}%',
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
            
            // Unpair Button (styled as Status screen)
            OutlinedButton.icon(
              onPressed: () => _handleUnpair(context),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Unpair & Scan New Mac'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.primary,
                side: BorderSide(color: colors.primary.withAlpha(160)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 60), // Push the whole block up slightly
          ],
        ),
      ),
    );
  }
}
