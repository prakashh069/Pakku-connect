import 'bus_message.dart';

enum MessageRoute {
  networkOnly,
  nativeOnly,
  broadcast,
}

abstract class MessageBus {
  /// Returns a stream of [BusMessage]s filtered by type prefix.
  Stream<BusMessage> messagesOfType(String typePrefix);

  /// Sends a message using explicit routing.
  /// 
  /// **Transport Failure Behavior:**
  /// The `MessageBus` employs best-effort fire-and-forget delivery.
  /// If the target transport (Network or Native) is unavailable, disconnected,
  /// or throws an exception during send, the `MessageBus` will catch the error,
  /// log a warning, and gracefully swallow it.
  /// The feature layer is isolated from these transport-level failures.
  void send(Map<String, dynamic> message, {MessageRoute route = MessageRoute.networkOnly});
  
  void dispose();
}
