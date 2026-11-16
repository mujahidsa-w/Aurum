# Room Service

Room directory + dedicated-server launcher for internet multiplayer
(Node.js >= 18, no dependencies).

Phones are almost always behind NAT, so they cannot host internet games.
This service runs next to the Unreal dedicated server binaries: each online
room is one `PUBG_BlueprintServer` process on its own UDP port.

```
Game client ──HTTP──► Room service ──spawn──► PUBG_BlueprintServer (UDP 7777+N)
     │                     ▲                         │
     └──────UDP (game)─────┼─────────────────────────┘
                           └──── heartbeat (players, state) every 5 s
```

## Run

```bash
PORT=8080 \
PUBLIC_HOST=203.0.113.10 \
SERVER_BINARY=/opt/pubg/LinuxServer/PUBG_BlueprintServer.sh \
node index.js
```

| Variable | Default | Meaning |
|---|---|---|
| `PORT` / `HOST` | `8080` / `0.0.0.0` | HTTP listen address |
| `PUBLIC_HOST` | `127.0.0.1` | IP / DNS clients use to reach the game servers |
| `SERVICE_URL` | `http://127.0.0.1:$PORT` | URL the game servers use to reach this service |
| `SERVER_BINARY` | *(empty = room creation disabled)* | dedicated server executable |
| `SERVER_ARGS` | `-log` | extra server arguments |
| `SERVER_PORT_MIN` / `MAX` | `7777` / `7796` | UDP port pool (one room per port) |
| `LOBBY_MAP` | `/Game/Maps/Level_Test` | map the server starts on (`?game=Lobby` is added) |
| `MAX_ROOMS` | `10` | concurrent rooms |
| `START_TIMEOUT_MS` | `90000` | a server that never reports in is removed |
| `HEARTBEAT_TIMEOUT_MS` | `30000` | a silent server is removed (and killed) |
| `IDLE_TIMEOUT_MS` | `300000` | an empty room is removed |

Firewall: TCP `PORT`, UDP `SERVER_PORT_MIN..MAX`. Put it behind HTTPS
(Nginx / Caddy) in production and set `RoomServiceURL=https://...` in the game.

## API

| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/health` | | `{ ok, rooms, launcher }` |
| GET | `/rooms` | | `{ rooms: [ {id, code, name, hostName, players, maxPlayers, hasPassword, state, map} ] }` |
| POST | `/rooms` | `{ name, maxPlayers, password, mapIndex, hostName }` | `201` room (state `starting`) |
| GET | `/rooms/:idOrCode` | | room |
| POST | `/rooms/:idOrCode/join` | `{ playerName, password }` | `{ address, ticket }` · `403` wrong password · `409` starting / full / running |
| POST | `/rooms/:id/heartbeat` | `{ players, state }` + header `X-Room-Secret` | `{ ok }` |
| DELETE | `/rooms/:id` | header `X-Room-Secret` | `204` |

### Join tickets

`ticket = base64url("roomId|playerName|expiresUnix") + "." + hex(HMAC-SHA1(roomSecret, payload))`,
valid 60 s. The room secret is passed only to the game server process
(`-RoomSecret=`), which verifies the ticket in `APUBGLobbyGameMode::PreLogin`
(`UPUBGRoomServiceSubsystem::VerifyTicketWithSecret`). Room passwords are
stored as scrypt hashes here and never reach the game server.

## Tests

```bash
npm test
```
Unit tests, a cross-language ticket vector (same constants as the Unreal
automation test `PUBG.RoomService.TicketVector`) and end-to-end tests that
spawn `fixtures/fake-game-server.js` with the exact command line and heartbeat
protocol of the real server.
