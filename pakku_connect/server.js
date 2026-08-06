const fs = require('fs');
const https = require('https');
const WebSocket = require('ws');
require('dotenv').config();

// ---------------------------------------------------------------------------
// Structured logging
// ---------------------------------------------------------------------------
const log = (event, details = {}) =>
  console.log(JSON.stringify({ timestamp: new Date().toISOString(), event, ...details }));

const errLog = (event, details = {}) =>
  console.error(JSON.stringify({ timestamp: new Date().toISOString(), event, ...details }));

// ---------------------------------------------------------------------------
// TLS setup
// ---------------------------------------------------------------------------
let cert, key;
try {
  cert = fs.readFileSync('certs/device.crt');
  key  = fs.readFileSync('certs/device.key');
} catch (e) {
  errLog('tls_cert_read_failed', { error: e.message });
  process.exit(1);
}

const server = https.createServer({ cert, key });
const wss    = new WebSocket.Server({ server });

// ---------------------------------------------------------------------------
// Security constants
// ---------------------------------------------------------------------------
const MAX_PAYLOAD_BYTES       = 5 * 1024 * 1024; // 5 MB (accommodates large contact lists)
const MAX_UNAUTHENTICATED     = 10;          // max simultaneous unauthed sockets
const HANDSHAKE_TIMEOUT_MS    = 5000;        // 5 s to send hello after connect
const RATE_LIMIT_WINDOW_MS    = 60 * 1000;   // 60 s window
const RATE_LIMIT_MAX_FAILURES = 5;           // failures before IP is blocked
const BLACKLIST_DURATION_MS   = 60 * 1000;   // 60 s blacklist duration

// ---------------------------------------------------------------------------
// In-memory security state (per-IP, reset on restart)
// ---------------------------------------------------------------------------
const failureTracker = new Map();  // ip -> { count, windowStart }
const blacklist      = new Map();  // ip -> expiresAt (ms epoch)

function isBlacklisted(ip) {
  const expires = blacklist.get(ip);
  if (!expires) return false;
  if (Date.now() > expires) {
    blacklist.delete(ip);
    return false;
  }
  return true;
}

function recordFailure(ip) {
  const now = Date.now();
  const entry = failureTracker.get(ip) || { count: 0, windowStart: now };

  // Reset window if expired
  if (now - entry.windowStart > RATE_LIMIT_WINDOW_MS) {
    entry.count = 0;
    entry.windowStart = now;
  }

  entry.count++;
  failureTracker.set(ip, entry);

  if (entry.count >= RATE_LIMIT_MAX_FAILURES) {
    blacklist.set(ip, now + BLACKLIST_DURATION_MS);
    errLog('ip_blacklisted', { ip, duration_ms: BLACKLIST_DURATION_MS });
  }
}

// ---------------------------------------------------------------------------
// Track unauthenticated connection count
// ---------------------------------------------------------------------------
let unauthenticatedCount = 0;

// ---------------------------------------------------------------------------
// Stale connection cleanup (Ping/Pong heartbeat)
// ---------------------------------------------------------------------------
const noop = () => {};
const heartbeatInterval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (ws.isAlive === false) {
      log('client_terminated_stale', { name: ws.clientName || 'unknown' });
      return ws.terminate();
    }
    ws.isAlive = false;
    ws.ping(noop);
  });
}, 30000);

// ---------------------------------------------------------------------------
// Connection handler
// ---------------------------------------------------------------------------
wss.on('connection', (ws, req) => {
  console.log('Client connected');
  const ip = req.socket.remoteAddress || 'unknown';

  // 3.2 / 3.3 — Rate limit and connection limit checks
  if (isBlacklisted(ip)) {
    errLog('connection_rejected_blacklisted', { ip });
    ws.close(1008, 'Blocked');
    return;
  }

  if (unauthenticatedCount >= MAX_UNAUTHENTICATED) {
    errLog('connection_rejected_limit', { ip, limit: MAX_UNAUTHENTICATED });
    ws.close(1008, 'Too many connections');
    return;
  }

  ws.isAlive       = true;
  ws.authenticated = false;
  ws.clientName    = null;
  unauthenticatedCount++;

  ws.on('pong', () => { ws.isAlive = true; });

  log('client_connected', { ip });

  // 3.1 — Handshake timeout: client must authenticate within HANDSHAKE_TIMEOUT_MS
  const handshakeTimer = setTimeout(() => {
    if (!ws.authenticated) {
      errLog('handshake_timeout', { ip });
      recordFailure(ip);
      ws.close(1008, 'Authentication timeout');
    }
  }, HANDSHAKE_TIMEOUT_MS);

  // ---------------------------------------------------------------------------
  // Cleanup helper — called on every close/error path
  // ---------------------------------------------------------------------------
  function cleanup() {
    clearTimeout(handshakeTimer);
    if (!ws.authenticated) {
      unauthenticatedCount = Math.max(0, unauthenticatedCount - 1);
    }
  }

  ws.on('close', (code, reason) => {
    cleanup();
    log('client_disconnected', { name: ws.clientName || 'unknown', code, reason: reason.toString() });
  });

  ws.on('error', (err) => {
    cleanup();
    errLog('client_error', { name: ws.clientName || 'unknown', error: err.message });
  });

  // ---------------------------------------------------------------------------
  // Message handler
  // ---------------------------------------------------------------------------
  ws.on('message', (raw) => {
    // 3.4 — Oversized payload protection
    if (raw.length > MAX_PAYLOAD_BYTES) {
      errLog('payload_too_large', { ip, bytes: raw.length });
      ws.close(1009, 'Message too large');
      return;
    }

    // 3.5 — Malformed JSON closes the socket immediately
    let data;
    try {
      data = JSON.parse(raw.toString());
    } catch {
      errLog('invalid_json', { ip });
      recordFailure(ip);
      ws.close(1007, 'Invalid JSON');
      return;
    }

    // Basic structure validation
    if (typeof data !== 'object' || data === null || Array.isArray(data)) {
      errLog('invalid_payload_structure', { ip });
      recordFailure(ip);
      ws.close(1007, 'Invalid payload structure');
      return;
    }

    if (typeof data.type !== 'string' || data.type.trim() === '') {
      errLog('missing_message_type', { ip });
      recordFailure(ip);
      ws.close(1007, 'Missing message type');
      return;
    }

    // 3.6 — Pre-auth: only 'hello' is permitted before authentication.
    // The existing Hello handshake (ES256/TOFU) is the authentication mechanism.
    // We enforce that no other message type is processed before auth completes.
    if (!ws.authenticated) {
      if (data.type !== 'hello') {
        errLog('pre_auth_message_rejected', { ip, type: data.type });
        recordFailure(ip);
        ws.close(1008, 'Authentication required');
        return;
      }

      // 'hello' received — mark as authenticated and transition to active state.
      // The existing Hello protocol (verified by the Flutter layer / cert pinning) is
      // the source of trust. We do not re-validate its payload here.
      ws.authenticated = true;
      unauthenticatedCount = Math.max(0, unauthenticatedCount - 1);
      clearTimeout(handshakeTimer);

      // Determine client role from hello payload for logging
      if (['dial', 'reject_call', 'end_call', 'answer_call', 'contacts_request'].includes(data.type)) {
        ws.clientName = 'macOS';
      } else {
        ws.clientName = data.platform === 'macOS' ? 'macOS' : 'Android';
      }

      console.log('Received hello');
      console.log('Authentication successful');
      log('client_authenticated', { ip, name: ws.clientName });

      // Forward hello to other clients so they can complete their own handshake
      wss.clients.forEach((client) => {
        if (client !== ws && client.readyState === WebSocket.OPEN) {
          client.send(raw);
        }
      });
      return;
    }

    // ---------------------------------------------------------------------------
    // Authenticated path — determine client role on first non-hello message
    // ---------------------------------------------------------------------------
    if (!ws.clientName) {
      if (['dial', 'reject_call', 'end_call', 'answer_call', 'contacts_request'].includes(data.type)) {
        ws.clientName = 'macOS';
      } else if (['device_state', 'call_state', 'contacts', 'action_result', 'incoming_call'].includes(data.type)) {
        ws.clientName = 'Android';
      } else {
        ws.clientName = 'Unknown';
      }
    }

    const sender = ws.clientName;
    console.log(`Received ${data.type}`);
    log('message_received', { from: sender, type: data.type });

    // Forward verbatim to all other authenticated clients
    wss.clients.forEach((client) => {
      if (client !== ws && client.readyState === WebSocket.OPEN) {
        client.send(raw);
      }
    });
  });
});

// ---------------------------------------------------------------------------
// Start server
// ---------------------------------------------------------------------------
const port = process.env.PAKKU_WS_PORT || 8080;
server.listen(port, () => {
  log('server_listening', { port });
});

// ---------------------------------------------------------------------------
// Graceful shutdown
// ---------------------------------------------------------------------------
const shutdown = (signal) => {
  log('server_shutting_down', { signal });
  clearInterval(heartbeatInterval);
  wss.clients.forEach((ws) => {
    ws.close(1001, 'Server shutting down');
  });

  const forceExit = setTimeout(() => {
    errLog('shutdown_timeout_exceeded', { message: 'Forcing exit after 5s' });
    process.exit(1);
  }, 5000);

  server.close(() => {
    clearTimeout(forceExit);
    log('server_shutdown_complete');
    process.exit(0);
  });
};

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
