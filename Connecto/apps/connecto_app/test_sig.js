const crypto = require('crypto');
const hmacSecret = 'test_secret_123';
const data = 'test.data';

const expectedSig = crypto
  .createHmac('sha256', hmacSecret)
  .update(data)
  .digest('base64url');
console.log(`Node: ${expectedSig}`);
