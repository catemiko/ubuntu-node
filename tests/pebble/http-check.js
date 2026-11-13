'use strict';

const assert = require('node:assert/strict');
const http = require('node:http');

http.get('http://127.0.0.1:18080/health', (response) => {
  assert.equal(response.statusCode, 200);
  let data = '';
  response.setEncoding('utf8');
  response.on('data', (chunk) => { data += chunk; });
  response.on('end', () => {
    const body = JSON.parse(data);
    assert.equal(body.status, 'ok');
    assert.equal(body.uid, 584792);
    console.log('Pebble-managed service HTTP health endpoint: OK');
  });
}).on('error', (error) => {
  console.error(error);
  process.exitCode = 1;
});
