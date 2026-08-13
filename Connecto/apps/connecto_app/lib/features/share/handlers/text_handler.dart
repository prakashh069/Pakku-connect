import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../constants/share_constants.dart';
import '../models/share_event.dart';
import 'share_handler.dart';

/// Handles [ShareMime.text] shares.
///
/// Forwards the event to the native macOS popup via MethodChannel.
/// All work runs on the main isolate — no heavy processing involved.
class TextHandler implements ShareHandler {
  static const MethodChannel _channel =
      MethodChannel('com.connecto.app/clipboardShare');

  @override
  bool supports(String mime) =>
      mime.toLowerCase() == ShareMime.text;

  @override
  Future<void> handle(ShareEvent event) async {
    if (event.content.encoding != ShareEncoding.utf8) {
      debugPrint('[TextHandler] Unexpected encoding: ${event.content.encoding}');
      return;
    }
    final body = event.content.body;
    if (body is! String) {
      debugPrint('[TextHandler] body is not a String for text/plain share');
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
      debugPrint('[TextHandler] MethodChannel error (non-fatal): $e');
    }
  }
}
