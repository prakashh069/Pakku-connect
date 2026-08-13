import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:connecto/features/share/handlers/image_handler.dart';
import 'package:connecto/features/share/models/share_event.dart';
import 'package:connecto/features/share/models/share_content.dart';
import 'package:connecto/features/share/constants/share_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageHandler', () {
    late ImageHandler handler;
    final List<MethodCall> methodCalls = [];

    setUp(() {
      handler = ImageHandler();
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

    test('supports valid image MIME types', () {
      expect(handler.supports('image/png'), isTrue);
      expect(handler.supports('IMAGE/JPEG'), isTrue);
      expect(handler.supports('image/webp'), isTrue);
      expect(handler.supports('text/plain'), isFalse);
      expect(handler.supports('application/pdf'), isFalse);
    });

    test('handles valid image event and invokes MethodChannel', () async {
      final event = ShareEvent(
        id: '456',
        mime: ShareMime.png,
        deviceName: 'MacBook',
        timestamp: 0,
        content: const ShareContent(
          encoding: ShareEncoding.base64,
          body: 'aW1hZ2U=',
          metadata: {'width': 1920},
        ),
      );

      await handler.handle(event);

      expect(methodCalls, hasLength(1));
      expect(methodCalls.first.method, 'showShare');
      
      final arguments = methodCalls.first.arguments as Map<dynamic, dynamic>;
      expect(arguments['id'], '456');
      expect(arguments['mime'], ShareMime.png);
      expect(arguments['deviceName'], 'MacBook');
      
      final content = arguments['content'] as Map<dynamic, dynamic>;
      expect(content['encoding'], ShareEncoding.base64);
      expect(content['body'], 'aW1hZ2U=');
      expect(content['metadata']['width'], 1920);
    });

    test('drops event silently if encoding is not base64', () async {
      final event = ShareEvent(
        id: '456',
        mime: ShareMime.png,
        deviceName: 'MacBook',
        timestamp: 0,
        content: const ShareContent(
          encoding: ShareEncoding.utf8, // Invalid for image
          body: 'invalid',
        ),
      );

      await handler.handle(event);
      expect(methodCalls, isEmpty);
    });

    test('drops event silently if body is empty', () async {
      final event = ShareEvent(
        id: '456',
        mime: ShareMime.png,
        deviceName: 'MacBook',
        timestamp: 0,
        content: const ShareContent(
          encoding: ShareEncoding.base64,
          body: '',
        ),
      );

      await handler.handle(event);
      expect(methodCalls, isEmpty);
    });

    test('drops event silently if payload exceeds size limit', () async {
      // 5MB limit is 5 * 1024 * 1024
      final massiveBody = 'A' * (ShareLimits.maxEncodedPayloadBytes + 1);

      final event = ShareEvent(
        id: '456',
        mime: ShareMime.png,
        deviceName: 'MacBook',
        timestamp: 0,
        content: ShareContent(
          encoding: ShareEncoding.base64,
          body: massiveBody,
        ),
      );

      await handler.handle(event);
      expect(methodCalls, isEmpty); // Dropped silently
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
        id: '456',
        mime: ShareMime.png,
        deviceName: 'MacBook',
        timestamp: 0,
        content: const ShareContent(
          encoding: ShareEncoding.base64,
          body: 'aW1hZ2U=',
        ),
      );

      await expectLater(handler.handle(event), completes);
    });
  });
}
