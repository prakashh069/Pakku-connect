import 'package:flutter_test/flutter_test.dart';
import 'package:connecto/core/messaging/bus_message.dart';

void main() {
  group('BusMessage Deduplication Logic', () {
    test('Normal event uses id for deduplication', () {
      final msg1 = BusMessage({'type': 'event', 'id': '123'}, 'event');
      final msg2 = BusMessage({'type': 'event', 'id': '123', 'other': 'data'}, 'event');
      
      expect(msg1.deduplicationId, equals(msg2.deduplicationId));
      expect(msg1.category, equals(MessageCategory.event));
    });

    test('file.transfer.* messages are categorized as transferProtocol', () {
      final msg = BusMessage({'type': 'file.transfer.chunk_ack'}, 'file.transfer.chunk_ack');
      expect(msg.category, equals(MessageCategory.transferProtocol));
    });

    test('Transfer protocol messages return bypass for deduplication ID', () {
      final msg1 = BusMessage({
        'type': 'file.transfer.chunk_ack',
        'transferId': 'transfer123',
        'fileId': 'fileA',
        'chunkIndex': 0,
      }, 'file.transfer.chunk_ack');

      final msg2 = BusMessage({
        'type': 'file.transfer.chunk_ack',
        'transferId': 'transfer123',
        'fileId': 'fileA',
        'chunkIndex': 1,
      }, 'file.transfer.chunk_ack');

      expect(msg1.deduplicationId, equals('bypass'));
      expect(msg2.deduplicationId, equals('bypass'));
    });
  });
}
