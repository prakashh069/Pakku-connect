import 'dart:async';
import 'package:flutter/foundation.dart';
import '../interfaces/device_transport.dart';
import '../interfaces/native_platform_bridge.dart';
import 'bus_message.dart';
import 'message_bus.dart';

class AppMessageBus implements MessageBus {
  final DeviceTransport? _deviceTransport;
  final NativePlatformBridge? _nativeBridge;
  final StreamController<BusMessage> _messageController = StreamController.broadcast();
  
  final List<StreamSubscription> _subscriptions = [];
  
  // Deduplication cache
  final int _maxCacheSize;
  final Duration _dedupTtl;
  final Map<String, DateTime> _recentMessages = {};

  AppMessageBus({
    DeviceTransport? deviceTransport,
    NativePlatformBridge? nativeBridge,
    int maxCacheSize = 100,
    Duration dedupTtl = const Duration(seconds: 5),
  })  : _deviceTransport = deviceTransport,
        _nativeBridge = nativeBridge,
        _maxCacheSize = maxCacheSize,
        _dedupTtl = dedupTtl {
    
    if (_deviceTransport != null) {
      _subscriptions.add(_deviceTransport!.messages.listen(_onRawMessage));
    }
    
    if (_nativeBridge != null) {
      _subscriptions.add(_nativeBridge!.messages.listen(_onRawMessage));
    }
  }

  void _onRawMessage(Map<String, dynamic> rawMsg) {
    try {
      final msg = BusMessage.fromJson(rawMsg);
      
      if (msg.category == MessageCategory.transferProtocol) {
        _messageController.add(msg);
        return;
      }
      
      // Deduplication check for event/command messages
      final dedupId = msg.deduplicationId;
      final now = DateTime.now();
      
      // Clean up stale entries periodically
      if (_recentMessages.length >= _maxCacheSize) {
        _recentMessages.removeWhere((key, time) => now.difference(time) > _dedupTtl);
      }
      
      if (_recentMessages.containsKey(dedupId)) {
        if (now.difference(_recentMessages[dedupId]!) <= _dedupTtl) {
          // Suppress duplicate
          return;
        }
      }
      
      // Ensure cache size is strictly maintained
      if (_recentMessages.length >= _maxCacheSize) {
        final oldestKey = _recentMessages.entries.reduce((a, b) => a.value.isBefore(b.value) ? a : b).key;
        _recentMessages.remove(oldestKey);
      }
      
      _recentMessages[dedupId] = now;
      _messageController.add(msg);
      
    } catch (e, st) {
      debugPrint('[AppMessageBus] Error processing incoming message: $e\n$st');
    }
  }

  @override
  Stream<BusMessage> messagesOfType(String typePrefix) {
    return _messageController.stream.where((msg) => msg.type.startsWith(typePrefix));
  }

  @override
  void send(Map<String, dynamic> message, {MessageRoute route = MessageRoute.networkOnly}) {
    if (route == MessageRoute.networkOnly || route == MessageRoute.broadcast) {
      try {
        _deviceTransport?.send(message);
      } catch (e) {
        debugPrint('[AppMessageBus] Network transport send failed: $e');
      }
    }
    
    if (route == MessageRoute.nativeOnly || route == MessageRoute.broadcast) {
      try {
        _nativeBridge?.send(message);
      } catch (e) {
        debugPrint('[AppMessageBus] Native bridge send failed: $e');
      }
    }
  }

  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _messageController.close();
  }
}
