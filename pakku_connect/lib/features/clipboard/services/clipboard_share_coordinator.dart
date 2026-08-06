import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../models/clipboard_share_event.dart';

/// Subscribes to the [ClipboardSyncManager.inboundShares] stream and
/// coordinates popup presentation via the native macOS layer.
///
/// Responsibilities:
///   - Subscribe to the inbound event stream
///   - Forward validated events to the native popup via MethodChannel
///   - Handle channel errors gracefully (best-effort; no retry)
///
/// This class has no clipboard business logic — that lives in [ClipboardSyncManager].
/// It is macOS-only in practice (attach() is a no-op on other platforms).
class ClipboardShareCoordinator {
  static const MethodChannel _channel =
      MethodChannel('com.pakku.connect/clipboardShare');

  StreamSubscription<ClipboardShareEvent>? _sub;

  /// Attaches this coordinator to the given stream.
  /// Calling attach() a second time cancels the previous subscription first.
  void attach(Stream<ClipboardShareEvent> stream) {
    _sub?.cancel();
    if (!Platform.isMacOS) return;
    _sub = stream.listen(_onEvent);
  }

  void _onEvent(ClipboardShareEvent event) {
    // text is passed in full — truncation is the popup's responsibility for display only.
    _channel.invokeMethod('showShare', {
      'id': event.id,
      'text': event.text,
      'imageBase64': event.imageBase64,
      'deviceName': event.deviceName,
    }).catchError((_) {
      // Channel errors are non-fatal. Best-effort only.
    });
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
