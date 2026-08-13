import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../constants/share_constants.dart';
import '../models/share_event.dart';
import 'share_handler.dart';

/// Handles image/* shares (image/png, image/jpeg, image/webp).
///
/// Forwards the event to the native macOS popup via MethodChannel.
/// The native side is responsible for background Base64 decoding
/// and lazy NSImage creation.
class ImageHandler implements ShareHandler {
  static const MethodChannel _channel =
      MethodChannel('com.pakku.connect/clipboardShare');

  static const _supportedMimes = {
    ShareMime.png,
    ShareMime.jpeg,
    ShareMime.webp,
  };

  @override
  bool supports(String mime) =>
      _supportedMimes.contains(mime.toLowerCase());

  @override
  Future<void> handle(ShareEvent event) async {
    if (event.content.encoding != ShareEncoding.base64) {
      debugPrint('[ImageHandler] Unexpected encoding: ${event.content.encoding}');
      return;
    }
    final body = event.content.body;
    if (body is! String || body.isEmpty) {
      debugPrint('[ImageHandler] body is empty or not a String for ${event.mime} share');
      return;
    }

    // Enforce encoded payload size limit before sending to native.
    if (body.length > ShareLimits.maxEncodedPayloadBytes) {
      debugPrint('[ImageHandler] Payload exceeds ${ShareLimits.maxEncodedPayloadBytes} bytes — dropping.');
      return;
    }

    try {
      await _channel.invokeMethod('showShare', {
        'id':         event.id,
        'mime':       event.mime,
        'deviceName': event.deviceName,
        'content': {
          'encoding': event.content.encoding,
          'body':     body,
          if (event.content.metadata != null)
            'metadata': event.content.metadata,
        },
      });
    } catch (e) {
      // Channel errors are non-fatal — best-effort only.
      debugPrint('[ImageHandler] MethodChannel error (non-fatal): $e');
    }
  }
}
