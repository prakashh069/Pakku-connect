import 'dart:convert';
import 'dart:io';

import '../models/relay_client.dart';
import '../models/relay_config.dart';

class RelayRouter {
  /// Routes a raw string message from [sender] to all authenticated [clients]
  /// except the sender itself. Enforces directionality rules.
  void routeMessage(String rawMessage, Map<String, dynamic> data, RelayClient sender, List<RelayClient> clients) {
    if (sender.clientName == null) {
      return; // Cannot route if we don't know the sender type
    }

    final type = data['type'] as String?;
    if (type == null) return;

    // Directionality Enforcement
    if (sender.clientName == 'Android' && RelayConfig.macOnlyTypes.contains(type)) {
      print('BLOCKED_DIRECTION: Android attempted to send macOnly message ($type)');
      return;
    }

    if (sender.clientName == 'macOS' && RelayConfig.androidOnlyTypes.contains(type)) {
      print('BLOCKED_DIRECTION: macOS attempted to send androidOnly message ($type)');
      return;
    }

    // Forward to all authenticated clients except sender
    print('RelayRouter: Routing message of type $type from ${sender.clientName} to ${clients.length} total clients.');
    for (final client in clients) {
      if (client != sender) {
        if (client.authenticated) {
          try {
            print('RelayRouter: Forwarding to client ${client.clientName}');
            client.socket.add(rawMessage);
          } catch (e) {
            print('RelayRouter: Error routing message to client: $e');
          }
        } else {
          print('RelayRouter: Skipping unauthenticated client ${client.clientName}');
        }
      } else {
        print('RelayRouter: Skipping sender');
      }
    }
  }
}
