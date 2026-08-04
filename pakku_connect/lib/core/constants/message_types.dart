class MessageTypes {
  static const String incomingCall = 'incoming_call';
  static const String answerCall = 'answer_call';
  static const String rejectCall = 'reject_call';
  static const String dial = 'dial';
  static const String callState = 'call_state'; // answered | ended
  static const String deviceState = 'device_state'; // connected | disconnected
  static const String contactsRequest = 'contacts_request';
  static const String contacts = 'contacts';
  static const String error = 'error';
}
