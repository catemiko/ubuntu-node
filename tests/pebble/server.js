'use strict';

const http = require('node:http');
const server = http.createServer((req, res) => {
  if (req.url !== '/health') {
    res.writeHead(404);
    res.end('not found');
    return;
  }
  res.writeHead(200, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ status: 'ok', uid: process.getuid(), pid: process.pid }));
});

server.listen(18080, '127.0.0.1');
process.on('SIGTERM', () => server.close());
