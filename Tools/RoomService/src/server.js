'use strict';
// HTTP API used by the game (UPUBGRoomServiceSubsystem).
//
//   GET    /health
//   GET    /rooms                      list rooms
//   POST   /rooms                      create a room (starts a dedicated server)
//   GET    /rooms/:idOrCode            one room
//   POST   /rooms/:idOrCode/join       { playerName, password } -> { address, ticket }
//   POST   /rooms/:id/heartbeat        game server -> service (header X-Room-Secret)
//   DELETE /rooms/:id                  game server shuts the room down (X-Room-Secret)

const http = require('http');
const { RoomStore } = require('./rooms');
const { ServerLauncher } = require('./launcher');

const MAX_BODY = 16 * 1024;

class RateLimiter {
  constructor(limit, windowMs, now = () => Date.now()) {
    this.limit = limit;
    this.windowMs = windowMs;
    this.now = now;
    this.hits = new Map();
  }
  allow(key) {
    const t = this.now();
    const list = (this.hits.get(key) || []).filter((x) => t - x < this.windowMs);
    if (list.length >= this.limit) {
      this.hits.set(key, list);
      return false;
    }
    list.push(t);
    this.hits.set(key, list);
    return true;
  }
}

function send(res, status, body) {
  const payload = body === undefined ? '' : JSON.stringify(body);
  res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  res.end(payload);
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY) {
        reject(Object.assign(new Error('Body too large.'), { status: 413 }));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      if (chunks.length === 0) return resolve({});
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch (e) {
        reject(Object.assign(new Error('Invalid JSON.'), { status: 400 }));
      }
    });
    req.on('error', reject);
  });
}

function createService(config, logger = console) {
  const store = new RoomStore({
    maxRooms: config.maxRooms,
    maxPlayersLimit: config.maxPlayersLimit,
    startTimeoutMs: config.startTimeoutMs,
    heartbeatTimeoutMs: config.heartbeatTimeoutMs,
    idleTimeoutMs: config.idleTimeoutMs,
    mapNames: config.mapNames,
  });
  const launcher = new ServerLauncher(config, logger);
  launcher.onExit = (roomId) => store.remove(roomId);
  const createLimiter = new RateLimiter(config.createPerMinute || 5, 60_000);
  const joinLimiter = new RateLimiter(config.joinPerMinute || 30, 60_000);

  async function handle(req, res) {
    const url = new URL(req.url, 'http://localhost');
    const parts = url.pathname.split('/').filter(Boolean).map(decodeURIComponent);
    const ip = req.socket.remoteAddress || 'unknown';
    try {
      if (req.method === 'GET' && parts.length === 1 && parts[0] === 'health') {
        return send(res, 200, { ok: true, rooms: store.rooms.size, launcher: launcher.enabled });
      }
      if (parts[0] !== 'rooms') return send(res, 404, { error: 'Not found.' });

      if (parts.length === 1 && req.method === 'GET') {
        return send(res, 200, { rooms: store.list() });
      }
      if (parts.length === 1 && req.method === 'POST') {
        if (!createLimiter.allow(ip)) return send(res, 429, { error: 'Too many rooms created, wait a minute.' });
        const body = await readJson(req);
        const room = store.create(body);
        try {
          launcher.start(room);
        } catch (e) {
          store.remove(room.id);
          throw e;
        }
        return send(res, 201, store.publicView(room));
      }

      const room = store.get(parts[1]);
      if (parts.length === 2 && req.method === 'GET') {
        return room ? send(res, 200, store.publicView(room)) : send(res, 404, { error: 'Room not found.' });
      }
      if (parts.length === 2 && req.method === 'DELETE') {
        if (!room) return send(res, 404, { error: 'Room not found.' });
        const auth = store.heartbeat(room.id, req.headers['x-room-secret'], { players: room.players, state: room.state });
        if (auth.status !== 200) return send(res, auth.status, auth.body);
        launcher.stop(room.id);
        store.remove(room.id);
        return send(res, 204);
      }
      if (parts.length === 3 && parts[2] === 'join' && req.method === 'POST') {
        if (!joinLimiter.allow(ip)) return send(res, 429, { error: 'Too many attempts, wait a minute.' });
        const body = await readJson(req);
        const result = store.join(parts[1], body);
        return send(res, result.status, result.body);
      }
      if (parts.length === 3 && parts[2] === 'heartbeat' && req.method === 'POST') {
        if (!room) return send(res, 404, { error: 'Room not found.' });
        const body = await readJson(req);
        const result = store.heartbeat(room.id, req.headers['x-room-secret'], body);
        return send(res, result.status, result.body);
      }
      return send(res, 404, { error: 'Not found.' });
    } catch (e) {
      const status = e.status || 500;
      if (status >= 500) logger.error(e);
      return send(res, status, { error: status >= 500 && !e.status ? 'Internal error.' : e.message });
    }
  }

  const server = http.createServer((req, res) => { handle(req, res); });
  const sweeper = setInterval(() => {
    for (const room of store.collectExpired()) {
      logger.log(`[room ${room.code}] expired (${room.state})`);
      launcher.stop(room.id);
    }
  }, config.sweepIntervalMs || 5000);
  sweeper.unref();

  server.on('close', () => {
    clearInterval(sweeper);
    launcher.stopAll();
  });

  return { server, store, launcher };
}

module.exports = { createService, RateLimiter };
