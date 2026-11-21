'use strict';
// Starts one Unreal dedicated server process per room.

const { spawn } = require('child_process');

class ServerLauncher {
  /**
   * @param {object} config
   *   serverBinary   path to PUBG_BlueprintServer(.exe); empty = launching disabled
   *   serverArgs     extra arguments (array), e.g. ['-log']
   *   portMin/portMax  UDP port range for game servers
   *   publicHost     host name / IP clients use to reach the game servers
   *   serviceUrl     URL the game servers use to reach this service
   *   lobbyMap       map the server starts on
   */
  constructor(config, logger = console) {
    this.config = config;
    this.logger = logger;
    this.processes = new Map(); // roomId -> { child, port }
    this.onExit = null;         // (roomId, code) => void
  }

  get enabled() {
    return Boolean(this.config.serverBinary);
  }

  _allocatePort() {
    const used = new Set([...this.processes.values()].map((p) => p.port));
    for (let port = this.config.portMin; port <= this.config.portMax; port++) {
      if (!used.has(port)) return port;
    }
    return null;
  }

  buildArgs(room, port) {
    const url = `${this.config.lobbyMap}?game=Lobby` +
      `?RoomName=${encodeURIComponent(room.name)}` +
      `?MaxPlayers=${room.maxPlayers}` +
      `?BattleMap=${room.mapIndex}`;
    return [
      url,
      `-port=${port}`,
      `-RoomService=${this.config.serviceUrl}`,
      `-RoomId=${room.id}`,
      `-RoomSecret=${room.secret}`,
      `-RoomCode=${room.code}`,
      ...(this.config.serverArgs || []),
    ];
  }

  /** Starts the server for a room; sets room.port / room.address. */
  start(room) {
    if (!this.enabled) {
      const err = new Error('No dedicated server binary configured (SERVER_BINARY).');
      err.status = 503;
      throw err;
    }
    const port = this._allocatePort();
    if (port === null) {
      const err = new Error('No free game server port.');
      err.status = 503;
      throw err;
    }
    const args = this.buildArgs(room, port);
    const child = spawn(this.config.serverBinary, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    room.port = port;
    room.address = `${this.config.publicHost}:${port}`;
    this.processes.set(room.id, { child, port });
    const prefix = `[room ${room.code}]`;
    child.stdout.on('data', (d) => this.logger.log(`${prefix} ${String(d).trimEnd()}`));
    child.stderr.on('data', (d) => this.logger.error(`${prefix} ${String(d).trimEnd()}`));
    child.on('error', (e) => this.logger.error(`${prefix} failed to start: ${e.message}`));
    child.on('exit', (code) => {
      this.processes.delete(room.id);
      this.logger.log(`${prefix} server exited (${code})`);
      if (this.onExit) this.onExit(room.id, code);
    });
    this.logger.log(`${prefix} started on port ${port}`);
    return room;
  }

  stop(roomId) {
    const entry = this.processes.get(roomId);
    if (!entry) return false;
    entry.child.kill('SIGTERM');
    return true;
  }

  stopAll() {
    for (const id of [...this.processes.keys()]) this.stop(id);
  }
}

module.exports = { ServerLauncher };
