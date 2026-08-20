import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/constants/message_types.dart';
import '../../../core/models/recent_call.dart';
import '../../../core/interfaces/device_transport.dart';

class RecentCallsManager extends ChangeNotifier {
  final DeviceTransport _webSocketService;
  late StreamSubscription _messageSub;

  List<RecentCall> _calls = [];
  List<RecentCall> get calls => List.unmodifiable(_calls);

  RecentCallsManager(this._webSocketService) {
    _messageSub = _webSocketService.messages.listen(_onMessage);
  }

  void requestCallHistory() {
    _webSocketService.send({
      'type': MessageTypes.requestCallHistory,
    });
  }

  void _onMessage(Map<String, dynamic> data) {
    if (data['type'] == MessageTypes.deviceState && data['state'] == 'connected') {
      requestCallHistory();
    } else if (data['type'] == MessageTypes.syncCallHistory) {
      final schemaVersion = data['schemaVersion'];
      if (schemaVersion != 1) {
        return; // Ignore unsupported schema versions
      }

      final payload = data['payload'] as Map<String, dynamic>?;
      if (payload == null) return;

      final callsData = payload['calls'] as List?;
      if (callsData == null) return;

      final parsedCalls = <RecentCall>[];
      final seenIds = <String>{};

      for (var element in callsData) {
        if (element is Map<String, dynamic>) {
          try {
            final call = RecentCall.fromJson(element);
            // Remove duplicates by id
            if (call.id.isNotEmpty && !seenIds.contains(call.id)) {
              seenIds.add(call.id);
              parsedCalls.add(call);
            }
          } catch (e) {
            // Ignore malformed individual entries
            debugPrint('Failed to parse recent call: $e');
          }
        }
      }

      // Sort newest first
      parsedCalls.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Replace list atomically and notify ONLY if changed
      if (!_areListsEqual(_calls, parsedCalls)) {
        _calls = parsedCalls;
        notifyListeners();
      }
    }
  }

  bool _areListsEqual(List<RecentCall> list1, List<RecentCall> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i].id != list2[i].id) return false;
      if (list1[i].type != list2[i].type) return false;
      if (list1[i].duration != list2[i].duration) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _messageSub.cancel();
    super.dispose();
  }
}
