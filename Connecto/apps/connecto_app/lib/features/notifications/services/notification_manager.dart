import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/message_types.dart';
import '../../../core/services/platform_transport.dart';

/// Manages notification mirroring from Android to macOS.
///
/// Architecture:
///   WebSocketService.messages stream
///           ↓
///   NotificationManager (filters type == "sync.notification")
///           ↓
///   Deduplication (in-memory, 500ms window)
///           ↓
///   Native macOS notification display (MethodChannel → UNUserNotificationCenter)
///
/// Privacy guarantees (enforced on Android before transmission):
///   - Feature is OFF by default.
///   - Notification content is never stored, logged, or persisted.
///   - No database. No history. Data lifecycle: receive → display → discard.
///
/// This class is macOS-only. On Android it registers no subscription.
class NotificationManager extends ChangeNotifier {
  static const MethodChannel _channel =
      MethodChannel('com.connecto.app/notifications');

  final PlatformTransport _transport;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  /// In-memory deduplication store.
  /// Key: notification id ("package:notificationId") or package+title hash
  /// Value: timestamp of first receipt (ms since epoch)
  /// Entries are pruned lazily on each new notification.
  final Map<String, int> _seenIds = {};

  /// Deduplication window — 500ms.
  static const int _dedupWindowMs = 500;

  NotificationManager(this._transport) {
    if (Platform.isMacOS) {
      _channel.setMethodCallHandler(_handleMethodCall);
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription = _transport.messages
        .where((data) => 
            data['type'] == MessageTypes.syncNotification || 
            data['type'] == MessageTypes.syncNotificationRemoved)
        .listen((data) {
      if (data['type'] == MessageTypes.syncNotificationRemoved) {
        _handleNotificationRemoved(data);
      } else {
        _handleNotification(data);
      }
    }, onError: (e) {
      debugPrint('NotificationManager: stream error: $e');
    });
  }
  
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'sendReply') {
      final String? replyHandle = call.arguments['replyHandle'] as String?;
      final String? text = call.arguments['text'] as String?;
      
      if (replyHandle != null && text != null) {
        _transport.send({
          'type': 'action.notification_reply',
          'replyHandle': replyHandle,
          'text': text,
        });
      }
    }
  }

  /// Maps a base notification ID (sbn.key) to a list of macOS specific identifiers.
  /// Used to remove all related macOS notifications when the parent is dismissed on Android.
  final Map<String, List<String>> _activeMacOsIds = {};

  void _handleNotificationRemoved(Map<String, dynamic> data) {
    try {
      final id = data['id'] as String?;
      if (id != null) {
        final List<String>? macOsIds = _activeMacOsIds.remove(id);
        if (macOsIds != null && macOsIds.isNotEmpty) {
          for (var macOsId in macOsIds) {
            _channel.invokeMethod('removeNotification', {'id': macOsId});
          }
        } else {
          // Fallback just in case
          _channel.invokeMethod('removeNotification', {'id': id});
        }
      }
    } catch (e) {
      debugPrint('NotificationManager: Error removing notification: $e');
    }
  }

  void _handleNotification(Map<String, dynamic> data) {
    try {
      final id = data['id'] as String?;
      final app = data['app'] as String?;
      final package = data['package'] as String?;
      final title = data['title'] as String?;
      final body = data['body'] as String?;
      final timestamp = data['timestamp'] as int?;
      final bool canReply = data['canReply'] as bool? ?? false;
      final String? replyHandle = data['replyHandle'] as String?;

      // Validate required fields
      if (id == null || app == null || package == null || title == null || body == null || timestamp == null) {
        debugPrint('NotificationManager: Dropping notification with missing fields.');
        return;
      }

      // Make the macOS identifier strictly unique to the timestamp and body so we don't overwrite previous messages in the same chat
      // but we ALSO want to ensure we don't bounce the EXACT SAME message twice.
      final String macOsId = "$id:$timestamp:${body.hashCode}";

      // If we are already displaying this exact message, ignore it to prevent macOS from dropping the banner again (bouncing).
      final activeList = _activeMacOsIds[id];
      if (activeList != null && activeList.contains(macOsId)) {
        debugPrint('NotificationManager: Exact duplicate suppressed to prevent bouncing (macOsId=$macOsId).');
        return;
      }

      // Track it so we can remove it when the parent 'id' is dismissed on Android
      _activeMacOsIds.putIfAbsent(id, () => []).add(macOsId);

      // Dispatch to native macOS notification center
      _showNativeNotification(
        id: macOsId,
        app: app, 
        title: title, 
        body: body,
        canReply: canReply,
        replyHandle: replyHandle,
      );
    } catch (e) {
      debugPrint('NotificationManager: Error handling notification: $e');
    }
  }

  Future<void> _showNativeNotification({
    required String id,
    required String app,
    required String title,
    required String body,
    required bool canReply,
    String? replyHandle,
  }) async {
    if (!Platform.isMacOS) return;

    try {
      await _channel.invokeMethod<void>('showNotification', {
        'id': id,
        'app': app,
        'title': title,
        'body': body,
        'canReply': canReply,
        'replyHandle': replyHandle,
      });
    } on PlatformException catch (e) {
      // Graceful fallback — log and continue. Do not crash or retry.
      debugPrint(
          'NotificationManager: Failed to show native notification: ${e.code} ${e.message}');
    } catch (e) {
      debugPrint('NotificationManager: Unexpected error showing notification: $e');
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _seenIds.clear();
    super.dispose();
  }
}
