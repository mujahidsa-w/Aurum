'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { RoomStore, makeTicket, verifyTicket, sanitizePlayerName, CODE_ALPHABET } = require('../src/rooms');

function makeStore(overrides = {}) {
  let t = 1_000_000;
  const clock = { now: () => t, advance: (ms) => { t += ms; } };
  const store = new RoomStore({ now: clock.now, ...overrides });
  return { store, clock };
}

function activate(store, room, players = 0) {
  room.address = '203.0.113.5:7777';
  return store.heartbeat(room.id, room.secret, { players, state: 'lobby' });
}

test('create sanitizes input and clamps max players', () => {
  const { store } = makeStore({ maxPlayersLimit: 16 });
  const room = store.create({ name: '  Night\u0001 Squad that is way too long for the list  ', maxPlayers: 99, hostName: 'Bad|Name<>' });
  assert.equal(room.name.length <= 24, true);
  assert.equal(room.name.includes('\u0001'), false);
  assert.equal(room.maxPlayers, 16);
  assert.equal(room.hostName, 'BadName');
  assert.equal(room.state, 'starting');
  assert.match(room.code, new RegExp(`^[${CODE_ALPHABET}]{6}$`));
  assert.equal(store.create({ maxPlayers: 1 }).maxPlayers, 2);
});

test('room codes are unique and lookup works by id or code (case-insensitive)', () => {
  const { store } = makeStore({ maxRooms: 200 });
  const codes = new Set();
  for (let i = 0; i < 150; i++) codes.add(store.create({}).code);
  assert.equal(codes.size, 150);
  const room = store.create({ name: 'x' });
  assert.equal(store.get(room.id), room);
  assert.equal(store.get(room.code.toLowerCase()), room);
  assert.equal(store.get('nope'), null);
});

test('max rooms is enforced', () => {
  const { store } = makeStore({ maxRooms: 2 });
  store.create({});
  store.create({});
  assert.throws(() => store.create({}), (e) => e.status === 503);
});

test('join: starting rooms, wrong password, full rooms, in-game rooms', () => {
  const { store } = makeStore();
  const room = store.create({ name: 'Locked', password: 'hunter2', maxPlayers: 2 });
  assert.equal(store.join(room.id, { playerName: 'A', password: 'hunter2' }).status, 409); // still starting
  activate(store, room, 0);
  assert.equal(store.join(room.code, { playerName: 'A', password: 'wrong' }).status, 403);
  assert.equal(store.join(room.code, { playerName: 'A' }).status, 403);
  const ok = store.join(room.code, { playerName: 'A', password: 'hunter2' });
  assert.equal(ok.status, 200);
  assert.equal(ok.body.address, '203.0.113.5:7777');
  activate(store, room, 2);
  assert.equal(store.join(room.code, { playerName: 'B', password: 'hunter2' }).status, 409); // full
  store.heartbeat(room.id, room.secret, { players: 1, state: 'in_game' });
  assert.equal(store.join(room.code, { playerName: 'B', password: 'hunter2' }).status, 409); // running
  assert.equal(store.join('missing', {}).status, 404);
});

test('public view never leaks secrets or password data', () => {
  const { store } = makeStore();
  const room = store.create({ password: 'p' });
  const view = JSON.stringify(store.list());
  assert.equal(view.includes(room.secret), false);
  assert.equal(view.includes('salt'), false);
  assert.equal(view.includes('passwordHash'), false);
  assert.equal(store.list()[0].hasPassword, true);
});

test('tickets: valid, tampered, other room, expired', () => {
  const { store, clock } = makeStore({ ticketTtlSeconds: 60 });
  const room = store.create({});
  activate(store, room);
  const { ticket } = store.join(room.id, { playerName: 'Neo Smith' }).body;
  const now = Math.floor(clock.now() / 1000);
  const good = verifyTicket(ticket, room.secret, room.id, now);
  assert.deepEqual(good, { ok: true, playerName: 'Neo_Smith' });
  assert.equal(verifyTicket(ticket, 'other-secret', room.id, now).ok, false);
  assert.equal(verifyTicket(ticket, room.secret, 'other-room', now).ok, false);
  assert.equal(verifyTicket(ticket, room.secret, room.id, now + 61).ok, false);
  const [payload, sig] = ticket.split('.');
  const tampered = Buffer.from(payload.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString().replace('Neo_Smith', 'Admin');
  const forged = `${Buffer.from(tampered).toString('base64url')}.${sig}`;
  assert.equal(verifyTicket(forged, room.secret, room.id, now).ok, false);
  assert.equal(verifyTicket('', room.secret, room.id, now).ok, false);
});

test('heartbeat requires the room secret and updates state', () => {
  const { store } = makeStore();
  const room = store.create({ maxPlayers: 8 });
  assert.equal(store.heartbeat(room.id, 'bad', { players: 3 }).status, 401);
  assert.equal(store.heartbeat(room.id, undefined, { players: 3 }).status, 401);
  assert.equal(store.heartbeat(room.id, room.secret, { players: 99, state: 'in_game' }).status, 200);
  assert.equal(room.players, 8);
  assert.equal(room.state, 'in_game');
  store.heartbeat(room.id, room.secret, { players: 1, state: 'failed' });
  assert.equal(room.state, 'lobby'); // a server cannot mark itself failed / starting
});

test('expiry: server never started, server went silent, room idle', () => {
  const { store, clock } = makeStore({ startTimeoutMs: 1000, heartbeatTimeoutMs: 1000, idleTimeoutMs: 5000 });
  const neverStarted = store.create({ name: 'a' });
  const silent = store.create({ name: 'b' });
  const idle = store.create({ name: 'c' });
  const busy = store.create({ name: 'd' });
  activate(store, silent, 1);
  activate(store, idle, 0);
  activate(store, busy, 2);
  clock.advance(1500);
  activate(store, idle, 0);
  activate(store, busy, 2);
  const expired1 = store.collectExpired().map((r) => r.name).sort();
  assert.deepEqual(expired1, ['a', 'b']);
  clock.advance(900);
  activate(store, idle, 0);
  activate(store, busy, 2);
  clock.advance(900);
  activate(store, idle, 0);
  activate(store, busy, 2);
  clock.advance(900);
  activate(store, idle, 0);
  activate(store, busy, 2);
  clock.advance(900);
  activate(store, idle, 0);
  activate(store, busy, 2);
  clock.advance(900);
  activate(store, idle, 0);
  activate(store, busy, 2);
  assert.deepEqual(store.collectExpired().map((r) => r.name), ['c']);
  assert.deepEqual(store.list().map((r) => r.name), ['d']);
  assert.equal(neverStarted.state, 'starting');
});

test('player names follow the game client rules', () => {
  assert.equal(sanitizePlayerName('  John Doe  '), 'John_Doe');
  assert.equal(sanitizePlayerName('a|b?c=d'), 'abcd');
  assert.equal(sanitizePlayerName(''), 'Player');
  assert.equal(sanitizePlayerName('x'.repeat(40)).length, 16);
});

test('makeTicket output has no padding and only url-safe characters', () => {
  const t = makeTicket('s', 'r', 'p', 1);
  assert.match(t, /^[A-Za-z0-9_-]+\.[0-9a-f]{40}$/);
});
