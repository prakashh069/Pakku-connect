import 'package:flutter/material.dart';
import 'package:pakku_connect/core/models/contact.dart';
import 'package:pakku_connect/core/services/websocket_service.dart';
import 'package:pakku_connect/core/services/window_visibility_service.dart';
import 'package:pakku_connect/features/calling/services/call_manager.dart';

void main() {
  final ws = WebSocketService();
  ws.cachedContacts.add(RemoteContact(
    id: '1',
    displayName: 'Test User',
    phones: [RemotePhone(label: 'Mobile', number: '+918483992578')],
  ));
  
  final vis = WindowVisibilityService();
  final manager = CallManager(ws, vis);
  
  manager.handleIncoming('+918483992578', '');
  print('Done');
}
