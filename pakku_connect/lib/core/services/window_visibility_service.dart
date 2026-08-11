import 'dart:io';
import 'package:flutter/services.dart';

class WindowVisibilityService {
  bool _isVisible = true;
  final MethodChannel _channel = const MethodChannel('com.pakku.connect/menuBar');
  final List<void Function()> _listeners = [];

  bool get isVisible => _isVisible;

  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  Future<void> init() async {
    if (Platform.isMacOS) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'windowVisibilityChanged') {
          final isVisible = call.arguments['isVisible'] as bool? ?? false;
          _updateVisibility(isVisible);
        }
      });
      
      try {
        final isVisible = await _channel.invokeMethod<bool>('checkWindowVisibility');
        _updateVisibility(isVisible ?? true);
      } catch (e) {
        // Fallback
      }
    }
  }

  void _updateVisibility(bool visible) {
    if (_isVisible != visible) {
      _isVisible = visible;
      for (var listener in _listeners) {
        listener();
      }
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _listeners.clear();
  }
}
