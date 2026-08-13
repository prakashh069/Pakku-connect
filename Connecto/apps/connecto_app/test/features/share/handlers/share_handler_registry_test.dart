import 'package:flutter_test/flutter_test.dart';
import 'package:connecto/features/share/handlers/share_handler_registry.dart';
import 'package:connecto/features/share/handlers/share_handler.dart';
import 'package:connecto/features/share/models/share_event.dart';
import 'package:connecto/features/share/models/share_content.dart';
import 'package:connecto/features/share/constants/share_constants.dart';

class FakeHandler implements ShareHandler {
  final String supportedMime;
  final bool shouldThrow;
  bool wasCalled = false;
  ShareEvent? receivedEvent;

  FakeHandler({required this.supportedMime, this.shouldThrow = false});

  @override
  bool supports(String mime) {
    return mime.toLowerCase() == supportedMime.toLowerCase();
  }

  @override
  Future<void> handle(ShareEvent event) async {
    wasCalled = true;
    receivedEvent = event;
    if (shouldThrow) {
      throw Exception('Fake exception');
    }
  }
}

void main() {
  group('ShareHandlerRegistry', () {
    late ShareEvent testEvent;

    setUp(() {
      testEvent = const ShareEvent(
        id: '123',
        mime: 'text/plain',
        deviceName: 'Test',
        timestamp: 0,
        content: ShareContent(
          encoding: ShareEncoding.utf8,
          body: 'body',
        ),
      );
    });

    test('dispatches to the correct handler', () async {
      final textHandler = FakeHandler(supportedMime: 'text/plain');
      final imageHandler = FakeHandler(supportedMime: 'image/png');
      
      final registry = ShareHandlerRegistry.forTesting([textHandler, imageHandler]);
      
      await registry.dispatch(testEvent);
      
      expect(textHandler.wasCalled, isTrue);
      expect(textHandler.receivedEvent, testEvent);
      expect(imageHandler.wasCalled, isFalse);
    });

    test('drops silently if no handler supports the mime type', () async {
      final imageHandler = FakeHandler(supportedMime: 'image/png');
      
      final registry = ShareHandlerRegistry.forTesting([imageHandler]);
      
      // Should not throw and should not call the handler
      await expectLater(registry.dispatch(testEvent), completes);
      
      expect(imageHandler.wasCalled, isFalse);
    });

    test('catches handler exceptions and drops silently', () async {
      final throwingHandler = FakeHandler(supportedMime: 'text/plain', shouldThrow: true);
      final registry = ShareHandlerRegistry.forTesting([throwingHandler]);
      
      // Should catch the exception internally and complete normally
      await expectLater(registry.dispatch(testEvent), completes);
      
      expect(throwingHandler.wasCalled, isTrue);
    });

    test('matches MIME types case-insensitively', () async {
      final upperCaseEvent = const ShareEvent(
        id: '123',
        mime: 'TEXT/PLAIN',
        deviceName: 'Test',
        timestamp: 0,
        content: ShareContent(encoding: ShareEncoding.utf8, body: 'body'),
      );

      final handler = FakeHandler(supportedMime: 'text/plain');
      final registry = ShareHandlerRegistry.forTesting([handler]);
      
      await registry.dispatch(upperCaseEvent);
      
      expect(handler.wasCalled, isTrue);
    });
  });
}
