/// Shared MIME type constants for the Pakku Share Framework.
///
/// Handlers and senders must reference these constants rather than
/// raw strings to prevent typos and centralise future additions.
class ShareMime {
  const ShareMime._();

  static const String text     = 'text/plain';
  static const String png      = 'image/png';
  static const String jpeg     = 'image/jpeg';
  static const String webp     = 'image/webp';

  // Future types — document here before implementing a handler.
  // static const String html  = 'text/html';
  // static const String uriList = 'text/uri-list';
  // static const String pdf   = 'application/pdf';
  // static const String heic  = 'image/heic';
}

/// Shared encoding constants for [ShareContent.encoding].
///
/// The encoding field defines how [ShareContent.body] is interpreted.
/// New encodings may be introduced in future schema versions without
/// changing the surrounding message envelope:
///   - 'utf-8'  → body is a [String]
///   - 'base64' → body is a base-64 [String] representing binary data
///   - 'binary' → (future) body is a [Uint8List]
class ShareEncoding {
  const ShareEncoding._();

  static const String utf8   = 'utf-8';
  static const String base64 = 'base64';
}

/// Shared transport limit constants.
///
/// A single source of truth. Changing [maxEncodedPayloadBytes] here
/// automatically propagates to all callers.
class ShareLimits {
  const ShareLimits._();

  /// Maximum size of the **encoded payload** (e.g., the Base64 string
  /// inside [ShareContent.body]) in bytes. Both sender and receiver
  /// must enforce this limit independently.
  static const int maxEncodedPayloadBytes = 5 * 1024 * 1024; // 5 MB
}
