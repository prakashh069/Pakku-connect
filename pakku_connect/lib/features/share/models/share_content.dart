import '../constants/share_constants.dart';

/// The content envelope for a [ShareEvent].
///
/// [encoding] declares how [body] must be interpreted:
///   - [ShareEncoding.utf8]   → body is a [String]
///   - [ShareEncoding.base64] → body is a base-64 [String]
///   - future 'binary'        → body will be a [Uint8List]
///
/// [metadata] is optional, advisory, and MIME-specific.
/// Receivers must treat it as a UI hint only — never as input
/// required for correctness. If metadata is absent or contains
/// unknown keys, the share must still work.
///
/// MIME-specific metadata keys:
///   image/*          → width, height, sizeBytes, displayName?
///   application/pdf  → pages, displayName?
///   text/plain       → language?
///
/// Payloads are immutable. Share handlers may read [body] and
/// [metadata] but must never mutate them.
class ShareContent {
  /// Declares how [body] is encoded. Use [ShareEncoding] constants.
  final String encoding;

  /// The actual content. Type depends on [encoding]:
  ///   utf-8  → [String]
  ///   base64 → [String] (base-64 encoded binary)
  ///   binary → [Uint8List] (future)
  final dynamic body;

  /// Optional, advisory, MIME-specific metadata for UI presentation.
  /// Handlers must never require this to be present for correctness.
  final Map<String, dynamic>? metadata;

  const ShareContent({
    required this.encoding,
    required this.body,
    this.metadata,
  });

  /// Constructs a [ShareContent] from a JSON map.
  /// Returns null if the map is malformed.
  static ShareContent? fromJson(Map<String, dynamic> json) {
    final encoding = json['encoding'] as String?;
    final body     = json['body'];
    if (encoding == null || body == null) return null;

    final rawMeta = json['metadata'];
    final metadata = (rawMeta is Map)
        ? Map<String, dynamic>.from(rawMeta)
        : null;

    return ShareContent(
      encoding: encoding,
      body: body,
      metadata: metadata,
    );
  }

  Map<String, dynamic> toJson() => {
    'encoding': encoding,
    'body': body,
    if (metadata != null) 'metadata': metadata,
  };
}
