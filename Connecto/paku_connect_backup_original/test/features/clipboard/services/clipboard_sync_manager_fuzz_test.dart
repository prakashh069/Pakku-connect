import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connecto/features/clipboard/services/clipboard_sync_manager.dart';
import 'package:connecto/core/services/platform_transport.dart';
import 'package:connecto/features/share/models/share_event.dart';

class FuzzFakeTransport implements PlatformTransport {
  final StreamController<Map<String, dynamic>> _controller = StreamController.broadcast();

  @override
  Stream<Map<String, dynamic>> get messages => _controller.stream;

  @override
  void send(Map<String, dynamic> message) {}

  void pushGarbage(dynamic message) {
    // The underlying method channel JSON decode produces Map<String, dynamic> 
    // for objects. If it's a map, we pass it in. If it's something else, 
    // the platform channel usually wouldn't emit it directly to this stream, 
    // but we can simulate broken maps.
    if (message is Map<String, dynamic>) {
      _controller.add(message);
    } else {
      try {
        _controller.add(Map<String, dynamic>.from(message as Map));
      } catch (_) {
        // Not a map, ignore for this transport boundary simulation
      }
    }
  }

  @override
  void dispose() {
    _controller.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClipboardSyncManager Fuzz Testing', () {
    late FuzzFakeTransport transport;
    late ClipboardSyncManager manager;

    setUp(() {
      SharedPreferences.setMockInitialValues({'clipboard_sync_enabled': true});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('com.pakku.connect/platform'), (_) async => null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('com.pakku.connect/macClipboard'), (_) async => null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('flutter/platform'), (_) async => null);

      transport = FuzzFakeTransport();
      manager = ClipboardSyncManager(transport);
    });

    tearDown(() {
      manager.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('com.pakku.connect/platform'), null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('com.pakku.connect/macClipboard'), null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('flutter/platform'), null);
    });

    test('Never crashes when fed thousands of malformed payloads', () async {
      await Future.delayed(Duration.zero); // Allow async init
      
      int validSharesReceived = 0;
      manager.inboundShares.listen((ShareEvent event) {
        validSharesReceived++;
      });

      final random = Random(42); // Fixed seed for reproducibility

      List<dynamic> generateJunkTypes() => [
        null,
        42,
        -1,
        0,
        3.14,
        "string",
        "",
        [],
        [1, 2, 3],
        {},
        {'key': 'value'},
        "A" * 100000 // Huge string
      ];

      // 1. Fuzz top-level envelope
      for (int i = 0; i < 1000; i++) {
        final junkType = generateJunkTypes()[random.nextInt(generateJunkTypes().length)];
        final junkSchema = generateJunkTypes()[random.nextInt(generateJunkTypes().length)];
        final junkPayload = generateJunkTypes()[random.nextInt(generateJunkTypes().length)];
        
        transport.pushGarbage({
          'type': junkType,
          'schemaVersion': junkSchema,
          'payload': junkPayload,
        });
      }

      // 2. Fuzz payload object fields
      for (int i = 0; i < 1000; i++) {
        final junkId = generateJunkTypes()[random.nextInt(generateJunkTypes().length)];
        final junkMime = generateJunkTypes()[random.nextInt(generateJunkTypes().length)];
        final junkContent = generateJunkTypes()[random.nextInt(generateJunkTypes().length)];
        
        transport.pushGarbage({
          'type': 'share.clipboard',
          'schemaVersion': 1,
          'payload': {
            'id': junkId,
            'mime': junkMime,
            'content': junkContent,
          }
        });
      }

      // 3. Fuzz content object fields
      // Uses a separate junk list that excludes known-valid encoding values
      // ('utf-8', 'base64') so this section never accidentally generates a
      // structurally conforming payload.
      List<dynamic> generateContentJunkTypes() => [
        null,
        42,
        -1,
        0,
        3.14,
        "not-a-valid-encoding",  // clearly invalid string, not a known encoding
        "",
        [],
        [1, 2, 3],
        {},
        {'key': 'value'},
        "A" * 100000,
      ];
      for (int i = 0; i < 1000; i++) {
        final junkEncoding = generateContentJunkTypes()[random.nextInt(generateContentJunkTypes().length)];
        final junkBody = generateContentJunkTypes()[random.nextInt(generateContentJunkTypes().length)];
        final junkMeta = generateContentJunkTypes()[random.nextInt(generateContentJunkTypes().length)];
        
        transport.pushGarbage({
          'type': 'share.clipboard',
          'schemaVersion': 1,
          'payload': {
            'id': 'uuid-${random.nextInt(10000)}',
            'mime': 'text/plain',
            'content': {
              'encoding': junkEncoding,
              'body': junkBody,
              'metadata': junkMeta,
            }
          }
        });
      }

      // 4. Oversized body tests
      for (int size in [5 * 1024 * 1024 + 1, 10 * 1024 * 1024]) {
        transport.pushGarbage({
          'type': 'share.clipboard',
          'schemaVersion': 1,
          'payload': {
            'id': 'uuid-massive-$size',
            'mime': 'text/plain',
            'content': {
              'encoding': 'utf-8',
              'body': "A" * size,
            }
          }
        });
        
        transport.pushGarbage({
          'type': 'share.clipboard',
          'schemaVersion': 1,
          'payload': {
            'id': 'uuid-massive-b64-$size',
            'mime': 'image/png',
            'content': {
              'encoding': 'base64',
              'body': "A" * size,
            }
          }
        });
      }

      // 5. Corrupted base64 characters
      transport.pushGarbage({
        'type': 'share.clipboard',
        'schemaVersion': 1,
        'payload': {
          'id': 'uuid-bad-b64',
          'mime': 'image/png',
          'content': {
            'encoding': 'base64',
            'body': 'This is definitely not base64 @#&(*!',
          }
        }
      });

      // Allow event loop to clear
      await Future.delayed(Duration.zero);

      // We pushed 3000+ garbage payloads, and none of them should have crashed the app.
      // The corrupted-base64 payload (section 5) is structurally valid at the transport level
      // (known encoding 'base64', non-empty String body) and correctly emits a ShareEvent.
      // The ImageHandler rejects it at decode time — that is the designed failure boundary.
      // All other garbage payloads (non-String bodies, unknown encodings, invalid envelopes)
      // must be rejected before reaching the stream.
      expect(validSharesReceived, 1, reason: 'Garbage payload accidentally slipped through validation');

      // Finally, prove the stream is still alive and processes a valid payload.
      transport.pushGarbage({
        'type': 'share.clipboard',
        'schemaVersion': 1,
        'payload': {
          'id': 'valid-uuid',
          'mime': 'text/plain',
          'content': {
            'encoding': 'utf-8',
            'body': 'Survived the fuzzing!',
          }
        }
      });

      await Future.delayed(Duration.zero);
      expect(validSharesReceived, 2, reason: 'Stream must still be alive and process valid data after fuzzing');
    });
  });
}
