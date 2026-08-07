import 'package:uuid/uuid.dart';

enum CallDirection { incoming, outgoing }
enum CallState { ringing, answeredRemotely, declinedRemotely, ended }

class Call {
  final String callId;
  final String phoneNumber;
  final String? contactName;
  final CallDirection direction;
  CallState state;
  final DateTime startedAt;

  Call({
    String? callId,
    required this.phoneNumber,
    this.contactName,
    required this.direction,
    this.state = CallState.ringing,
    DateTime? startedAt,
  })  : callId = callId ?? const Uuid().v4(),
        startedAt = startedAt ?? DateTime.now();
}
