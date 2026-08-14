import 'dart:io';

import 'package:connecto/features/relay/models/relay_client.dart';
import 'package:connecto/features/relay/services/relay_router.dart';
import 'package:flutter_test/flutter_test.dart';

class MockWebSocket implements WebSocket {
  final List<String> sentMessages = [];

  @override
  void add(data) {
    sentMessages.add(data.toString());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('RelayRouter', () {
    late RelayRouter router;
    late RelayClient macClient;
    late RelayClient androidClient;
    late RelayClient macClient2;

    setUp(() {
      router = RelayRouter();
      
      macClient = RelayClient(socket: MockWebSocket(), ip: InternetAddress('127.0.0.1'))
        ..authenticated = true
        ..clientName = 'macOS';
        
      androidClient = RelayClient(socket: MockWebSocket(), ip: InternetAddress('127.0.0.2'))
        ..authenticated = true
        ..clientName = 'Android';

      macClient2 = RelayClient(socket: MockWebSocket(), ip: InternetAddress('127.0.0.3'))
        ..authenticated = true
        ..clientName = 'macOS';
    });

    test('should drop MAC_ONLY message from Android', () {
      final data = {'type': 'dial'};
      router.routeMessage('{"type":"dial"}', data, androidClient, [macClient, androidClient, macClient2]);

      expect((macClient.socket as MockWebSocket).sentMessages.isEmpty, true);
    });

    test('should drop ANDROID_ONLY message from macOS', () {
      final data = {'type': 'incoming_call'};
      router.routeMessage('{"type":"incoming_call"}', data, macClient, [macClient, androidClient, macClient2]);

      expect((androidClient.socket as MockWebSocket).sentMessages.isEmpty, true);
    });

    test('should forward valid message to other authenticated clients', () {
      final data = {'type': 'incoming_call'};
      // From Android, should reach both macOS clients
      router.routeMessage('{"type":"incoming_call"}', data, androidClient, [macClient, androidClient, macClient2]);

      expect((macClient.socket as MockWebSocket).sentMessages.length, 1);
      expect((macClient2.socket as MockWebSocket).sentMessages.length, 1);
      // Sender should not receive its own message
      expect((androidClient.socket as MockWebSocket).sentMessages.isEmpty, true);
    });

    test('should allow notification message from Android to macOS', () {
      final data = {'type': 'notification'};
      router.routeMessage('{"type":"notification"}', data, androidClient, [macClient, androidClient, macClient2]);

      expect((macClient.socket as MockWebSocket).sentMessages.length, 1);
      expect((macClient2.socket as MockWebSocket).sentMessages.length, 1);
      expect((androidClient.socket as MockWebSocket).sentMessages.isEmpty, true);
    });

    test('should drop notification message from macOS to Android (direction enforcement)', () {
      final data = {'type': 'notification'};
      router.routeMessage('{"type":"notification"}', data, macClient, [macClient, androidClient, macClient2]);

      // Android should NOT receive a notification message from macOS
      expect((androidClient.socket as MockWebSocket).sentMessages.isEmpty, true);
      // macOS2 should NOT receive it either, message is dropped entirely
      expect((macClient2.socket as MockWebSocket).sentMessages.isEmpty, true);
    });
  });
}
