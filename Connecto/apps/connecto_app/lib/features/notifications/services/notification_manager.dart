import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/message_types.dart';
import '../../../core/messaging/message_bus.dart';
import '../../../core/messaging/message_types.dart';

/// Manages notification mirroring from Android to macOS.
///
/// Architecture:
///   AppMessageBus messages stream
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

  final MessageBus? _messageBus;
  StreamSubscription? _subscription;

  /// In-memory deduplication store.
  /// Key: notification id ("package:notificationId") or package+title hash
  /// Value: timestamp of first receipt (ms since epoch)
  /// Entries are pruned lazily on each new notification.
  final Map<String, int> _seenIds = {};

  /// Deduplication window — 500ms.
  static const int _dedupWindowMs = 500;

  NotificationManager(this._messageBus) {
    if (Platform.isMacOS) {
      _channel.setMethodCallHandler(_handleMethodCall);
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription = _messageBus?.messagesOfType(BusMessagePrefixes.notification)
        .listen((busMsg) {
      final data = busMsg.raw;
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
        _messageBus?.send({
          'type': 'action.notification_reply',
          'replyHandle': replyHandle,
          'text': text,
        });
      }
    }
  }

  final Map<String, int> _lastBodyHashes = {};

  void _handleNotificationRemoved(Map<String, dynamic> data) {
    try {
      final id = data['id'] as String?;
      if (id != null) {
        _lastBodyHashes.remove(id);
        _channel.invokeMethod('removeNotification', {'id': id});
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

      final String macOsId = id;
      final int bodyHash = body.hashCode;

      if (_lastBodyHashes[id] == bodyHash) {
        debugPrint('NotificationManager: Exact duplicate suppressed to prevent bouncing (macOsId=$macOsId).');
        return;
      }

      _lastBodyHashes[id] = bodyHash;

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
