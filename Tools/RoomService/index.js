#!/usr/bin/env node
'use strict';
const { loadConfig } = require('./src/config');
const { createService } = require('./src/server');

const config = loadConfig();
const { server, launcher } = createService(config);
server.listen(config.port, config.host, () => {
  console.log(`Room service listening on ${config.host}:${config.port}`);
  console.log(`Game servers: ${launcher.enabled ? config.serverBinary : 'DISABLED (set SERVER_BINARY)'}; public host ${config.publicHost}`);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
