import 'dart:io';
import 'package:flutter/material.dart';
import '../../features/auth/screens/qr_pairing_screen.dart';
import '../../features/auth/screens/scan_screen.dart';

/// Coordinator widget that handles platform-specific pairing screens.
/// Extracts OS-level decisions from the navigation layer.
class DevicePairingCoordinator extends StatelessWidget {
  const DevicePairingCoordinator({super.key});

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS) {
      return const QrPairingScreen();
    }
    return const ScanScreen();
  }
}
