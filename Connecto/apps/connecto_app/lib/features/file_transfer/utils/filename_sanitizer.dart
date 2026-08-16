class FilenameSanitizer {
  static String sanitize(String filename) {
    if (filename.isEmpty) return 'unnamed_file';
    
    // 1. Strip path separators
    String safeName = filename.replaceAll(RegExp(r'[/\\]'), '');
    
    // 2. Remove null bytes and control characters
    safeName = safeName.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
    
    // 3. Prevent path traversal attempts that rely on '..' 
    // (though stripping slashes usually covers this, good defense in depth)
    safeName = safeName.replaceAll('..', '');

    // 4. Truncate to 255 characters (typical OS limit)
    if (safeName.length > 255) {
      // Try to preserve extension
      final lastDot = safeName.lastIndexOf('.');
      if (lastDot > 0 && safeName.length - lastDot < 20) {
        final ext = safeName.substring(lastDot);
        safeName = safeName.substring(0, 255 - ext.length) + ext;
      } else {
        safeName = safeName.substring(0, 255);
      }
    }
    
    // 5. Replace remaining unsafe characters (colon, asterisk, question mark, quotes, less/greater, pipe)
    safeName = safeName.replaceAll(RegExp(r'[:*?"<>|]'), '_');

    if (safeName.isEmpty) return 'unnamed_file';
    return safeName;
  }
}
