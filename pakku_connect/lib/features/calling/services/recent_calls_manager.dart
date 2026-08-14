import 'package:flutter/foundation.dart';
import '../../../core/models/recent_call.dart';

import '../../../core/constants/message_types.dart';
import '../../../core/services/websocket_service.dart';

class RecentCallsManager extends ChangeNotifier {
  final WebSocketService _wsService;
  final List<RecentCall> _calls = [];
  bool _permissionDenied = false;

  RecentCallsManager(this._wsService) {
    _wsService.messages.listen(_onMessage);
  }

  void requestCallHistory() {
    _wsService.send({'type': MessageTypes.requestCallHistory});
  }

  void _onMessage(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == MessageTypes.syncCallHistory) {
      final payload = data['payload'] as Map<String, dynamic>?;
      if (payload != null && payload['calls'] is List) {
        handleSyncCallHistory(payload['calls'] as List);
      } else if (data['calls'] is List) {
        // Fallback if the payload is directly in the event
        handleSyncCallHistory(data['calls'] as List);
      }
    } else if (type == MessageTypes.callHistoryPermissionDenied) {
      handlePermissionDenied();
    }
  }

  List<RecentCall> get calls => List.unmodifiable(_calls);
  bool get isPermissionDenied => _permissionDenied;

  void handleSyncCallHistory(List<dynamic> historyPayload) {
    _calls.clear();
    for (var item in historyPayload) {
      if (item is Map<String, dynamic>) {
        final name = item['name'] as String?;
        _calls.add(RecentCall(
          id: DateTime.now().microsecondsSinceEpoch.toString(), // ephemeral ID
          name: name?.isNotEmpty == true ? name! : 'Unknown caller',
          number: '', // Obfuscated per Phase 5.5 rules
          type: item['type'] as String? ?? 'unknown',
          timestamp: item['timestamp'] as int? ?? 0,
          duration: item['duration'] as int? ?? 0,
        ));
      }
    }
    _permissionDenied = false;
    notifyListeners();
  }

  void handlePermissionDenied() {
    _calls.clear();
    _permissionDenied = true;
    notifyListeners();
  }
}
