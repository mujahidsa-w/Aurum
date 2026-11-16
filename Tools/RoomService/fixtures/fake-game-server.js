#!/usr/bin/env node
'use strict';
// Stands in for PUBG_BlueprintServer in the integration test. It parses the same
// command line the room service passes to the real server and sends the same
// heartbeats as UPUBGRoomServiceSubsystem::HeartbeatTick (POST
// /rooms/:id/heartbeat, header X-Room-Secret, body { players, state }).
const http = require('http');

const args = process.argv.slice(2);
const arg = (name) => {
  const hit = args.find((a) => a.startsWith(`-${name}=`));
  return hit ? hit.slice(name.length + 2) : '';
};
const service = new URL(arg('RoomService'));
const roomId = arg('RoomId');
const secret = arg('RoomSecret');
const players = Number(process.env.FAKE_PLAYERS || 0);

// Echo the URL so the test can check the arguments.
console.log(`URL ${args[0]}`);
console.log(`PORT ${arg('port')} CODE ${arg('RoomCode')}`);

function beat() {
  const body = JSON.stringify({ players, state: 'lobby' });
  const req = http.request({
    hostname: service.hostname, port: service.port, method: 'POST',
    path: `/rooms/${roomId}/heartbeat`,
    headers: { 'Content-Type': 'application/json', 'X-Room-Secret': secret, 'Content-Length': Buffer.byteLength(body) },
  }, (res) => res.resume());
  req.on('error', () => {});
  req.end(body);
}
beat();
const timer = setInterval(beat, 200);
process.on('SIGTERM', () => { clearInterval(timer); process.exit(0); });
