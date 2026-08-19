/// Application-level constants for Connecto.
///
/// Port and protocol configuration is defined here to provide a single source
/// of truth. Changing a value here propagates to all features automatically.

/// The port on which the local relay WebSocket server listens.
/// Must match the port configured in the Node relay server (server.js).
const int kRelayPort = 8080;
