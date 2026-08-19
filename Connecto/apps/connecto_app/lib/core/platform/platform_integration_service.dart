import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../interfaces/platform_integration.dart';

class PlatformIntegrationService implements PlatformIntegration {
  Future<void> startAndroidPhoneStateService() async {
    if (!Platform.isAndroid) return;
    
    try {
      const platform = MethodChannel('com.connecto.app/platform');
      await platform.invokeMethod('startPhoneStateService');
      // Request call screening role for caller ID on Samsung Android 16+
      try {
        await platform.invokeMethod('requestCallScreeningRole');
      } catch (_) {}
    } catch (e, st) {
      debugPrint('Failed to start PhoneStateService: $e\n$st');
    }
  }

  void updateMacOsMenuBarStatus(String stateName) {
    if (!Platform.isMacOS) return;
    
    const menuBarChannel = MethodChannel('com.connecto.app/menuBar');
    menuBarChannel.invokeMethod('updateStatus', {'state': stateName});
  }
}
