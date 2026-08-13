class RecentCall {
  final String id;
  final String name;
  final String number;
  final String type;
  final int duration;
  final int timestamp;

  RecentCall({
    required this.id,
    required this.name,
    required this.number,
    required this.type,
    required this.duration,
    required this.timestamp,
  });

  factory RecentCall.fromJson(Map<String, dynamic> json) {
    // Preserve forward compatibility by providing defaults for missing fields
    return RecentCall(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      number: json['number']?.toString() ?? '',
      type: json['type']?.toString() ?? 'unknown',
      duration: json['duration'] is num ? (json['duration'] as num).toInt() : 0,
      timestamp: json['timestamp'] is num ? (json['timestamp'] as num).toInt() : 0,
    );
  }
}
