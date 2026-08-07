import '../models/share_event.dart';

/// Interface for all Share handlers.
///
/// Each handler is responsible for a specific set of MIME types.
/// Handlers are registered once into [ShareHandlerRegistry] at startup.
///
/// Handler isolation contract:
///   An exception thrown inside [handle] must never propagate to the
///   registry or affect processing of subsequent messages.
///   Each handler must fail independently and silently.
///
/// Registration contract:
///   New MIME types MUST be supported by registering a new [ShareHandler].
///   Existing handlers must not be modified unless their MIME type logic changes.
abstract class ShareHandler {
  /// Returns true if this handler supports the given [mime] type.
  ///
  /// Comparison is always case-insensitive.
  bool supports(String mime);

  /// Processes the given [event].
  ///
  /// Implementations must be non-blocking from the caller's perspective.
  /// Any heavy work (image decode, I/O) must be dispatched internally
  /// and must not throw.
  Future<void> handle(ShareEvent event);
}
