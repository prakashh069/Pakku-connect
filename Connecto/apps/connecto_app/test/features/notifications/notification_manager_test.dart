import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:connecto/features/notifications/services/notification_manager.dart';
import 'package:connecto/core/messaging/message_bus.dart';
import 'package:connecto/core/messaging/bus_message.dart';
import 'package:connecto/core/messaging/message_types.dart';

class MockMessageBus implements MessageBus {
  final _controller = StreamController<BusMessage>.broadcast();

  @override
  Stream<BusMessage> messagesOfType(String typePrefix) {
    return _controller.stream.where((msg) => msg.type.startsWith(typePrefix));
  }

  @override
  void send(Map<String, dynamic> message, {MessageRoute route = MessageRoute.networkOnly}) {}

  @override
  void dispose() {}
  
  void injectMessage(BusMessage msg) {
    _controller.add(msg);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NotificationManager notificationManager;
  late MockMessageBus mockBus;
  final List<MethodCall> methodCalls = [];

  setUp(() {
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.connecto.app/notifications'), (MethodCall methodCall) async {
      methodCalls.add(methodCall);
      return null;
    });

    mockBus = MockMessageBus();
    notificationManager = NotificationManager(mockBus);
  });

  tearDown(() {
    notificationManager.dispose();
    methodCalls.clear();
  });

  test('NotificationManager ignores non-notification messages', () async {
    mockBus.injectMessage(BusMessage({'type': 'battery_status', 'level': 50}, 'battery_status'));
    await pumpEventQueue();
    expect(methodCalls.isEmpty, isTrue);
  });

  test('NotificationManager forwards valid notification to MethodChannel', () async {
    mockBus.injectMessage(BusMessage({
      'type': BusMessagePrefixes.notification,
      'id': 'com.example:123',
      'package': 'com.example',
      'app': 'Example App',
      'title': 'Test Title',
      'body': 'Test Body',
    }, BusMessagePrefixes.notification));
    
    await pumpEventQueue();
    
    expect(methodCalls.length, 1);
    expect(methodCalls.first.method, 'showNotification');
    expect(methodCalls.first.arguments['app'], 'Example App');
    expect(methodCalls.first.arguments['title'], 'Test Title');
    expect(methodCalls.first.arguments['body'], 'Test Body');
  });

  test('NotificationManager deduplicates messages within 500ms window', () async {
    final payload = BusMessage({
      'type': BusMessagePrefixes.notification,
      'id': 'com.example:123',
      'package': 'com.example',
      'app': 'Example App',
      'title': 'Test Title',
      'body': 'Test Body',
    }, BusMessagePrefixes.notification);

    mockBus.injectMessage(payload);
    mockBus.injectMessage(payload); // Duplicate
    
    await pumpEventQueue();
    
    expect(methodCalls.length, 1); // Should only be forwarded once
  });

  test('NotificationManager allows different IDs immediately', () async {
    mockBus.injectMessage(BusMessage({
      'type': BusMessagePrefixes.notification,
      'id': 'com.example:123',
      'package': 'com.example',
      'app': 'Example App',
      'title': 'Test Title',
      'body': 'Test Body',
    }, BusMessagePrefixes.notification));

    mockBus.injectMessage(BusMessage({
      'type': BusMessagePrefixes.notification,
      'id': 'com.example:456',
      'package': 'com.example',
      'app': 'Example App',
      'title': 'Another Title',
      'body': 'Another Body',
    }, BusMessagePrefixes.notification));
    
    await pumpEventQueue();
    
    expect(methodCalls.length, 2);
  });
}
