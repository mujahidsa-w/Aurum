'use strict';
// Room directory for dedicated-server rooms. Pure logic: no network, no
// processes; the clock and random source are injectable for tests.

const crypto = require('crypto');

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O, 1/I
const STATES = new Set(['starting', 'lobby', 'in_game', 'failed']);

function sanitizePlayerName(name) {
  // Same rule as the game client (UPUBGSessionSubsystem::SetDisplayName).
  const clean = String(name || '')
    .trim()
    .replace(/ /g, '_')
    .replace(/[^A-Za-z0-9_-]/g, '')
    .slice(0, 16);
  return clean || 'Player';
}

function sanitizeRoomName(name) {
  const clean = String(name || '').replace(/[\u0000-\u001f]/g, '').trim().slice(0, 24);
  return clean || 'Room';
}

function base64Url(buffer) {
  return Buffer.from(buffer).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/**
 * Ticket = base64url("roomId|playerName|expiresUnix") + "." + hex(HMAC-SHA1(secret, payload)).
 * Verified by the dedicated server in UPUBGRoomServiceSubsystem::VerifyTicketWithSecret.
 */
function makeTicket(secret, roomId, playerName, expiresUnix) {
  const payload = `${roomId}|${playerName}|${expiresUnix}`;
  const signature = crypto.createHmac('sha1', secret).update(payload, 'utf8').digest('hex');
  return `${base64Url(Buffer.from(payload, 'utf8'))}.${signature}`;
}

/** Reference implementation of the server-side check (mirrors the C++ code). */
function verifyTicket(ticket, secret, roomId, nowUnix) {
  const dot = String(ticket || '').indexOf('.');
  if (dot <= 0) return { ok: false, error: 'missing ticket' };
  const payloadB64 = ticket.slice(0, dot);
  const signature = ticket.slice(dot + 1).toLowerCase();
  const payload = Buffer.from(payloadB64.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
  const expected = crypto.createHmac('sha1', secret).update(payload).digest('hex');
  if (expected !== signature) return { ok: false, error: 'bad signature' };
  const parts = payload.toString('utf8').split('|');
  if (parts.length !== 3) return { ok: false, error: 'bad payload' };
  if (parts[0] !== roomId) return { ok: false, error: 'other room' };
  if (nowUnix > Number(parts[2])) return { ok: false, error: 'expired' };
  return { ok: true, playerName: parts[1] };
}

function hashPassword(password, salt) {
  return crypto.scryptSync(String(password), salt, 32);
}

class RoomStore {
  constructor(options = {}) {
    this.now = options.now || (() => Date.now());
    this.random = options.random || ((n) => crypto.randomBytes(n));
    this.maxRooms = options.maxRooms || 10;
    this.maxPlayersLimit = options.maxPlayersLimit || 16;
    this.startTimeoutMs = options.startTimeoutMs || 60_000;
    this.heartbeatTimeoutMs = options.heartbeatTimeoutMs || 30_000;
    this.idleTimeoutMs = options.idleTimeoutMs || 300_000;
    this.ticketTtlSeconds = options.ticketTtlSeconds || 60;
    this.mapNames = options.mapNames || ['Test', 'Battle'];
    this.rooms = new Map(); // id -> room
  }

  _newCode() {
    for (let attempt = 0; attempt < 50; attempt++) {
      const bytes = this.random(6);
      let code = '';
      for (let i = 0; i < 6; i++) code += CODE_ALPHABET[bytes[i] % CODE_ALPHABET.length];
      if (![...this.rooms.values()].some((r) => r.code === code)) return code;
    }
    throw new Error('could not allocate a unique room code');
  }

  create({ name, maxPlayers, password, mapIndex, hostName } = {}) {
    if (this.rooms.size >= this.maxRooms) {
      const err = new Error('The server is full, try again later.');
      err.status = 503;
      throw err;
    }
    const id = this.random(8).toString('hex');
    const room = {
      id,
      code: this._newCode(),
      name: sanitizeRoomName(name),
      hostName: sanitizePlayerName(hostName),
      maxPlayers: Math.min(Math.max(parseInt(maxPlayers, 10) || 8, 2), this.maxPlayersLimit),
      mapIndex: Math.max(parseInt(mapIndex, 10) || 0, 0),
      players: 0,
      state: 'starting',
      secret: this.random(24).toString('hex'),
      salt: null,
      passwordHash: null,
      address: null,
      port: null,
      createdAt: this.now(),
      lastHeartbeat: null,
      emptySince: null,
    };
    if (password) {
      room.salt = this.random(16);
      room.passwordHash = hashPassword(password, room.salt);
    }
    this.rooms.set(id, room);
    return room;
  }

  get(idOrCode) {
    const key = String(idOrCode || '').trim();
    if (this.rooms.has(key)) return this.rooms.get(key);
    const upper = key.toUpperCase();
    return [...this.rooms.values()].find((r) => r.code === upper) || null;
  }

  remove(id) {
    return this.rooms.delete(id);
  }

  publicView(room) {
    return {
      id: room.id,
      code: room.code,
      name: room.name,
      hostName: room.hostName,
      players: room.players,
      maxPlayers: room.maxPlayers,
      hasPassword: Boolean(room.passwordHash),
      state: room.state,
      map: this.mapNames[room.mapIndex] || this.mapNames[0],
    };
  }

  list() {
    return [...this.rooms.values()].filter((r) => r.state !== 'failed').map((r) => this.publicView(r));
  }

  checkPassword(room, password) {
    if (!room.passwordHash) return true;
    const candidate = hashPassword(password || '', room.salt);
    return crypto.timingSafeEqual(candidate, room.passwordHash);
  }

  /** Returns { status, body } for POST /rooms/:id/join. */
  join(idOrCode, { playerName, password } = {}) {
    const room = this.get(idOrCode);
    if (!room || room.state === 'failed') return { status: 404, body: { error: 'Room not found.' } };
    if (room.state === 'starting' || !room.address) return { status: 409, body: { error: 'The room server is still starting.' } };
    if (room.state === 'in_game') return { status: 409, body: { error: 'The match is already in progress.' } };
    if (room.players >= room.maxPlayers) return { status: 409, body: { error: 'The room is full.' } };
    if (!this.checkPassword(room, password)) return { status: 403, body: { error: 'Wrong room password.' } };
    const name = sanitizePlayerName(playerName);
    const expires = Math.floor(this.now() / 1000) + this.ticketTtlSeconds;
    return { status: 200, body: { address: room.address, ticket: makeTicket(room.secret, room.id, name, expires) } };
  }

  /** Called by the dedicated server (authenticated with the room secret). */
  heartbeat(id, secret, { players, state } = {}) {
    const room = this.rooms.get(id);
    if (!room) return { status: 404, body: { error: 'Room not found.' } };
    if (!secret || secret.length !== room.secret.length ||
        !crypto.timingSafeEqual(Buffer.from(secret), Buffer.from(room.secret))) {
      return { status: 401, body: { error: 'Bad room secret.' } };
    }
    const nextState = STATES.has(state) && state !== 'starting' && state !== 'failed' ? state : 'lobby';
    room.players = Math.min(Math.max(parseInt(players, 10) || 0, 0), room.maxPlayers);
    room.state = nextState;
    room.lastHeartbeat = this.now();
    room.emptySince = room.players === 0 ? (room.emptySince ?? this.now()) : null;
    return { status: 200, body: { ok: true } };
  }

  /** Returns the rooms that must be shut down (and removes them). */
  collectExpired() {
    const now = this.now();
    const expired = [];
    for (const room of this.rooms.values()) {
      const startingTooLong = room.state === 'starting' && now - room.createdAt > this.startTimeoutMs;
      const silent = room.lastHeartbeat !== null && now - room.lastHeartbeat > this.heartbeatTimeoutMs;
      const idle = room.emptySince !== null && now - room.emptySince > this.idleTimeoutMs;
      if (startingTooLong || silent || idle || room.state === 'failed') expired.push(room);
    }
    for (const room of expired) this.rooms.delete(room.id);
    return expired;
  }
}

module.exports = { RoomStore, makeTicket, verifyTicket, sanitizePlayerName, sanitizeRoomName, base64Url, CODE_ALPHABET };
