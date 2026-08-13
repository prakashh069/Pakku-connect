import 'package:flutter_test/flutter_test.dart';
import 'package:connecto/features/share/models/share_content.dart';
import 'package:connecto/features/share/constants/share_constants.dart';

void main() {
  group('ShareContent', () {
    test('fromJson successfully parses valid JSON', () {
      final json = {
        'encoding': ShareEncoding.utf8,
        'body': 'test string',
        'metadata': {'key': 'value'},
      };

      final content = ShareContent.fromJson(json);

      expect(content, isNotNull);
      expect(content!.encoding, ShareEncoding.utf8);
      expect(content.body, 'test string');
      expect(content.metadata, isNotNull);
      expect(content.metadata!['key'], 'value');
    });

    test('fromJson successfully parses valid JSON without metadata', () {
      final json = {
        'encoding': ShareEncoding.base64,
        'body': 'aW1hZ2U=',
      };

      final content = ShareContent.fromJson(json);

      expect(content, isNotNull);
      expect(content!.encoding, ShareEncoding.base64);
      expect(content.body, 'aW1hZ2U=');
      expect(content.metadata, isNull);
    });

    test('fromJson returns null if encoding is missing', () {
      final json = {
        'body': 'test string',
      };
      expect(ShareContent.fromJson(json), isNull);
    });

    test('fromJson returns null if body is missing', () {
      final json = {
        'encoding': ShareEncoding.utf8,
      };
      expect(ShareContent.fromJson(json), isNull);
    });

    test('fromJson safely casts metadata or sets to null if malformed', () {
      final json = {
        'encoding': ShareEncoding.utf8,
        'body': 'test string',
        'metadata': 'this is not a map', // Malformed metadata
      };

      final content = ShareContent.fromJson(json);

      expect(content, isNotNull);
      expect(content!.metadata, isNull); // Falls back to null safely
    });

    test('toJson serializes correctly', () {
      const content = ShareContent(
        encoding: ShareEncoding.utf8,
        body: 'test string',
        metadata: {'width': 100},
      );

      final json = content.toJson();

      expect(json['encoding'], ShareEncoding.utf8);
      expect(json['body'], 'test string');
      expect(json['metadata'], isNotNull);
      expect(json['metadata']['width'], 100);
    });

    test('toJson omits metadata if null', () {
      const content = ShareContent(
        encoding: ShareEncoding.base64,
        body: 'aW1hZ2U=',
      );

      final json = content.toJson();

      expect(json.containsKey('metadata'), isFalse);
    });
  });
}
