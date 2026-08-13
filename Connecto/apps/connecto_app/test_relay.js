const WebSocket = require('ws');
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0'; // Trust self-signed cert for testing

const ws1 = new WebSocket('wss://127.0.0.1:8080');
const ws2 = new WebSocket('wss://127.0.0.1:8080');

ws1.on('open', () => {
  console.log('WS1 connected');
  ws1.send(JSON.stringify({ type: 'incoming_call', phoneNumber: '123456789' }));
  
  // Test invalid payload
  ws1.send('invalid json');

  // Test invalid object
  ws1.send(JSON.stringify([{ type: 'test' }]));

  // Test missing type
  ws1.send(JSON.stringify({ notype: true }));
});

ws2.on('open', () => {
  console.log('WS2 connected');
});

ws2.on('message', (msg) => {
  console.log('WS2 received:', msg.toString());
});

ws1.on('message', (msg) => {
  console.log('WS1 received:', msg.toString());
});

setTimeout(() => {
  ws1.close();
  ws2.close();
}, 2000);
