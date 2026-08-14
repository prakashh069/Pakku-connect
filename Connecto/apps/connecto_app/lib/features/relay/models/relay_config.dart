class RelayConfig {
  static const int maxPayloadBytes = 5 * 1024 * 1024; // 5 MB
  static const int maxUnauthenticated = 10;
  static const Duration handshakeTimeout = Duration(milliseconds: 5000);
  static const Duration rateLimitWindow = Duration(milliseconds: 60000);
  static const int rateLimitMaxFailures = 5;
  static const Duration blacklistDuration = Duration(milliseconds: 60000);
  static const Duration heartbeatInterval = Duration(seconds: 30);

  // Message directionality validation sets
  static const Set<String> macOnlyTypes = {
    'dial',
    'answer_call',
    'reject_call',
    'end_call',
    'set_ringer_mode',
    'device_action',
    'contacts_request',
    'request.call_history',
    'action.notification_reply',
  };

  static const Set<String> androidOnlyTypes = {
    'incoming_call',
    'call_state',
    'contacts',
    'sync.call_history',
    'battery_status',
    'device_state',
    'action_result',
    'notification',
    'sync.notification',
    'device.telemetry',
  };
}
