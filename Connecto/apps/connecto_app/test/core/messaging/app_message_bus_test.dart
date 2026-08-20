import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:connecto/core/messaging/app_message_bus.dart';
import 'package:connecto/core/messaging/bus_message.dart';
import 'package:connecto/core/interfaces/device_transport.dart';

class MockTransport implements DeviceTransport {
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  
  @override
  Stream<Map<String, dynamic>> get messages => _controller.stream;

  @override
  void send(Map<String, dynamic> message) {}
  
  void injectMessage(Map<String, dynamic> msg) {
    _controller.add(msg);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('AppMessageBus Deduplication', () {
    test('Protocol messages (file.transfer.*) bypass deduplication', () async {
      final transport = MockTransport();
      final bus = AppMessageBus(deviceTransport: transport, dedupTtl: const Duration(seconds: 5));
      
      final messages = <BusMessage>[];
      bus.messagesOfType('file.transfer.chunk_ack').listen((msg) {
        messages.add(msg);
      });

      // Inject 3 chunk acks
      for (int i = 0; i < 3; i++) {
        transport.injectMessage({
          'type': 'file.transfer.chunk_ack',
          'transferId': 'transferA',
          'chunkIndex': i,
        });
      }

      // Allow async events to process
      await Future.delayed(const Duration(milliseconds: 50));

      expect(messages.length, equals(3), reason: 'All 3 protocol messages should be delivered');
      
      bus.dispose();
    });

    test('Normal event messages are deduplicated', () async {
      final transport = MockTransport();
      final bus = AppMessageBus(deviceTransport: transport, dedupTtl: const Duration(seconds: 5));
      
      final messages = <BusMessage>[];
      bus.messagesOfType('event').listen((msg) {
        messages.add(msg);
      });

      // Inject identical messages
      for (int i = 0; i < 3; i++) {
        transport.injectMessage({
          'type': 'event',
          'id': 'msg_123',
          'payload': 'data',
        });
      }

      await Future.delayed(const Duration(milliseconds: 50));

      expect(messages.length, equals(1), reason: 'Identical normal events should be suppressed to 1 delivery');
      
      bus.dispose();
    });

    test('File transfer ACK ordering is preserved', () async {
      final transport = MockTransport();
      final bus = AppMessageBus(deviceTransport: transport, dedupTtl: const Duration(seconds: 5));
      
      final receivedIndices = <int>[];
      bus.messagesOfType('file.transfer.chunk_ack').listen((msg) {
        receivedIndices.add(msg.raw['chunkIndex'] as int);
      });

      // Inject ACKs in a specific order
      final testOrder = [0, 1, 2, 4, 3, 5];
      for (final index in testOrder) {
        transport.injectMessage({
          'type': 'file.transfer.chunk_ack',
          'transferId': 'transferB',
          'chunkIndex': index,
        });
      }

      await Future.delayed(const Duration(milliseconds: 50));

      expect(receivedIndices, equals(testOrder), reason: 'ACK ordering should perfectly match the received injection order');
      
      bus.dispose();
    });
  });
}
