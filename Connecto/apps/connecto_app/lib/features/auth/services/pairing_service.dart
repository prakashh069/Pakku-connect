import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> clearAllPairedState(SharedPreferences prefs) async {
  await prefs.setBool('paired', false);
  try {
    const secureStorage = FlutterSecureStorage(
      mOptions: MacOsOptions(
        usesDataProtectionKeychain: !kDebugMode,
      ),
    );
    await secureStorage.delete(key: 'hmacSecret');
    await secureStorage.delete(key: 'ws_ip');
    await secureStorage.delete(key: 'ws_port');
    await secureStorage.delete(key: 'cert_fp');
  } catch (_) {}
  await prefs.remove('hmacSecret');
  await prefs.remove('ws_ip');
  await prefs.remove('ws_port');
  await prefs.remove('cert_fp');
}
