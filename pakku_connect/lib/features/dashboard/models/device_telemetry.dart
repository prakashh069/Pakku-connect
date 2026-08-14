class DeviceTelemetry {
  final int version;
  final int percentage;
  final bool charging;
  final String? network;

  DeviceTelemetry({
    required this.version,
    required this.percentage,
    required this.charging,
    this.network,
  });

  factory DeviceTelemetry.fromJson(Map<String, dynamic> json) {
    final battery = json['battery'] as Map<String, dynamic>? ?? {};
    return DeviceTelemetry(
      version: json['version'] as int? ?? 1,
      percentage: battery['percentage'] as int? ?? -1,
      charging: battery['charging'] as bool? ?? false,
      network: json['network'] as String?,
    );
  }
}
