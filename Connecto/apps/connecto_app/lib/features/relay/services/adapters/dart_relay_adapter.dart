import 'package:connecto/features/relay/services/relay_adapter.dart';
import 'package:connecto/features/relay/services/relay_server.dart';

class DartRelayAdapter implements RelayAdapter {
  RelayServer? _server;
  void Function(Object error)? _onError;
  String? _pendingSecret;

  @override
  Future<void> start({
    required int port,
    required String certPath,
    required String keyPath,
  }) async {
    if (_server != null) return;
    _server = RelayServer();
    if (_pendingSecret != null) {
      _server!.setSecret(_pendingSecret!);
    }
    _server!.onError = _onError;
    await _server!.start(
      port: port,
      certPath: certPath,
      keyPath: keyPath,
    );
  }

  @override
  void setSecret(String secret) {
    _pendingSecret = secret;
    _server?.setSecret(secret);
  }

  @override
  void setOnError(void Function(Object error)? handler) {
    _onError = handler;
    _server?.onError = handler;
  }

  @override
  Future<void> stop() async {
    await _server?.stop();
    _server = null;
  }
}
