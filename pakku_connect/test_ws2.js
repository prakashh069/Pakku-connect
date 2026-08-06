const WebSocket = require('ws');
const ws = new WebSocket('wss://127.0.0.1:8080', { rejectUnauthorized: false });

ws.on('open', () => {
  ws.send(JSON.stringify({ type: 'hello', deviceName: 'TestAndroid', platform: 'android' }));
  
  for (let i = 1; i <= 5; i++) {
    setTimeout(() => {
      ws.send(JSON.stringify({
        schemaVersion: 1,
        type: 'share.clipboard',
        payload: { id: `msg${i}`, text: `Item ${i}`, deviceName: 'TestAndroid' }
      }));
      console.log(`Sent Item ${i}`);
    }, i * 100);
  }
  
  setTimeout(() => process.exit(0), 1000);
});
