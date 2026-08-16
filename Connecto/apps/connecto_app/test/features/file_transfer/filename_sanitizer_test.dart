import 'package:flutter_test/flutter_test.dart';
import '../../../lib/features/file_transfer/utils/filename_sanitizer.dart';

void main() {
  group('FilenameSanitizer', () {
    test('keeps normal filenames unchanged', () {
      expect(FilenameSanitizer.sanitize('document.pdf'), 'document.pdf');
      expect(FilenameSanitizer.sanitize('my_video 2.mp4'), 'my_video 2.mp4');
    });

    test('strips path separators and dots', () {
      expect(FilenameSanitizer.sanitize('../secret.txt'), 'secret.txt');
      expect(FilenameSanitizer.sanitize('/etc/passwd'), 'etcpasswd');
      expect(FilenameSanitizer.sanitize('C:\\Windows\\System32'), 'C_WindowsSystem32');
    });

    test('removes path traversal dots', () {
      expect(FilenameSanitizer.sanitize('..secret.txt'), 'secret.txt');
    });

    test('replaces unsafe characters', () {
      expect(FilenameSanitizer.sanitize('file:name*.txt?'), 'file_name_.txt_');
      expect(FilenameSanitizer.sanitize('<file>|"'), '_file___');
    });

    test('handles empty or null-like strings', () {
      expect(FilenameSanitizer.sanitize(''), 'unnamed_file');
      expect(FilenameSanitizer.sanitize('\x00\x01'), 'unnamed_file');
    });

    test('truncates extremely long filenames but preserves extension', () {
      final longName = 'a' * 300 + '.pdf';
      final sanitized = FilenameSanitizer.sanitize(longName);
      
      expect(sanitized.length, 255);
      expect(sanitized.endsWith('.pdf'), isTrue);
      expect(sanitized.startsWith('a' * 251), isTrue);
    });
  });
}
