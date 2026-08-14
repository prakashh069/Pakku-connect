import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:connecto/features/notifications/services/notification_manager.dart';
import 'package:connecto/core/services/platform_transport.dart';
import 'package:connecto/core/constants/message_types.dart';

class MockPlatformTransport implements PlatformTransport {
  final _messagesController = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get messages => _messagesController.stream;

  @override
  void send(Map<String, dynamic> message) {}

  @override
  void dispose() {
    _messagesController.close();
  }

  void simulateIncomingMessage(Map<String, dynamic> message) {
    _messagesController.add(message);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlatformTransport mockTransport;
  late NotificationManager notificationManager;
  final List<MethodCall> methodCalls = [];

  setUp(() {
    mockTransport = MockPlatformTransport();
    
    const MethodChannel('com.connecto.app/notifications')
        .setMockMethodCallHandler((MethodCall methodCall) async {
      methodCalls.add(methodCall);
      return null;
    });

    notificationManager = NotificationManager(mockTransport);
  });

  tearDown(() {
    notificationManager.dispose();
    methodCalls.clear();
  });

  test('NotificationManager ignores non-notification messages', () async {
    mockTransport.simulateIncomingMessage({'type': 'battery_status', 'level': 50});
    await pumpEventQueue();
    expect(methodCalls.isEmpty, isTrue);
  });

  test('NotificationManager forwards valid notification to MethodChannel', () async {
    mockTransport.simulateIncomingMessage({
      'type': MessageTypes.notification,
      'id': 'com.example:123',
      'package': 'com.example',
      'app': 'Example App',
      'title': 'Test Title',
      'body': 'Test Body',
    });
    
    await pumpEventQueue();
    
    expect(methodCalls.length, 1);
    expect(methodCalls.first.method, 'showNotification');
    expect(methodCalls.first.arguments['app'], 'Example App');
    expect(methodCalls.first.arguments['title'], 'Test Title');
    expect(methodCalls.first.arguments['body'], 'Test Body');
  });

  test('NotificationManager deduplicates messages within 500ms window', () async {
    final payload = {
      'type': MessageTypes.notification,
      'id': 'com.example:123',
      'package': 'com.example',
      'app': 'Example App',
      'title': 'Test Title',
      'body': 'Test Body',
    };

    mockTransport.simulateIncomingMessage(payload);
    mockTransport.simulateIncomingMessage(payload); // Duplicate
    
    await pumpEventQueue();
    
    expect(methodCalls.length, 1); // Should only be forwarded once
  });

  test('NotificationManager allows different IDs immediately', () async {
    mockTransport.simulateIncomingMessage({
      'type': MessageTypes.notification,
      'id': 'com.example:123',
      'package': 'com.example',
      'app': 'Example App',
      'title': 'Test Title',
      'body': 'Test Body',
    });

    mockTransport.simulateIncomingMessage({
      'type': MessageTypes.notification,
      'id': 'com.example:456',
      'package': 'com.example',
      'app': 'Example App',
      'title': 'Another Title',
      'body': 'Another Body',
    });
    
    await pumpEventQueue();
    
    expect(methodCalls.length, 2);
  });
}
