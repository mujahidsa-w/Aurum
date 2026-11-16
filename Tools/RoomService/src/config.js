'use strict';
// Configuration from environment variables (see README.md).

function intEnv(name, fallback) {
  const value = parseInt(process.env[name], 10);
  return Number.isFinite(value) ? value : fallback;
}

function loadConfig(env = process.env) {
  const port = intEnv('PORT', 8080);
  return {
    port,
    host: env.HOST || '0.0.0.0',
    // Address players use to reach the game servers (public IP / DNS name of this machine).
    publicHost: env.PUBLIC_HOST || '127.0.0.1',
    // URL the game servers use to reach this service (usually local).
    serviceUrl: env.SERVICE_URL || `http://127.0.0.1:${port}`,
    serverBinary: env.SERVER_BINARY || '',
    serverArgs: (env.SERVER_ARGS || '-log').split(' ').filter(Boolean),
    lobbyMap: env.LOBBY_MAP || '/Game/Maps/Level_Test',
    mapNames: (env.MAP_NAMES || 'Test,Battle').split(','),
    portMin: intEnv('SERVER_PORT_MIN', 7777),
    portMax: intEnv('SERVER_PORT_MAX', 7796),
    maxRooms: intEnv('MAX_ROOMS', 10),
    maxPlayersLimit: intEnv('MAX_PLAYERS_LIMIT', 16),
    startTimeoutMs: intEnv('START_TIMEOUT_MS', 90_000),
    heartbeatTimeoutMs: intEnv('HEARTBEAT_TIMEOUT_MS', 30_000),
    idleTimeoutMs: intEnv('IDLE_TIMEOUT_MS', 300_000),
    sweepIntervalMs: intEnv('SWEEP_INTERVAL_MS', 5_000),
    createPerMinute: intEnv('CREATE_PER_MINUTE', 5),
    joinPerMinute: intEnv('JOIN_PER_MINUTE', 30),
  };
}

module.exports = { loadConfig };
