extends RefCounted
## Multiplayer settings. The server address is taken from (first match wins):
##   1. Settings -> Server address in the lobby (GameState.server_address)
##   2. Firebase Realtime Database: config/server = {"host": "...", "port": 7777}
##   3. DEFAULT_HOST below
## With no address the game plays offline against bots.

const DEFAULT_HOST := ""
const PORT := 7777
const PROTOCOL := 1
const MAX_PLAYERS := 24
## Waiting room: the countdown starts when the first player joins.
const LOBBY_SECONDS := 30.0
## How long the server waits for every client to finish building the island.
const READY_TIMEOUT := 120.0
const SNAPSHOT_HZ := 15.0
const CONNECT_TIMEOUT := 6.0
