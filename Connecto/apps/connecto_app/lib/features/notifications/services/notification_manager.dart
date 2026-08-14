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
///   NotificationManager (filters type == "notification")
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
  /// Key: notification id ("package:notificationId")
  /// Value: timestamp of first receipt (ms since epoch)
  /// Entries are pruned lazily on each new notification.
  final Map<String, int> _seenIds = {};

  /// Deduplication window — 500ms.
  static const int _dedupWindowMs = 500;

  NotificationManager(this._transport) {
    if (Platform.isMacOS) {
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription = _transport.messages
        .where((data) => data['type'] == MessageTypes.notification)
        .listen(_handleNotification, onError: (e) {
      debugPrint('NotificationManager: stream error: $e');
    });
  }

  void _handleNotification(Map<String, dynamic> data) {
    try {
      final id = data['id'] as String?;
      final app = data['app'] as String?;
      final title = data['title'] as String?;
      final body = data['body'] as String?;

      // Validate required fields
      if (id == null || id.isEmpty) {
        debugPrint('NotificationManager: Dropping notification with missing id.');
        return;
      }
      if (app == null || title == null || body == null) {
        debugPrint('NotificationManager: Dropping notification with missing fields.');
        return;
      }

      // Deduplication — prune stale entries and check
      final now = DateTime.now().millisecondsSinceEpoch;
      _seenIds.removeWhere((_, ts) => (now - ts) > _dedupWindowMs);

      if (_seenIds.containsKey(id)) {
        debugPrint('NotificationManager: Duplicate suppressed (id=$id).');
        return;
      }
      _seenIds[id] = now;

      // Dispatch to native macOS notification center
      _showNativeNotification(app: app, title: title, body: body);
    } catch (e) {
      debugPrint('NotificationManager: Error handling notification: $e');
    }
  }

  Future<void> _showNativeNotification({
    required String app,
    required String title,
    required String body,
  }) async {
    try {
      await _channel.invokeMethod<void>('showNotification', {
        'app': app,
        'title': title,
        'body': body,
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
