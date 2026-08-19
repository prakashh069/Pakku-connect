import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/message_types.dart';
import '../../../core/services/platform_transport.dart';
import '../../share/constants/share_constants.dart';
import '../../share/models/share_content.dart';
import '../../share/models/share_event.dart';
import 'clipboard_watcher.dart';

/// Maximum clipboard text payload size in UTF-16 code units (≈ 64 KB).
const int _kMaxClipboardBytes = 64000;

/// Owns all clipboard business logic:
///   - Lifecycle management (start/stop watcher)
///   - Enable/disable state persistence
///   - Deduplication (by id only — never by timestamp)
///   - UUID generation
///   - Payload construction and size enforcement
///   - Transport send (Android → macOS direction)
///   - Inbound validation + [ShareEvent] stream emission (macOS receiving direction)
///
/// Thread ownership:
///   This class runs on the main Dart isolate. Any native-side heavy work
///   (image decode, EXIF strip) is handled by the native layer via PlatformChannel.
///   Background processing happens: Dart main isolate → PlatformChannel →
///   Native thread → Background processing → Main thread.
///
/// Protocol envelope:
///   Every outbound message uses the canonical Pakku transport envelope:
///   { "schemaVersion": 1, "type": "...", "timestamp": ..., "payload": { ... } }
///
/// This class is deliberately unaware of the UI layer.
/// The [ClipboardShareCoordinator] subscribes to [inboundShares] to
/// dispatch events to the appropriate [ShareHandler].
class ClipboardSyncManager extends ChangeNotifier {
  final PlatformTransport _transport;
  late final ClipboardWatcher _watcher;
  StreamSubscription<Map<String, dynamic>>? _transportSubscription;

  final StreamController<ShareEvent> _inboundController =
      StreamController.broadcast();

  /// Stream of validated, deduplicated inbound [ShareEvent]s.
  /// Only meaningful on macOS. On Android this stream never emits.
  Stream<ShareEvent> get inboundShares => _inboundController.stream;

  bool _enabled = true;
  bool get enabled => _enabled;

  String? _lastLocalClipboardID;
  String? _lastRemoteClipboardID;
  String? _lastReceivedClipboardSignature;
  DateTime? _lastInboundTime;

  /// Device name read once at init and sent with every outbound message.
  String _deviceName = 'Android';

  ClipboardSyncManager(this._transport) {
    debugPrint('ClipboardSyncManager created');
    _watcher = ClipboardWatcher(onClipboardChanged: _onLocalClipboardChanged);
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool('clipboard_sync_enabled') ?? true;

    if (Platform.isAndroid) {
      _deviceName = await _fetchDeviceName();
    } else if (Platform.isMacOS) {
      _deviceName = 'Mac';
    }

    _transportSubscription = _transport.messages.listen(_onTransportMessage);

    if (_enabled) {
      _watcher.start();
    }
    notifyListeners();
  }

  Future<String> _fetchDeviceName() async {
    try {
      const ch = MethodChannel('com.connecto.app/platform');
      final name = await ch.invokeMethod<String>('getDeviceName');
      return name ?? 'Android';
    } catch (_) {
      return 'Android';
    }
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('clipboard_sync_enabled', value);

    if (_enabled) {
      _watcher.start();
    } else {
      _watcher.stop();
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Outbound (Android → macOS)
  // ---------------------------------------------------------------------------

  void _onLocalClipboardChanged(String text, String? imageBase64) {
    if (!_enabled) return;
    if (text.isEmpty && imageBase64 == null) return;
    
    // Global temporal deduplication to prevent echo loops when we write to our own clipboard.
    // Especially critical for images since the native layer strips the payload body before forwarding.
    if (_lastInboundTime != null && DateTime.now().difference(_lastInboundTime!) < const Duration(milliseconds: 1500)) {
      return;
    }

    // Deduplicate outbound
    final String payloadSignature;
    if (imageBase64 != null) {
      payloadSignature = 'img:${imageBase64.hashCode}';
    } else {
      final normalizedText = text.replaceAll('\r\n', '\n').trim();
      payloadSignature = 'txt:$normalizedText';
    }
    
    // Prevent echoing back what we just received over the network
    if (payloadSignature == _lastReceivedClipboardSignature) return;
    
    if (payloadSignature == _lastLocalClipboardID) return;
    _lastLocalClipboardID = payloadSignature;

    // Enforce 64 KB limit for text (measured in UTF-16 code units).
    // Truncated silently — no exception, no retry, no log of contents.
    String payloadText = text;
    if (payloadText.codeUnits.length > _kMaxClipboardBytes) {
      payloadText = String.fromCharCodes(
          payloadText.codeUnits.take(_kMaxClipboardBytes));
    }

    final id = _generateUuidV4();

    final Map<String, dynamic> contentJson;
    final String mime;

    if (imageBase64 != null) {
      // Enforce encoded payload size limit before sending.
      if (imageBase64.length > ShareLimits.maxEncodedPayloadBytes) {
        debugPrint('[ClipboardSyncManager] Image payload exceeds limit — dropped.');
        return;
      }
      mime = ShareMime.png;
      contentJson = {
        'encoding': ShareEncoding.base64,
        'body': imageBase64,
      };
    } else {
      mime = ShareMime.text;
      contentJson = {
        'encoding': ShareEncoding.utf8,
        'body': payloadText,
      };
    }


    _transport.send({
      'schemaVersion': 1,
      'type': MessageTypes.shareClipboard,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'payload': {
        'id': id,
        'mime': mime,
        'deviceName': _deviceName,
        'content': contentJson,
      },
    });
  }

  // ---------------------------------------------------------------------------
  // Inbound (macOS receiving share.clipboard)
  // ---------------------------------------------------------------------------

  void _onTransportMessage(Map<String, dynamic> data) {
    if (!_enabled) return;

    // Failure contract: malformed or unsupported messages are dropped silently.
    // Never reconnect, retry, disconnect, throw, or crash.
    try {
      final type = data['type'];
      if (type != MessageTypes.shareClipboard) return;

      final schemaVersion = data['schemaVersion'];
      // Accept only schemaVersion 1. Ignore anything < 1 or > 1.
      if (schemaVersion != 1) return;

      final payload = data['payload'];
      if (payload is! Map<String, dynamic>) return;

      final rawId = payload['id'];
      if (rawId is! String || rawId.isEmpty) return;
      final id = rawId;

      // ID-based deduplication (handles duplicate deliveries of the same message).
      if (id == _lastRemoteClipboardID) return;

      final rawMime = payload['mime'];
      if (rawMime is! String || rawMime.isEmpty) return;
      final mime = rawMime;

      final rawContent = payload['content'];
      // content might be a direct string (base64/text) or a Map.
      // The canonical ShareContent expects a Map, but if it's a direct string we construct one.
      final ShareContent content;
      if (rawContent is String) {
        content = ShareContent(
          encoding: mime.startsWith('text') ? ShareEncoding.utf8 : ShareEncoding.base64,
          body: rawContent,
        );
      } else if (rawContent is Map<String, dynamic>) {
        final parsed = ShareContent.fromJson(rawContent);
        if (parsed == null) return;
        content = parsed;
      } else {
        return;
      }
      
      final rawSize = payload['size'];
      final size = rawSize is int ? rawSize : null;

      final rawSha256 = payload['sha256'];
      final sha256 = rawSha256 is String ? rawSha256 : null;

      // Ensure image payloads have sha256
      if (mime.startsWith('image') && sha256 == null) {
        debugPrint('[ClipboardSyncManager] Dropped inbound image without SHA256.');
        return;
      }

      // Enforce encoded payload size limit on inbound.
      final body = content.body;
      if (body is String && body.length > ShareLimits.maxEncodedPayloadBytes) {
        debugPrint('[ClipboardSyncManager] Inbound payload exceeds limit — dropped.');
        return;
      }

      // Content-based deduplication (prevents echo loops when a receiving device writes to its own clipboard and broadcasts it back).
      final String payloadSignature;
      if (mime == ShareMime.text && body is String) {
        final normalizedText = body.replaceAll('\r\n', '\n').trim();
        payloadSignature = 'txt:$normalizedText';
      } else {
        payloadSignature = 'img:${body.hashCode}';
      }
          
      if (payloadSignature == _lastLocalClipboardID) return;

      _lastRemoteClipboardID = id;
      _lastReceivedClipboardSignature = payloadSignature;
      _lastInboundTime = DateTime.now();

      final rawDeviceName = payload['deviceName'];
      final deviceName = rawDeviceName is String ? rawDeviceName : 'Android';
      final rawTimestamp = data['timestamp'];
      final timestamp = rawTimestamp is int ? rawTimestamp : 0;

      _inboundController.add(ShareEvent(
        id: id,
        mime: mime,
        deviceName: deviceName,
        timestamp: timestamp,
        content: content,
        size: size,
        sha256: sha256,
      ));
    } catch (e) {
      // Per the failure contract: drop silently, never crash.
      debugPrint('[ClipboardSyncManager] Dropped malformed message: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _transportSubscription?.cancel();
    _inboundController.close();
    _watcher.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // UUID v4 generation
  // ---------------------------------------------------------------------------

  String _generateUuidV4() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40;
    values[8] = (values[8] & 0x3f) | 0x80;

    String hex(int value) => value.toRadixString(16).padLeft(2, '0');

    return '${hex(values[0])}${hex(values[1])}${hex(values[2])}${hex(values[3])}-'
        '${hex(values[4])}${hex(values[5])}-'
        '${hex(values[6])}${hex(values[7])}-'
        '${hex(values[8])}${hex(values[9])}-'
        '${hex(values[10])}${hex(values[11])}${hex(values[12])}${hex(values[13])}${hex(values[14])}${hex(values[15])}';
  }
}
