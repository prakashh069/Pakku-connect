import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pakku_connect/features/share/handlers/text_handler.dart';
import 'package:pakku_connect/features/share/models/share_event.dart';
import 'package:pakku_connect/features/share/models/share_content.dart';
import 'package:pakku_connect/features/share/constants/share_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TextHandler', () {
    late TextHandler handler;
    final List<MethodCall> methodCalls = [];

    setUp(() {
      handler = TextHandler();
      methodCalls.clear();
      
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.pakku.connect/clipboardShare'),
        (MethodCall methodCall) async {
          methodCalls.add(methodCall);
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.pakku.connect/clipboardShare'),
        null,
      );
    });

    test('supports text/plain', () {
      expect(handler.supports('text/plain'), isTrue);
      expect(handler.supports('TEXT/PLAIN'), isTrue);
      expect(handler.supports('image/png'), isFalse);
    });

    test('handles valid text event and invokes MethodChannel', () async {
      final event = ShareEvent(
        id: '123',
        mime: ShareMime.text,
        deviceName: 'Test Device',
        timestamp: 0,
        content: const ShareContent(
          encoding: ShareEncoding.utf8,
          body: 'hello text',
          metadata: {'lang': 'en'},
        ),
      );

      await handler.handle(event);

      expect(methodCalls, hasLength(1));
      expect(methodCalls.first.method, 'showShare');
      
      final arguments = methodCalls.first.arguments as Map<dynamic, dynamic>;
      expect(arguments['id'], '123');
      expect(arguments['mime'], ShareMime.text);
      expect(arguments['deviceName'], 'Test Device');
      
      final content = arguments['content'] as Map<dynamic, dynamic>;
      expect(content['encoding'], ShareEncoding.utf8);
      expect(content['body'], 'hello text');
      expect(content['metadata']['lang'], 'en');
    });

    test('drops event silently if encoding is not utf8', () async {
      final event = ShareEvent(
        id: '123',
        mime: ShareMime.text,
        deviceName: 'Test',
        timestamp: 0,
        content: const ShareContent(
          encoding: ShareEncoding.base64,
          body: 'invalid',
        ),
      );

      await handler.handle(event);
      expect(methodCalls, isEmpty);
    });

    test('drops event silently if body is not a string', () async {
      final event = ShareEvent(
        id: '123',
        mime: ShareMime.text,
        deviceName: 'Test',
        timestamp: 0,
        content: const ShareContent(
          encoding: ShareEncoding.utf8,
          body: 12345, // Not a string
        ),
      );

      await handler.handle(event);
      expect(methodCalls, isEmpty);
    });

    test('does not throw if MethodChannel fails', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.pakku.connect/clipboardShare'),
        (MethodCall methodCall) async {
          throw PlatformException(code: 'ERROR');
        },
      );

      final event = ShareEvent(
        id: '123',
        mime: ShareMime.text,
        deviceName: 'Test Device',
        timestamp: 0,
        content: const ShareContent(
          encoding: ShareEncoding.utf8,
          body: 'hello text',
        ),
      );

      await expectLater(handler.handle(event), completes);
    });
  });
}
