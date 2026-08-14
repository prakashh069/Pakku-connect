import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:pasteboard/pasteboard.dart';
import '../../../core/services/platform_transport.dart';

class ShareManager {
  final PlatformTransport _transport;
  StreamSubscription? _subscription;
  static const MethodChannel _channel = MethodChannel('com.connecto.app/notifications');

  ShareManager(this._transport);

  void start() {
    _subscription = _transport.messages.listen(_onMessage);
    debugPrint('[ShareManager] Started listening to PlatformTransport messages');
  }

  void stop() {
    _subscription?.cancel();
  }

  void _onMessage(Map<String, dynamic> msg) async {
    if (msg['type'] != 'share.clipboard') return;
    
    // Strict discriminator enforcement
    if (msg['source'] != 'share_sheet') return;
    
    // Version enforcement
    if (msg['version'] != 1) {
      debugPrint('[ShareManager] Dropped payload: Invalid version ${msg['version']}');
      return;
    }
    
    final payload = msg['payload'];
    if (payload == null || payload is! Map<String, dynamic>) {
      debugPrint('[ShareManager] Dropped payload: Missing or invalid payload object');
      return;
    }
    
    final mime = payload['mime']?.toString();
    final content = payload['content']?.toString();
    final sha256 = payload['sha256']?.toString();
    
    if (mime == null || content == null) {
      debugPrint('[ShareManager] Dropped payload: Missing required fields');
      return;
    }
    
    try {
      if (mime == 'text/plain') {
        await Clipboard.setData(ClipboardData(text: content));
        await _showNotification('Copied to Clipboard', 'Text copied from Phone');
      } else if (mime == 'image/jpeg' || mime == 'image/png') {
        if (sha256 == null) {
          debugPrint('[ShareManager] Dropped image: Missing SHA256');
          return;
        }

        final imageBytes = base64Decode(content);
        final calculatedHash = sha256Hash(imageBytes).toLowerCase();
        
        if (sha256.toLowerCase() != calculatedHash) {
          debugPrint('[ShareManager] Dropped image: SHA256 mismatch');
          return;
        }

        await Pasteboard.writeImage(imageBytes);
        
        await _showNotification('Image Copied', 'Image copied from Phone');
      } else {
        debugPrint('[ShareManager] Dropped payload: Unsupported MIME type $mime');
      }
    } catch (e) {
      debugPrint('[ShareManager] Failed to process share payload: $e');
    }
  }

  Future<void> _showNotification(String title, String body) async {
    try {
      await _channel.invokeMethod('showNotification', {
        'id': 'share_${DateTime.now().millisecondsSinceEpoch}',
        'title': title,
        'body': body,
        'package': 'com.connecto.app',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'canReply': false,
      });
    } catch (e) {
      debugPrint('[ShareManager] Failed to show notification: $e');
    }
  }

  String sha256Hash(Uint8List data) {
    final digest = sha256Lib.convert(data);
    return digest.toString();
  }
}

final sha256Lib = sha256;
