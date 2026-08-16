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
  final void Function(String text, String? imageBase64) onClipboardChanged;
  bool _isRunning = false;

  ClipboardWatcher({required this.onClipboardChanged});

  /// Enables the watcher. Registers the lifecycle observer.
  /// The polling timer starts immediately if the app is already resumed.
  void start() {
    if (_isRunning) return;
    debugPrint('ClipboardWatcher started');
    _isRunning = true;
    
    if (Platform.isMacOS) {
      const channel = MethodChannel('com.connecto.app/macClipboard');
      channel.setMethodCallHandler((call) async {
        if (call.method == 'clipboardTextChanged') {
          final text = call.arguments as String?;
          if (text != null) {
            onClipboardChanged(text, null);
          }
        } else if (call.method == 'clipboardImageChanged') {
          final base64 = call.arguments as String?;
          if (base64 != null) {
            onClipboardChanged('', base64);
          }
        }
      });
      channel.invokeMethod('startWatching');
    } else {
      WidgetsBinding.instance.addObserver(this);
      _startTimer();
    }
  }

  /// Disables the watcher. Cancels the timer and unregisters the observer.
  void stop() {
    if (!_isRunning) return;
    _isRunning = false;
    
    if (Platform.isMacOS) {
      const channel = MethodChannel('com.connecto.app/macClipboard');
      channel.invokeMethod('stopWatching');
      channel.setMethodCallHandler(null);
    } else {
      WidgetsBinding.instance.removeObserver(this);
      _cancelTimer();
    }
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
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _checkClipboard());
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _checkClipboard() async {
    try {
      String text = '';
      bool isRemote = false;

      if (Platform.isAndroid) {
        const channel = MethodChannel('com.connecto.app/platform');
        final result = await channel.invokeMethod<Map<Object?, Object?>>('getClipboardData');
        if (result != null) {
          text = (result['text'] as String?) ?? '';
          isRemote = (result['isRemote'] as bool?) ?? false;
        }
      } else {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        text = data?.text ?? '';
      }

      if (text.isNotEmpty && text != _lastClipboardContent) {
        _lastClipboardContent = text;
        if (!isRemote) {
          onClipboardChanged(text, null);
        } else {
          debugPrint('ClipboardWatcher: Ignored remote clipboard update based on label');
        }
      } else if (text.isEmpty &&
          _lastClipboardContent != null &&
          _lastClipboardContent!.isNotEmpty) {
        _lastClipboardContent = text;
        if (!isRemote) {
          onClipboardChanged(text, null);
        }
      }
    } catch (e) {
      // Ignore platform exceptions (e.g., clipboard denied when backgrounded on Android).
    }
  }
}
