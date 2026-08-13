import 'package:flutter/foundation.dart';
import '../models/share_event.dart';
import 'share_handler.dart';
import 'text_handler.dart';
import 'image_handler.dart';

/// Registry for all [ShareHandler] implementations.
///
/// Lifecycle:
///   The registry is created once, all handlers are registered,
///   and it becomes immutable afterwards. No runtime registration
///   is permitted.
///
/// Handler isolation:
///   An exception thrown by one handler will never propagate to the
///   registry or prevent subsequent messages from being processed.
///   Each handler fails independently and silently.
///
/// MIME matching:
///   All MIME comparisons are delegated to the individual handler's
///   [ShareHandler.supports] method, which must perform case-insensitive
///   matching.
class ShareHandlerRegistry {
  final List<ShareHandler> _handlers;

  ShareHandlerRegistry._internal(this._handlers);

  @visibleForTesting
  ShareHandlerRegistry.forTesting(this._handlers);

  /// Creates the default registry with all built-in handlers.
  ///
  /// Handlers are evaluated in registration order. The first handler
  /// whose [supports] returns true wins.
  factory ShareHandlerRegistry.withDefaults() {
    return ShareHandlerRegistry._internal([
      TextHandler(),
      ImageHandler(),
    ]);
  }

  /// Dispatches [event] to the first handler that supports [event.mime].
  ///
  /// If no handler matches, the event is dropped silently — this is
  /// intentional. Unknown MIME types must never crash the app.
  ///
  /// Handler exceptions are caught here so that a failure in one
  /// handler never affects future messages.
  Future<void> dispatch(ShareEvent event) async {
    final mime = event.mime.toLowerCase();

    for (final handler in _handlers) {
      if (handler.supports(mime)) {
        try {
          await handler.handle(event);
        } catch (e, st) {
          // Handler failed independently — do not re-throw.
          debugPrint('[ShareHandlerRegistry] Handler error (dropped): $e\n$st');
        }
        return;
      }
    }

    debugPrint('[ShareHandlerRegistry] No handler for mime="$mime" — dropped.');
  }
}
