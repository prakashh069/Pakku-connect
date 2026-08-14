import 'package:flutter/foundation.dart';
import '../models/device_telemetry.dart';

class TelemetryService extends ChangeNotifier {
  DeviceTelemetry? _currentTelemetry;

  DeviceTelemetry? get currentTelemetry => _currentTelemetry;

  void updateTelemetry(DeviceTelemetry telemetry) {
    _currentTelemetry = telemetry;
    notifyListeners();
  }
}

// Global instance for easy access, similar to other services in the app
final telemetryService = TelemetryService();
