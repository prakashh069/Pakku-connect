import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../core/constants/message_types.dart';
import '../../core/services/websocket_service.dart';

class NotificationManager extends ChangeNotifier {
  final WebSocketService _wsService;
  late StreamSubscription _messageSubscription;
  static const MethodChannel _channel = MethodChannel('com.connecto.app/notifications');

  // In-memory deduplication cache
  final Map<int, DateTime> _recentNotifications = {};
  static const Duration _dedupWindow = Duration(milliseconds: 500);

  NotificationManager(this._wsService) {
    _init();
  }

  void _init() {
    _messageSubscription = _wsService.messages.listen((message) {
      if (message['type'] == MessageTypes.syncNotification) {
        _handleNotificationMessage(message);
      }
    });
  }

  Future<void> _handleNotificationMessage(Map<String, dynamic> message) async {
    try {
      final String package = message['package'] as String? ?? 'unknown';
      final String title = message['title'] as String? ?? '';
      final String body = message['body'] as String? ?? '';
      final int timestamp = message['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;

      if (title.isEmpty && body.isEmpty) return;

      // Hash combination of package + title + body + timestamp for dedup
      final int hash = Object.hash(package, title, body, timestamp);
      final now = DateTime.now();

      // Clean up old entries
      _recentNotifications.removeWhere((_, time) => now.difference(time) > _dedupWindow);

      if (_recentNotifications.containsKey(hash)) {
        debugPrint('NotificationManager: Duplicate notification dropped');
        return;
      }

      _recentNotifications[hash] = now;

      // Forward to macOS native layer
      await _channel.invokeMethod('showNotification', {
        'title': title,
        'body': body,
      });

    } catch (e) {
      debugPrint('NotificationManager: Error processing sync.notification - $e');
    }
  }

  @override
  void dispose() {
    _messageSubscription.cancel();
    super.dispose();
  }
}
