import 'dart:async';
import 'package:flutter/foundation.dart';

enum RelayStatus { stopped, running, reconnecting, failed }

abstract class RelayService {
  ValueNotifier<RelayStatus> get status;
  Future<void> start({
    required int port,
    required String certPath,
    required String keyPath,
  });
  void setSecret(String secret);
  void stop();
}
