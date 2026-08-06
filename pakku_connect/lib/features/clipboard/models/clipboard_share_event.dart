/// Represents a validated, deduplicated clipboard share event received
/// from the remote device. Produced by [ClipboardSyncManager] and consumed
/// by [ClipboardShareCoordinator].
class ClipboardShareEvent {
  /// UUID-v4 used for deduplication. Never used for ordering.
  final String id;

  /// Full, untruncated clipboard text. Never truncate before passing to the coordinator.
  final String? text;

  /// Base64 encoded image data if the clipboard is an image.
  final String? imageBase64;

  /// Human-readable source device name (e.g. "Pixel 8").
  final String deviceName;

  /// Unix epoch milliseconds. Informational only — never used for loop prevention.
  final int timestamp;

  const ClipboardShareEvent({
    required this.id,
    this.text,
    this.imageBase64,
    required this.deviceName,
    required this.timestamp,
  });
}
