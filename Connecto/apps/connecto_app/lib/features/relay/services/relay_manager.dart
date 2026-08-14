import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connecto/features/relay/services/relay_adapter.dart';
import 'package:connecto/features/relay/services/adapters/dart_relay_adapter.dart';

enum RelayStatus { stopped, running, reconnecting, failed }

class RelayManager {
  
  late final RelayAdapter _adapter;
  final ValueNotifier<RelayStatus> status = ValueNotifier(RelayStatus.stopped);
  
  Timer? _retryTimer;
  int _retryCount = 0;
  static const int _maxRetries = 10;
  bool _intentionalStop = false;
  
  int? _port;
  String? _certPath;
  String? _keyPath;

  RelayManager() {
    _adapter = DartRelayAdapter();
    _adapter.setOnError((e) {
      _handleAdapterError(e);
    });
  }

  Future<void> start({
    required int port,
    required String certPath,
    required String keyPath,
  }) async {
    _intentionalStop = false;
    _port = port;
    _certPath = certPath;
    _keyPath = keyPath;
    _retryCount = 0;
    
    await _startInternal();
  }

  Future<void> _startInternal() async {
    if (_intentionalStop || _port == null || _certPath == null || _keyPath == null) return;
    
    if (_retryCount > 0) {
      status.value = RelayStatus.reconnecting;
    }
    
    try {
      await _adapter.start(port: _port!, certPath: _certPath!, keyPath: _keyPath!);
      status.value = RelayStatus.running;
      _retryCount = 0; // Reset on success
    } catch (e) {
      print('RelayManager: Failed to start: $e');
      _handleAdapterError(e);
    }
  }

  void _handleAdapterError(Object error) {
    if (_intentionalStop) return;
    
    if (_retryCount >= _maxRetries) {
      print('RelayManager: Max retries reached. Relay is failed.');
      status.value = RelayStatus.failed;
      return;
    }
    
    status.value = RelayStatus.reconnecting;
    _retryCount++;
    
    // Exponential backoff: 2, 4, 8, 16, 32, 60 (max 60 seconds)
    int seconds = (1 << _retryCount);
    if (seconds > 60) seconds = 60;
    
    final backoff = Duration(seconds: seconds);
    print('RelayManager: Attempt $_retryCount failed. Retrying in ${backoff.inSeconds}s...');
    
    _retryTimer?.cancel();
    _retryTimer = Timer(backoff, () async {
      await _adapter.stop();
      _startInternal();
    });
  }

  void setSecret(String secret) {
    _adapter.setSecret(secret);
  }

  Future<void> stop() async {
    _intentionalStop = true;
    _retryTimer?.cancel();
    await _adapter.stop();
    status.value = RelayStatus.stopped;
  }
}
