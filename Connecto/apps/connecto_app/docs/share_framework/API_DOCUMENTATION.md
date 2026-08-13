# Pakku Share Framework - API & Developer Documentation

The Pakku Share Framework is a generic, MIME-driven architecture designed to share arbitrary content across paired devices. While initially built for Clipboard Sync (Text and Images), the framework is highly extensible and can support files, links, contacts, or any other MIME-type in the future.

## 1. Architectural Core Principles
1. **Generic Protocol:** Data is transported inside a versioned, self-describing canonical envelope.
2. **Immutable Handlers:** The `ShareHandlerRegistry` is immutable after startup. Handlers read payloads but never mutate them.
3. **Silent Failure Contract:** Malformed data, unsupported MIMEs, and size violations are dropped silently. The system never crashes or disconnects the WebSocket due to a bad payload.
4. **ID-Based Deduplication:** Deduplication is strictly managed via UUIDv4 IDs, never by timestamp or payload content.

---

## 2. The Canonical Envelope

All Share Framework messages transmitted over the WebSocket must adhere to the following JSON schema:

```json
{
  "schemaVersion": 1,
  "type": "share.clipboard",
  "timestamp": 1724000000000,
  "payload": {
    "id": "e8a3a0e1-...",
    "mime": "image/png",
    "deviceName": "Pixel 7",
    "content": {
      "encoding": "base64",
      "body": "iVBORw0KGgo...",
      "metadata": {
        "width": 1920,
        "height": 1080,
        "sizeBytes": 145000
      }
    }
  }
}
```

### Fields Breakdown
- `schemaVersion` (int, required): Must be `1`. Reject any other version.
- `type` (string, required): Determines routing at the WebSocket layer. Currently `"share.clipboard"`.
- `timestamp` (int, required): Milliseconds since epoch.
- `payload` (object, required): The actual share data.
  - `id` (string, required): A UUIDv4 string. Used for deduplication.
  - `mime` (string, required): E.g., `"text/plain"`, `"image/jpeg"`. Drives handler routing.
  - `deviceName` (string, optional): Used for UI displays (e.g., "Copied from Pixel 7").
  - `content` (object, required):
    - `encoding` (string, required): Usually `"utf-8"` or `"base64"`.
    - `body` (string, required): The actual data. Must not exceed 5MB when encoded.
    - `metadata` (object, optional): Flexible dictionary for extra info (dimensions, filenames).

---

## 3. Extending the Framework (Adding a New Handler)

The system routes payloads based on the `mime` type using the `ShareHandlerRegistry`. To support a new content type (e.g., URLs or PDFs), follow these steps:

### Step 1: Define the MIME Constant
In `lib/features/share/constants/share_constants.dart`:
```dart
class ShareMime {
  static const String pdf = 'application/pdf';
}
```

### Step 2: Create a ShareHandler
Implement the `ShareHandler` abstract class:
```dart
class PdfHandler implements ShareHandler {
  @override
  bool supports(String mime) {
    return mime.toLowerCase() == ShareMime.pdf;
  }

  @override
  Future<void> handle(ShareEvent event) async {
    // 1. Validate encoding (e.g., base64)
    // 2. Decode body
    // 3. Dispatch to native UI via MethodChannel or handle in Dart
  }
}
```

### Step 3: Register the Handler
In `ShareHandlerRegistry.withDefaults()`, add your new handler:
```dart
factory ShareHandlerRegistry.withDefaults() {
  return ShareHandlerRegistry([
    TextHandler(),
    ImageHandler(),
    PdfHandler(), // <-- Your new handler
  ]);
}
```

---

## 4. Native Layer Contracts

### Android Background Processing
When generating an image payload on Android (e.g., via the system Share sheet):
- Processing must occur on a background thread.
- `BitmapFactory.decodeFile()` is used to ensure EXIF data is stripped.
- A **Binary Search compression** algorithm targets a JPEG quality that guarantees the Base64 encoded payload is ≤ 5MB (max 7 iterations).
- Temporary files in `cacheDir/pakku_share/` must be explicitly deleted via `.delete()` immediately after encoding or decoding is finished.

### macOS Memory Management
When receiving an image payload on macOS:
- Decoding the Base64 string to `Data` occurs on a global background queue (`DispatchQueue.global(qos: .userInitiated)`).
- The decoded memory (`decodedData`) is retained by the popup controller for display.
- **Contract:** You MUST release this memory (`decodedData = nil`) immediately when the popup is dismissed or when a new share event replaces the current one.
