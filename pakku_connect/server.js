const fs = require('fs');
const https = require('https');
const WebSocket = require('ws');
require('dotenv').config();

// Logger helper for structured logging
const log = (event, details = {}) => {
  console.log(JSON.stringify({ timestamp: new Date().toISOString(), event, ...details }));
};

const errLog = (event, details = {}) => {
  console.error(JSON.stringify({ timestamp: new Date().toISOString(), event, ...details }));
};

// TLS setup
let cert, key;
try {
  cert = fs.readFileSync('certs/device.crt');
  key = fs.readFileSync('certs/device.key');
} catch (e) {
  errLog('tls_cert_read_failed', { error: e.message });
  process.exit(1);
}

const server = https.createServer({ cert, key });
const wss = new WebSocket.Server({ server });

// Stale connection cleanup (Ping/Pong heartbeat)
const noop = () => {};
const heartbeatInterval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (ws.isAlive === false) {
      log('client_terminated_stale');
      return ws.terminate();
    }
    ws.isAlive = false;
    ws.ping(noop);
  });
}, 30000);

wss.on('connection', (ws, req) => {
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });

  log('client_connected', { ip: req.socket.remoteAddress });

  ws.on('message', (raw) => {
    let data;
    try {
      data = JSON.parse(raw.toString());
    } catch (e) {
      errLog('invalid_payload_rejected', { reason: 'not_json' });
      ws.send(JSON.stringify({ type: 'error', payload: 'Invalid JSON' }));
      return;
    }

    // Validate structure (must be object with string type)
    if (typeof data !== 'object' || data === null || Array.isArray(data)) {
      errLog('invalid_payload_rejected', { reason: 'not_object' });
      return;
    }

    if (typeof data.type !== 'string' || data.type.trim() === '') {
      errLog('invalid_payload_rejected', { reason: 'missing_or_invalid_type' });
      return;
    }

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

    console.log(`\n[${new Date().toISOString()}] SERVER RECEIVED from ${sender}:\n${raw.toString()}\n`);

    // Forward verbatim (raw) to all other connected clients
    wss.clients.forEach((client) => {
      if (client !== ws && client.readyState === WebSocket.OPEN) {
        const receiver = client.clientName || (sender === 'macOS' ? 'Android' : 'macOS');
        console.log(`[${new Date().toISOString()}] SERVER FORWARDED to ${receiver}:\n${raw.toString()}\n`);
        client.send(raw);
      }
    });
  });

  ws.on('close', (code, reason) => {
    log('client_disconnected', { code, reason: reason.toString() });
  });

  ws.on('error', (err) => {
    errLog('client_error', { error: err.message });
  });
});

const port = process.env.PAKKU_WS_PORT || 8080;
server.listen(port, () => {
  log('server_listening', { port });
});

// Graceful shutdown
const shutdown = (signal) => {
  log('server_shutting_down', { signal });
  clearInterval(heartbeatInterval);
  wss.clients.forEach((ws) => {
    ws.close(1001, 'Server shutting down');
  });
  
  // Bounded shutdown timeout to prevent indefinite wait
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
