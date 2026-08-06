import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/message_types.dart';
import '../../../core/services/platform_transport.dart';
import '../models/clipboard_share_event.dart';
import 'clipboard_watcher.dart';

/// Maximum clipboard payload size in UTF-16 code units (≈ 64 KB).
const int _kMaxClipboardBytes = 64000;

/// Owns all clipboard business logic:
///   - Lifecycle management (start/stop watcher)
///   - Enable/disable state persistence
///   - Deduplication
///   - UUID generation
///   - Payload construction and 64 KB enforcement
///   - Transport send (Android → macOS direction)
///   - Inbound validation + stream emission (macOS receiving direction)
///
/// This class is deliberately unaware of the UI layer.
/// The [ClipboardShareCoordinator] subscribes to [inboundShares] to handle
/// popup presentation on macOS.
class ClipboardSyncManager extends ChangeNotifier {
  final PlatformTransport _transport;
  late final ClipboardWatcher _watcher;
  StreamSubscription<Map<String, dynamic>>? _transportSubscription;

  final StreamController<ClipboardShareEvent> _inboundController =
      StreamController.broadcast();

  /// Stream of validated, deduplicated inbound clipboard share events.
  /// Only meaningful on macOS. On Android this stream never emits.
  Stream<ClipboardShareEvent> get inboundShares => _inboundController.stream;

  bool _enabled = true;
  bool get enabled => _enabled;

  String? _lastLocalClipboardID;
  String? _lastRemoteClipboardID;

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
    _lastReceivedText = prefs.getString('lastReceivedClipboardText');

    if (Platform.isAndroid) {
      _deviceName = await _fetchDeviceName();
    } else if (Platform.isMacOS) {
      _deviceName = 'Mac';
    }

    if (_enabled) {
      _watcher.start();
    }

    _transportSubscription = _transport.messages.listen(_onTransportMessage);
    notifyListeners();
  }

  Future<String> _fetchDeviceName() async {
    try {
      const ch = MethodChannel('com.pakku.connect/platform');
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

  String? _lastReceivedText;

  // ---------------------------------------------------------------------------
  // Outbound (Android → macOS)
  // ---------------------------------------------------------------------------

  void _onLocalClipboardChanged(String content) {
    if (!_enabled) return;
    if (content.isEmpty) return;
    if (content == _lastReceivedText) return;

    // Enforce 64 KB limit measured in UTF-16 code units.
    // Truncated silently — no exception, no retry, no log of contents.
    String payload = content;
    if (payload.codeUnits.length > _kMaxClipboardBytes) {
      payload = String.fromCharCodes(payload.codeUnits.take(_kMaxClipboardBytes));
    }

    _lastLocalClipboardID = _generateUuidV4();

    _transport.send({
      'schemaVersion': 1,
      'type': MessageTypes.shareClipboard,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'payload': {
        'id': _lastLocalClipboardID,
        'mime': 'text/plain',
        'text': payload,
        'deviceName': _deviceName,
      },
    });
  }

  // ---------------------------------------------------------------------------
  // Inbound (macOS receiving share.clipboard)
  // ---------------------------------------------------------------------------

  void _onTransportMessage(Map<String, dynamic> data) {
    if (!_enabled) return;

    final type = data['type'];
    if (type != MessageTypes.shareClipboard) return;

    final schemaVersion = data['schemaVersion'];
    if (schemaVersion != 1) return; // safely ignore unsupported schema versions

    final payload = data['payload'];
    if (payload is! Map<String, dynamic>) return; // malformed payload

    final id = payload['id'] as String?;
    final text = payload['text'] as String?;
    
    if (text != null && text.isNotEmpty) {
      _lastReceivedText = text;
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('lastReceivedClipboardText', text);
      });
    }
    
    final deviceName = payload['deviceName'] as String? ?? 'Android';

    if (id == null || text == null || text.isEmpty) return;

    // Deduplication — ignore events we already processed.
    if (id == _lastRemoteClipboardID || id == _lastLocalClipboardID) return;
    _lastRemoteClipboardID = id;

    final timestamp = data['timestamp'] as int? ?? 0;

    _inboundController.add(ClipboardShareEvent(
      id: id,
      text: text, // full, untruncated
      deviceName: deviceName,
      timestamp: timestamp,
    ));
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
