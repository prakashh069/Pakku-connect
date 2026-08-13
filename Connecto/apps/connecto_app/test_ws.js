const WebSocket = require('ws');
const ws = new WebSocket('wss://127.0.0.1:8080', { rejectUnauthorized: false });

ws.on('open', () => {
  console.log('Connected');
  ws.send(JSON.stringify({ type: 'hello', deviceName: 'TestAndroid', platform: 'android' }));
  
  // Send first item
  ws.send(JSON.stringify({
    schemaVersion: 1,
    type: 'share.clipboard',
    payload: { id: 'msg1', text: 'First item', deviceName: 'TestAndroid' }
  }));
  console.log('Sent First item');

  // Send second item 100ms later
  setTimeout(() => {
    ws.send(JSON.stringify({
      schemaVersion: 1,
      type: 'share.clipboard',
      payload: { id: 'msg2', text: 'Second item', deviceName: 'TestAndroid' }
    }));
    console.log('Sent Second item');
    process.exit(0);
  }, 100);
});
