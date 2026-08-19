import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connecto/features/clipboard/services/clipboard_sync_manager.dart';
import 'package:connecto/core/messaging/app_message_bus.dart';
import 'package:connecto/core/interfaces/device_transport.dart';
import 'package:connecto/core/constants/message_types.dart';
import 'package:connecto/features/share/constants/share_constants.dart';
import 'package:connecto/features/share/models/share_event.dart';

class FakeTransport implements DeviceTransport {
  final StreamController<Map<String, dynamic>> _controller = StreamController.broadcast();
  final List<Map<String, dynamic>> sentMessages = [];

  @override
  Stream<Map<String, dynamic>> get messages => _controller.stream;

  @override
  void send(Map<String, dynamic> message) {
    sentMessages.add(message);
  }

  void receiveMessage(Map<String, dynamic> message) {
    _controller.add(message);
  }

  @override
  void dispose() {
    _controller.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClipboardSyncManager', () {
    late FakeTransport transport;
    late AppMessageBus bus;
    late ClipboardSyncManager manager;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'clipboard_sync_enabled': true,
      });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.pakku.connect/platform'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'getDeviceName') return 'TestDevice';
          return null;
        },
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.connecto.app/macClipboard'),
        (MethodCall methodCall) async {
          return null;
        },
      );
      
      // Need to mock flutter/platform for Clipboard.getData
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter/platform'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.getData') {
            return {'text': 'local clipboard text'};
          }
          return null;
        },
      );

      transport = FakeTransport();
      bus = AppMessageBus(deviceTransport: transport);
    });

    tearDown(() {
      bus.dispose();
      manager.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('com.pakku.connect/platform'), null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('com.connecto.app/macClipboard'), null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('flutter/platform'), null);
    });

    test('initializes and respects shared preferences', () async {
      manager = ClipboardSyncManager(messageBus: bus);
      // Let async init complete
      await Future.delayed(Duration.zero);
      expect(manager.enabled, isTrue);
    });

    test('emits valid inbound text share correctly', () async {
      manager = ClipboardSyncManager(messageBus: bus);
      await Future.delayed(Duration.zero);

      ShareEvent? receivedEvent;
      manager.inboundShares.listen((event) {
        receivedEvent = event;
      });

      final inboundJson = {
        'schemaVersion': 1,
        'type': MessageTypes.shareClipboard,
        'timestamp': 1000,
        'payload': {
          'id': 'remote-123',
          'mime': ShareMime.text,
          'deviceName': 'Remote',
          'content': {
            'encoding': ShareEncoding.utf8,
            'body': 'remote text',
          }
        }
      };

      transport.receiveMessage(inboundJson);
      await Future.delayed(Duration.zero);

      expect(receivedEvent, isNotNull);
      expect(receivedEvent!.id, 'remote-123');
      expect(receivedEvent!.content.body, 'remote text');
    });

    test('drops inbound share if schemaVersion is incorrect', () async {
      manager = ClipboardSyncManager(messageBus: bus);
      await Future.delayed(Duration.zero);

      ShareEvent? receivedEvent;
      manager.inboundShares.listen((event) => receivedEvent = event);

      transport.receiveMessage({
        'schemaVersion': 2, // Unsupported
        'type': MessageTypes.shareClipboard,
        'payload': {
          'id': '123',
          'mime': ShareMime.text,
          'content': {'encoding': ShareEncoding.utf8, 'body': 'test'}
        }
      });
      await Future.delayed(Duration.zero);
      expect(receivedEvent, isNull);
    });

    test('drops inbound text payload if size exceeds limit', () async {
      manager = ClipboardSyncManager(messageBus: bus);
      await Future.delayed(Duration.zero);

      ShareEvent? receivedEvent;
      manager.inboundShares.listen((event) => receivedEvent = event);

      final massiveText = 'A' * (ShareLimits.maxEncodedPayloadBytes + 1);

      transport.receiveMessage({
        'schemaVersion': 1,
        'type': MessageTypes.shareClipboard,
        'payload': {
          'id': '123',
          'mime': ShareMime.text,
          'content': {
            'encoding': ShareEncoding.utf8,
            'body': massiveText,
          }
        }
      });
      await Future.delayed(Duration.zero);
      expect(receivedEvent, isNull);
    });
    
    test('deduplicates based on ID', () async {
      manager = ClipboardSyncManager(messageBus: bus);
      await Future.delayed(Duration.zero);

      int receiveCount = 0;
      manager.inboundShares.listen((event) => receiveCount++);

      final inboundJson = {
        'schemaVersion': 1,
        'type': MessageTypes.shareClipboard,
        'payload': {
          'id': 'dup-id',
          'mime': ShareMime.text,
          'content': {'encoding': ShareEncoding.utf8, 'body': 'hello'}
        }
      };

      // Send twice
      transport.receiveMessage(inboundJson);
      transport.receiveMessage(inboundJson);
      await Future.delayed(Duration.zero);

      // Should only emit once due to ID deduplication
      expect(receiveCount, 1);
    });
  });
}
