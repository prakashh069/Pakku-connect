import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'dart:io' show Platform;

/// Monitors the local clipboard for text changes.
///
/// Respects Android's platform restriction: clipboard access is only permitted
/// while the app is in the foreground. This watcher uses [WidgetsBindingObserver]
/// to start the polling timer on [AppLifecycleState.resumed] and stop it on
/// any non-foreground state. This is the only correct approach on Android 10+.
class ClipboardWatcher with WidgetsBindingObserver {
  Timer? _timer;
  String? _lastClipboardContent;
  final void Function(String content) onClipboardChanged;
  bool _isRunning = false;

  ClipboardWatcher({required this.onClipboardChanged});

  /// Enables the watcher. Registers the lifecycle observer.
  /// The polling timer starts immediately if the app is already resumed.
  void start() {
    if (_isRunning) return;
    debugPrint('ClipboardWatcher started');
    _isRunning = true;
    WidgetsBinding.instance.addObserver(this);
    // Start polling immediately — app is likely already in foreground when start() is called.
    _startTimer();
  }

  /// Disables the watcher. Cancels the timer and unregisters the observer.
  void stop() {
    if (!_isRunning) return;
    _isRunning = false;
    WidgetsBinding.instance.removeObserver(this);
    _cancelTimer();
  }

  void dispose() {
    stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isRunning) return;
    switch (state) {
      case AppLifecycleState.resumed:
        debugPrint('ClipboardWatcher: app resumed, starting timer');
        _startTimer();
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (Platform.isAndroid || Platform.isIOS) {
          debugPrint('ClipboardWatcher: app backgrounded, stopping timer');
          _cancelTimer();
        } else {
          debugPrint('ClipboardWatcher: app backgrounded, keeping timer running for desktop');
        }
    }
  }

  void _startTimer() {
    if (_timer != null) return; // already running
    // Immediately check on (re)start to catch copy-then-switch-to-app pattern.
    _checkClipboard();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _checkClipboard());
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';

      if (text.isNotEmpty && text != _lastClipboardContent) {
        _lastClipboardContent = text;
        onClipboardChanged(text);
      } else if (text.isEmpty &&
          _lastClipboardContent != null &&
          _lastClipboardContent!.isNotEmpty) {
        _lastClipboardContent = text;
        onClipboardChanged(text);
      }
    } catch (e) {
      // Ignore platform exceptions (e.g., clipboard denied when backgrounded on Android).
    }
  }
}
