import 'dart:async';
import 'dart:io';
import '../../share/handlers/share_handler_registry.dart';
import '../../share/models/share_event.dart';

/// Subscribes to the [ClipboardSyncManager.inboundShares] stream and
/// delegates each [ShareEvent] to the [ShareHandlerRegistry].
///
/// Responsibilities:
///   - Subscribe to the inbound event stream
///   - Delegate events to the appropriate handler via [ShareHandlerRegistry]
///   - Manage the subscription lifecycle
///
/// This class has no business logic — routing is owned by [ShareHandlerRegistry],
/// and all MIME-specific processing is owned by individual handlers.
/// It is macOS-only in practice (attach() is a no-op on other platforms).
class ClipboardShareCoordinator {
  final ShareHandlerRegistry _registry;
  StreamSubscription<ShareEvent>? _sub;

  ClipboardShareCoordinator()
      : _registry = ShareHandlerRegistry.withDefaults();

  /// Attaches this coordinator to the given [ShareEvent] stream.
  /// Calling attach() a second time cancels the previous subscription first.
  void attach(Stream<ShareEvent> stream) {
    _sub?.cancel();
    if (!Platform.isMacOS) return;
    _sub = stream.listen(_onEvent);
  }

  Future<void> _onEvent(ShareEvent event) async {
    await _registry.dispatch(event);
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
