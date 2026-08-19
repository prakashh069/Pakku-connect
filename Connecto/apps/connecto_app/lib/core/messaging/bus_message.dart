import 'dart:convert';
import 'package:crypto/crypto.dart';

enum MessageCategory {
  event,
  command,
  transferProtocol,
}

class BusMessage {
  final Map<String, dynamic> raw;
  final String type;
  
  const BusMessage(this.raw, this.type);

  MessageCategory get category {
    if (type.startsWith('file.transfer.')) {
      return MessageCategory.transferProtocol;
    }
    return MessageCategory.event;
  }

  /// Extract or generate a unique identifier for deduplication
  String get deduplicationId {
    if (category == MessageCategory.transferProtocol) {
      // Protocol messages bypass deduplication in AppMessageBus, so this ID is unused for them.
      return 'bypass';
    }

    final explicitId = raw['id']?.toString() ?? raw['transferId']?.toString();
    if (explicitId != null && explicitId.isNotEmpty) {
      return '${type}_$explicitId';
    }

    // Fallback: SHA-256 of the payload
    final payloadStr = jsonEncode(raw);
    final bytes = utf8.encode(payloadStr);
    final digest = sha256.convert(bytes);
    return '${type}_$digest';
  }

  factory BusMessage.fromJson(Map<String, dynamic> json) {
    return BusMessage(
      json,
      json['type']?.toString() ?? 'unknown',
    );
  }
}
