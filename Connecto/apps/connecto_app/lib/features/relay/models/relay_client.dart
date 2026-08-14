import 'dart:io';

class RelayClient {
  final WebSocket socket;
  final InternetAddress ip;
  bool authenticated = false;
  String? clientName; // 'macOS', 'Android', or 'Unknown'

  RelayClient({
    required this.socket,
    required this.ip,
  });
}
