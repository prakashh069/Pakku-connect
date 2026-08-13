import 'package:flutter_test/flutter_test.dart';
import 'package:connecto/features/share/models/share_event.dart';
import 'package:connecto/features/share/models/share_content.dart';
import 'package:connecto/features/share/constants/share_constants.dart';

void main() {
  group('ShareEvent', () {
    test('constructs successfully with all required fields', () {
      const content = ShareContent(
        encoding: ShareEncoding.utf8,
        body: 'hello world',
      );

      const event = ShareEvent(
        id: '1234-5678',
        mime: ShareMime.text,
        deviceName: 'Pixel 8',
        timestamp: 1724000000000,
        content: content,
      );

      expect(event.id, '1234-5678');
      expect(event.mime, ShareMime.text);
      expect(event.deviceName, 'Pixel 8');
      expect(event.timestamp, 1724000000000);
      expect(event.content, content);
      expect(event.content.body, 'hello world');
    });
  });
}
