import 'package:flutter_test/flutter_test.dart';
import '../../../lib/features/file_transfer/models/file_transfer_protocol.dart';
import '../../../lib/core/constants/message_types.dart';

void main() {
  group('FileTransferProtocol', () {
    test('FileTransferStart roundtrips', () {
      final json = {
        'type': MessageTypes.fileTransferStart,
        'transferId': '123',
        'name': 'test.pdf',
        'mime': 'application/pdf',
        'size': 1024,
        'totalChunks': 4,
        'sha256': 'hash'
      };
      
      final msg = FileTransferStart.fromJson(json);
      expect(msg.transferId, '123');
      expect(msg.name, 'test.pdf');
      
      final out = msg.toJson();
      expect(out, json);
    });

    test('FileTransferChunk roundtrips', () {
      final json = {
        'type': MessageTypes.fileTransferChunk,
        'transferId': '123',
        'chunkIndex': 0,
        'totalChunks': 4,
        'payload': 'base64'
      };
      
      final msg = FileTransferChunk.fromJson(json);
      expect(msg.chunkIndex, 0);
      
      final out = msg.toJson();
      expect(out, json);
    });

    test('FileTransferComplete roundtrips', () {
      final json = {
        'type': MessageTypes.fileTransferComplete,
        'transferId': '123',
        'sha256Match': true
      };
      
      final msg = FileTransferComplete.fromJson(json);
      expect(msg.sha256Match, true);
      
      final out = msg.toJson();
      expect(out, json);
    });

    test('FileTransferError roundtrips', () {
      final json = {
        'type': MessageTypes.fileTransferError,
        'transferId': '123',
        'reason': 'timeout'
      };
      
      final msg = FileTransferError.fromJson(json);
      expect(msg.reason, 'timeout');
      
      final out = msg.toJson();
      expect(out, json);
    });

    test('FileTransferCancel roundtrips', () {
      final json = {
        'type': MessageTypes.fileTransferCancel,
        'transferId': '123',
        'reason': 'user_aborted'
      };
      
      final msg = FileTransferCancel.fromJson(json);
      expect(msg.reason, 'user_aborted');
      
      final out = msg.toJson();
      expect(out, json);
    });

    test('MIME allowed checking', () {
      expect(FileTransferMimeTypes.isAllowed('application/pdf'), true);
      expect(FileTransferMimeTypes.isAllowed('text/plain'), true);
      expect(FileTransferMimeTypes.isAllowed('video/mp4'), true);
      expect(FileTransferMimeTypes.isAllowed('application/vnd.openxmlformats-officedocument.wordprocessingml.document'), true);
      
      expect(FileTransferMimeTypes.isAllowed('image/jpeg'), false);
      expect(FileTransferMimeTypes.isAllowed('application/exe'), false);
    });
  });
}
