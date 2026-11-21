'use strict';
// End-to-end: real HTTP server + a spawned "game server" process.
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const { createService } = require('../src/server');
const { verifyTicket } = require('../src/rooms');

const FAKE_SERVER = path.join(__dirname, '..', 'fixtures', 'fake-game-server.js');

async function startService(overrides = {}) {
  const logs = [];
  const logger = { log: (m) => logs.push(String(m)), error: (m) => logs.push(String(m)) };
  const config = {
    port: 0,
    publicHost: 'game.example.test',
    serviceUrl: '',
    serverBinary: process.execPath,
    serverArgs: [],
    lobbyMap: '/Game/Maps/Level_Test',
    mapNames: ['Test', 'Battle'],
    portMin: 7777,
    portMax: 7778,
    maxRooms: 5,
    maxPlayersLimit: 16,
    startTimeoutMs: 5000,
    heartbeatTimeoutMs: 1000,
    idleTimeoutMs: 60_000,
    sweepIntervalMs: 100,
    createPerMinute: 3,
    joinPerMinute: 30,
    ...overrides,
  };
  const service = createService(config, logger);
  await new Promise((resolve) => service.server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${service.server.address().port}`;
  config.serviceUrl = base;
  // The launcher runs `node fake-game-server.js <args>`: prepend the script.
  const originalBuild = service.launcher.buildArgs.bind(service.launcher);
  service.launcher.buildArgs = (room, port) => [FAKE_SERVER, ...originalBuild(room, port)];
  return { ...service, base, logs };
}

async function request(base, method, route, body, headers = {}) {
  const res = await fetch(base + route, {
    method,
    headers: { 'Content-Type': 'application/json', ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : undefined };
}

async function waitFor(predicate, timeoutMs = 5000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await predicate()) return true;
    await new Promise((r) => setTimeout(r, 50));
  }
  return false;
}

test('create -> server starts and heartbeats -> join with ticket -> delete', async (t) => {
  const svc = await startService();
  t.after(() => new Promise((r) => svc.server.close(r)));

  assert.equal((await request(svc.base, 'GET', '/health')).body.ok, true);

  const created = await request(svc.base, 'POST', '/rooms', { name: 'Friday Night', maxPlayers: 4, password: 'pw', mapIndex: 1, hostName: 'Host One' });
  assert.equal(created.status, 201);
  assert.equal(created.body.state, 'starting');
  assert.equal(created.body.map, 'Battle');
  assert.equal(created.body.hasPassword, true);
  const { id, code } = created.body;

  // Joining before the server reported in is refused.
  assert.equal((await request(svc.base, 'POST', `/rooms/${code}/join`, { playerName: 'P1', password: 'pw' })).status, 409);

  // The spawned process heartbeats -> room becomes joinable.
  assert.equal(await waitFor(async () => (await request(svc.base, 'GET', `/rooms/${id}`)).body.state === 'lobby'), true);

  // The command line given to the game server.
  const urlLine = svc.logs.find((l) => l.includes('URL '));
  assert.ok(urlLine.includes('/Game/Maps/Level_Test?game=Lobby?RoomName=Friday%20Night?MaxPlayers=4?BattleMap=1'), urlLine);
  assert.ok(svc.logs.some((l) => l.includes(`PORT 7777 CODE ${code}`)));

  assert.equal((await request(svc.base, 'POST', `/rooms/${code}/join`, { playerName: 'P1', password: 'nope' })).status, 403);
  const joined = await request(svc.base, 'POST', `/rooms/${code.toLowerCase()}/join`, { playerName: 'P1', password: 'pw' });
  assert.equal(joined.status, 200);
  assert.equal(joined.body.address, 'game.example.test:7777');
  const room = svc.store.get(id);
  assert.equal(verifyTicket(joined.body.ticket, room.secret, id, Math.floor(Date.now() / 1000)).ok, true);

  // List does not expose secrets.
  const list = await request(svc.base, 'GET', '/rooms');
  assert.equal(list.body.rooms.length, 1);
  assert.equal(JSON.stringify(list.body).includes(room.secret), false);

  // Heartbeat / delete need the secret.
  assert.equal((await request(svc.base, 'POST', `/rooms/${id}/heartbeat`, { players: 1 }, { 'X-Room-Secret': 'wrong' })).status, 401);
  assert.equal((await request(svc.base, 'DELETE', `/rooms/${id}`, undefined, { 'X-Room-Secret': 'wrong' })).status, 401);
  assert.equal((await request(svc.base, 'DELETE', `/rooms/${id}`, undefined, { 'X-Room-Secret': room.secret })).status, 204);
  assert.equal(await waitFor(() => svc.launcher.processes.size === 0), true);
  assert.equal((await request(svc.base, 'GET', `/rooms/${id}`)).status, 404);
});

test('a server that stops heartbeating is removed', async (t) => {
  const svc = await startService();
  t.after(() => new Promise((r) => svc.server.close(r)));
  const created = await request(svc.base, 'POST', '/rooms', { name: 'Crash test' });
  const { id } = created.body;
  assert.equal(await waitFor(async () => (await request(svc.base, 'GET', `/rooms/${id}`)).body.state === 'lobby'), true);
  // Simulate a crash: kill the process without telling the service.
  const entry = svc.launcher.processes.get(id);
  entry.child.kill('SIGKILL');
  assert.equal(await waitFor(async () => (await request(svc.base, 'GET', `/rooms/${id}`)).status === 404), true);
});

test('port pool, rate limit, bad JSON and missing binary', async (t) => {
  const svc = await startService();
  t.after(() => new Promise((r) => svc.server.close(r)));
  assert.equal((await request(svc.base, 'POST', '/rooms', {})).status, 201);
  assert.equal((await request(svc.base, 'POST', '/rooms', {})).status, 201);
  const third = await request(svc.base, 'POST', '/rooms', {});
  assert.equal(third.status, 503); // only ports 7777-7778
  assert.equal((await request(svc.base, 'POST', '/rooms', {})).status, 429); // 3 creates per minute

  const res = await fetch(`${svc.base}/rooms/x/join`, { method: 'POST', body: '{bad json' });
  assert.equal(res.status, 400);
  assert.equal((await request(svc.base, 'POST', '/rooms/unknown/join', { playerName: 'a' })).status, 404);
  assert.equal((await request(svc.base, 'GET', '/nothing')).status, 404);
});

test('room creation fails cleanly when no server binary is configured', async (t) => {
  const svc = await startService({ serverBinary: '' });
  t.after(() => new Promise((r) => svc.server.close(r)));
  const res = await request(svc.base, 'POST', '/rooms', { name: 'x' });
  assert.equal(res.status, 503);
  assert.match(res.body.error, /SERVER_BINARY/);
  assert.equal((await request(svc.base, 'GET', '/rooms')).body.rooms.length, 0);
});
