class MessageTypes {
  const MessageTypes._();
  static const String incomingCall = 'incoming_call';
  static const String answerCall = 'answer_call';
  static const String rejectCall = 'reject_call';
  static const String dial = 'dial';
  static const String callState = 'call_state'; // answered | ended
  static const String deviceState = 'device_state'; // connected | disconnected
  static const String contactsRequest = 'contacts_request';
  static const String contacts = 'contacts';
  static const String endCall = 'end_call';
  static const String actionResult = 'action_result';
  static const String error = 'error';
  static const String unpair = 'unpair';
  static const String shareClipboard = 'share.clipboard';
  static const String requestCallHistory = 'request.call_history';
  static const String syncCallHistory = 'sync.call_history';
  static const String notificationReply = 'action.notification_reply';
  static const String syncNotification = 'sync.notification';
  static const String syncNotificationRemoved = 'sync.notification.removed';
}
