import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../interfaces/auth_manager.dart';

class DeviceAuthManager implements AuthManager {
  Future<bool> isPaired() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('paired') ?? false;
  }

  Future<void> setPaired(bool paired) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('paired', paired);
  }

  Future<bool> hasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('onboarding_complete') ?? false;
  }

  /// Retrieves the HMAC secret from secure storage.
  /// Handles migration from SharedPreferences to SecureStorage.
  /// Returns null if not paired or if the secret is missing.
  Future<String?> getHmacSecret() async {
    final prefs = await SharedPreferences.getInstance();
    final paired = prefs.getBool('paired') ?? false;
    
    if (!paired) return null;

    final secureStorage = Platform.isMacOS 
        ? const FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: !kDebugMode))
        : const FlutterSecureStorage();

    String? hmacSecret;
    try {
      hmacSecret = await secureStorage.read(key: 'hmacSecret');
      if (hmacSecret != null) {
        debugPrint('DeviceAuthManager: Keychain read success');
      }
      
      // Migration from insecure SharedPreferences
      final insecureSecret = prefs.getString('hmacSecret');
      if (insecureSecret != null) {
        if (hmacSecret == null) {
          await secureStorage.write(key: 'hmacSecret', value: insecureSecret);
          hmacSecret = insecureSecret;
          debugPrint('DeviceAuthManager: Migrated hmacSecret from SharedPreferences to SecureStorage');
        }
        await prefs.remove('hmacSecret');
      }
    } catch (e) {
      debugPrint('DeviceAuthManager: Secure storage failed: $e');
    }

    if (hmacSecret == null) {
      // Paired but no secret — force unpair so we don't loop forever.
      await prefs.setBool('paired', false);
    }
    
    return hmacSecret;
  }
}
