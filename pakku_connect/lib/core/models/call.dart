enum CallDirection { incoming, outgoing }
enum CallState { ringing, answeredRemotely, declinedRemotely, ended }

class Call {
  final String phoneNumber;
  final String? contactName;
  final CallDirection direction;
  CallState state;
  final DateTime startedAt;

  Call({
    required this.phoneNumber,
    this.contactName,
    required this.direction,
    this.state = CallState.ringing,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();
}
