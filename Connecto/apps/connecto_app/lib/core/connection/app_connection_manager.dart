import 'package:flutter/foundation.dart';
import '../../features/relay/services/relay_manager.dart';
import '../services/websocket_service.dart';
import '../services/crypto_service.dart';
import '../constants/app_constants.dart';
import '../interfaces/connection_manager.dart';

class AppConnectionManager implements ConnectionManager {
  final WebSocketService _ws;
  final RelayManager _relayManager;

  AppConnectionManager(this._ws, this._relayManager);

  /// Initializes the secure WebSocket connection to the relay
  Future<void> startConnection(String hmacSecret) async {
    if (hmacSecret.isEmpty) {
      debugPrint('AppConnectionManager: Waiting for pairing before WebSocket connection.');
      return;
    }

    final port = '$kRelayPort';
    
    String? certFp;
    try {
      certFp = await CryptoService.certFingerprint('certs/device.der');
    } catch (e) {
      debugPrint('AppConnectionManager: Could not compute local certFp: $e');
    }
    
    _relayManager.setSecret(hmacSecret);
    _ws.connect('wss://127.0.0.1:$port', hmacSecret: hmacSecret, certFp: certFp);
  }
}
