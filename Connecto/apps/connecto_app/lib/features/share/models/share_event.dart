import 'share_content.dart';

/// A validated, deduplicated share event received from the remote device.
///
/// Produced by [ClipboardSyncManager] and consumed by [ShareHandlerRegistry].
///
/// This object is MIME-agnostic — it carries any content type the
/// framework supports. Handlers inspect [mime] to decide whether
/// they can process the event.
///
/// Payload immutability contract:
///   Receivers must treat the payload as immutable. Handlers may read
///   [content] but must never mutate it.
///
/// Timestamp semantics:
///   [timestamp] is the sender's local Unix epoch milliseconds.
///   It is informational only and must never be used for ordering,
///   deduplication, or conflict resolution. Deduplication is based
///   solely on [id].
class ShareEvent {
  /// UUID-v4 used for deduplication. Never used for ordering.
  final String id;

  /// MIME type of the shared content (case-insensitive on the receiver).
  /// Use [ShareMime] constants when constructing events.
  final String mime;

  /// Human-readable source device name (e.g. "Pixel 8").
  final String deviceName;

  /// Sender's local Unix epoch milliseconds. Informational only.
  final int timestamp;

  final ShareContent content;
  final int? size;
  final String? sha256;

  const ShareEvent({
    required this.id,
    required this.mime,
    required this.deviceName,
    required this.timestamp,
    required this.content,
    this.size,
    this.sha256,
  });
}
