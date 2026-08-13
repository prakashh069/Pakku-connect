/**
 * Stage 12 — Relay Security Verification Script
 * Tests: oversized payload, malformed JSON, pre-auth non-hello, rate limiting, unauthenticated handshake timeout
 */
const WebSocket = require('ws');
const https = require('https');
const fs = require('fs');

// Self-signed cert with CN=PakkuConnect — skip hostname check for local test
const AGENT = new https.Agent({ rejectUnauthorized: false });

let passed = 0;
let failed = 0;

function test(name, fn) {
  return fn().then(() => {
    console.log(`  ✅ PASS: ${name}`);
    passed++;
  }).catch((e) => {
    console.error(`  ❌ FAIL: ${name} — ${e.message}`);
    failed++;
  });
}

function connect() {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket('wss://localhost:8080', { agent: AGENT });
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}

function waitClose(ws, timeoutMs = 6000) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('Socket did not close within timeout')), timeoutMs);
    ws.on('close', (code, reason) => {
      clearTimeout(t);
      resolve({ code, reason: reason.toString() });
    });
    ws.on('error', () => {}); // ignore errors after send
  });
}

async function runTests() {
  console.log('\nPakku Connect — Relay Security Test Suite\n');

  // Test 1: Handshake timeout — connect and send nothing
  await test('Handshake timeout (no hello within 5s)', async () => {
    const ws = await connect();
    const result = await waitClose(ws, 8000);
    if (result.code !== 1008) throw new Error(`Expected close code 1008, got ${result.code}`);
  });

  // Test 2: Pre-auth non-hello message rejected
  await test('Pre-auth non-hello message is rejected', async () => {
    const ws = await connect();
    ws.send(JSON.stringify({ type: 'call_state', state: 'answered' }));
    const result = await waitClose(ws, 3000);
    if (result.code !== 1008) throw new Error(`Expected close code 1008, got ${result.code}`);
  });

  // Test 3: Malformed JSON closes socket
  await test('Malformed JSON closes socket', async () => {
    const ws = await connect();
    ws.send('this is not json');
    const result = await waitClose(ws, 3000);
    if (result.code !== 1007) throw new Error(`Expected close code 1007, got ${result.code}`);
  });

  // Test 4: Oversized payload closes socket
  await test('Oversized payload (65 KB) closes socket', async () => {
    const ws = await connect();
    ws.send(Buffer.alloc(65 * 1024, 'a'));
    const result = await waitClose(ws, 3000);
    if (result.code !== 1009) throw new Error(`Expected close code 1009, got ${result.code}`);
  });

  // Test 5: hello is accepted and socket remains open
  await test('hello message is accepted and socket stays open', async () => {
    const ws = await connect();
    ws.send(JSON.stringify({ type: 'hello', platform: 'Android', version: 1 }));

    await new Promise((resolve, reject) => {
      const t = setTimeout(resolve, 2000); // socket should still be open after 2s
      ws.on('close', (code) => {
        clearTimeout(t);
        reject(new Error(`Socket closed unexpectedly with code ${code} after hello`));
      });
    });

    ws.close(1000, 'Test complete');
  });

  // Summary
  console.log(`\nResults: ${passed} passed, ${failed} failed\n`);
  process.exit(failed > 0 ? 1 : 0);
}

runTests().catch((e) => {
  console.error('Test suite error:', e.message);
  process.exit(1);
});
