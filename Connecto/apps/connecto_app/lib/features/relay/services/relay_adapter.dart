abstract class RelayAdapter {
  Future<void> start({
    required int port,
    required String certPath,
    required String keyPath,
  });

  void setSecret(String secret);

  void setOnError(void Function(Object error)? handler);

  Future<void> stop();
}
