'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');

assert.equal(process.versions.node.split('.')[0], '24', 'Node.js major version');
assert.equal(process.arch, process.env.EXPECTED_ARCH, 'target CPU architecture');
assert.equal(process.getuid(), 584792, 'non-root UID');
assert.equal(process.getgid(), 584792, 'non-root GID');
assert.equal(process.env.HOME, '/tmp', 'non-root home');
assert.match(fs.readFileSync('/etc/passwd', 'utf8'), /^_daemon_:x:584792:584792::\/tmp:\/usr\/sbin\/nologin$/m);
assert.match(fs.readFileSync('/etc/group', 'utf8'), /^_daemon_:x:584792:$/m);
assert.equal(fs.statSync('/tmp').mode & 0o7777, 0o1777, 'sticky /tmp permissions');
assert.match(fs.readFileSync('/etc/os-release', 'utf8'), /^VERSION_ID="?24\.04"?$/m);
assert.ok(fs.statSync('/etc/ssl/certs/ca-certificates.crt').size > 1000, 'Ubuntu CA bundle');
assert.equal(fs.existsSync('/bin/sh'), false, 'no shell');
assert.equal(fs.existsSync('/usr/bin/apt'), false, 'no apt');
assert.equal(fs.existsSync('/usr/local/bin/npm'), false, 'no npm');
assert.ok(fs.statSync('/usr/bin/pebble').isFile(), 'Pebble binary installed');
assert.equal(process.env.PEBBLE, '/var/lib/pebble/default', 'Pebble config directory');
assert.equal(process.env.PEBBLE_COPY_ONCE, '/usr/share/pebble', 'Immutable Pebble layer seed directory');
assert.ok(fs.statSync('/usr/share/pebble/layers').isDirectory(), 'Pebble seed layers directory exists');
assert.ok(fs.statSync('/var/lib/pebble/default').isDirectory(), 'Writable Pebble runtime directory exists');
assert.equal(process.env.PEBBLE_SOCKET, '/tmp/.pebble.socket', 'Pebble runtime socket');
assert.equal(process.env.PEBBLE_PERSIST, 'never', 'read-only runtime state');
assert.equal(fs.readFileSync('/proc/1/comm', 'utf8').trim(), 'pebble', 'Pebble is PID 1');

console.log(JSON.stringify({
  status: 'ok',
  node: process.version,
  arch: process.arch,
  uid: process.getuid(),
  gid: process.getgid(),
  ubuntu: '24.04',
  pid1: 'pebble',
}));
