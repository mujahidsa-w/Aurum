extends Node
## Autoload "Net": real-time multiplayer over ENet (UDP).
##
## The same project runs as the dedicated server (`godot --headless -- --server`): it keeps
## a waiting room, starts a match when the countdown ends, runs the bots, the zone and all
## damage (server-authoritative), and relays player movement and shots. Clients move their
## own character locally (no input lag), send their state 15x per second and receive
## snapshots of everyone else. Every RPC lives on this node so paths match on all peers.

signal status_changed(text: String)
signal lobby_updated(players: int, seconds_left: int)
signal match_started
signal go_received
signal match_ended(winner_id: int, winner_name: String)
signal connection_lost(reason: String)

const Config := preload("res://scripts/net/net_config.gd")

## Server: this process is the dedicated server.
var is_server := false
## A networked match is running (client or server).
var in_match := false
var match_seed := 0
## peer_id -> {name, character, outfit}
var roster := {}
## Bots announced by the server at go: [[id, name, character, outfit, weapon], ...]
var bots: Array = []
## The battleground registers itself here while a networked match runs.
var battle: Node
var status := "offline"
## The server's go arrived (clients may receive it before they start waiting for it).
var go_arrived := false

var _peer: ENetMultiplayerPeer
var _phase := "idle"   # server: waiting / loading / playing / ending
var _waiting := {}
var _countdown := -1.0
var _lobby_tick := 0.0
var _ready_peers := {}
var _ready_wait := 0.0
var _lobby_seconds := Config.LOBBY_SECONDS
var _connect_t := -1.0
var _end_t := -1.0
var _drop_id := 900000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var args := OS.get_cmdline_user_args()
	if args.has("--server") or OS.has_feature("dedicated_server"):
		var port := Config.PORT
		for a in args:
			if a.begins_with("--port="):
				port = int(a.substr(7))
			elif a.begins_with("--lobby-seconds="):
				_lobby_seconds = float(a.substr(16))
		_start_server.call_deferred(port)


func my_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1


func is_client_match() -> bool:
	return in_match and not is_server


## Address to use for online matches ("" = offline).
func server_address() -> String:
	if GameState.server_address != "":
		return GameState.server_address
	if Online.server_host != "":
		return Online.server_host
	return Config.DEFAULT_HOST


# --- Server --------------------------------------------------------------------------------

func _start_server(port: int) -> void:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, Config.MAX_PLAYERS)
	if err != OK:
		push_error("AURUM SERVER: cannot listen on UDP %d (%s)" % [port, error_string(err)])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = _peer
	is_server = true
	_set_phase_waiting()
	print("AURUM SERVER: listening on UDP %d (protocol %d, %d players max, lobby %ds)" % [port, Config.PROTOCOL, Config.MAX_PLAYERS, int(_lobby_seconds)])


func _set_phase_waiting() -> void:
	_phase = "waiting"
	in_match = false
	battle = null
	_waiting.clear()
	_ready_peers.clear()
	roster.clear()
	bots.clear()
	_countdown = -1.0
	get_tree().change_scene_to_file("res://scenes/server.tscn")


@rpc("any_peer", "call_remote", "reliable")
func _c_register(protocol: int, player_name: String, character: String, outfit: String) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if protocol != Config.PROTOCOL:
		_s_rejected.rpc_id(id, "Please update the game to play online.")
		return
	if _phase != "waiting":
		_s_rejected.rpc_id(id, "A match is in progress. Try again in a minute.")
		return
	_waiting[id] = {"name": player_name.substr(0, 16), "character": character, "outfit": outfit}
	print("AURUM SERVER: %s joined (%d waiting)" % [player_name, _waiting.size()])
	if _countdown < 0.0:
		_countdown = _lobby_seconds
	if _waiting.size() >= Config.MAX_PLAYERS:
		_countdown = minf(_countdown, 3.0)
	_broadcast_lobby()


func _broadcast_lobby() -> void:
	for id in _waiting:
		_s_lobby.rpc_id(id, _waiting.size(), int(ceil(maxf(_countdown, 0.0))))


func _start_match() -> void:
	_phase = "loading"
	in_match = true
	match_seed = randi()
	roster = _waiting.duplicate(true)
	_ready_peers.clear()
	_ready_wait = 0.0
	print("AURUM SERVER: match starting with %d players (seed %d)" % [roster.size(), match_seed])
	for id in roster:
		_s_start.rpc_id(id, match_seed, roster)
	get_tree().change_scene_to_file("res://scenes/battleground.tscn")


## Called by the server battleground once its island is built.
func server_world_ready(bot_list: Array) -> void:
	bots = bot_list
	_phase = "ready_wait"


@rpc("any_peer", "call_remote", "reliable")
func _c_ready() -> void:
	if is_server:
		_ready_peers[multiplayer.get_remote_sender_id()] = true


func _send_go() -> void:
	_phase = "playing"
	print("AURUM SERVER: go (%d/%d clients ready)" % [_ready_peers.size(), roster.size()])
	for id in roster:
		_s_go.rpc_id(id, bots)
	go_received.emit()


## Called by the server battleground when one (or no) combatant is left.
func server_end_match(winner_id: int, winner_name: String) -> void:
	if _phase == "ending":
		return
	_phase = "ending"
	print("AURUM SERVER: match over, winner %s" % winner_name)
	for id in roster:
		if multiplayer.get_peers().has(id):
			_s_end.rpc_id(id, winner_id, winner_name)
	_end_t = 12.0


func _process(delta: float) -> void:
	if _connect_t >= 0.0:
		_connect_t -= delta
		if _connect_t < 0.0 and status == "connecting":
			_fail("Server did not answer")
	if not is_server:
		return
	match _phase:
		"waiting":
			if _countdown >= 0.0:
				_countdown -= delta
				_lobby_tick += delta
				if _lobby_tick >= 1.0:
					_lobby_tick = 0.0
					_broadcast_lobby()
				if _countdown <= 0.0:
					if _waiting.is_empty():
						_countdown = -1.0
					else:
						_start_match()
		"ready_wait":
			_ready_wait += delta
			var all_ready := true
			for id in roster:
				if not _ready_peers.has(id) and multiplayer.get_peers().has(id):
					all_ready = false
			if all_ready or _ready_wait > Config.READY_TIMEOUT:
				_send_go()
		"ending":
			_end_t -= delta
			if _end_t <= 0.0:
				for id in multiplayer.get_peers():
					_peer.disconnect_peer(id)
				_set_phase_waiting()


func _on_peer_connected(id: int) -> void:
	if is_server:
		print("AURUM SERVER: peer %d connected" % id)


func _on_peer_disconnected(id: int) -> void:
	if not is_server:
		return
	_waiting.erase(id)
	# Stop addressing the departed peer before the battleground reacts to the departure.
	roster.erase(id)
	if _phase == "waiting":
		if _waiting.is_empty():
			_countdown = -1.0
		_broadcast_lobby()
	elif battle and battle.has_method("net_peer_left"):
		battle.call("net_peer_left", id)


# --- Client --------------------------------------------------------------------------------

## Connects to the server and enters its waiting room.
func find_match() -> bool:
	var address := server_address()
	if address == "":
		return false
	leave()
	var host := address
	var port := Config.PORT
	if address.contains(":"):
		host = address.get_slice(":", 0)
		port = int(address.get_slice(":", 1))
	_peer = ENetMultiplayerPeer.new()
	if _peer.create_client(host, port) != OK:
		_fail("Cannot reach %s" % address)
		return false
	multiplayer.multiplayer_peer = _peer
	_set_status("connecting")
	_connect_t = Config.CONNECT_TIMEOUT
	return true


func leave() -> void:
	if multiplayer.has_multiplayer_peer() and not is_server:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	in_match = false
	battle = null
	_connect_t = -1.0
	if not is_server:
		_set_status("offline")


func _on_connected() -> void:
	_connect_t = -1.0
	_set_status("waiting")
	_c_register.rpc_id(1, Config.PROTOCOL, GameState.player_name, GameState.character_id, GameState.outfit_id)


func _on_connection_failed() -> void:
	_fail("Server unreachable")


func _on_server_disconnected() -> void:
	var was_in_match := in_match
	multiplayer.multiplayer_peer = null
	in_match = false
	_set_status("offline")
	connection_lost.emit("Disconnected from the server" if was_in_match else "Server closed the connection")


func _fail(reason: String) -> void:
	_connect_t = -1.0
	if multiplayer.has_multiplayer_peer() and not is_server:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_set_status("offline")
	connection_lost.emit(reason)


func _set_status(s: String) -> void:
	status = s
	status_changed.emit(s)


@rpc("authority", "call_remote", "reliable")
func _s_rejected(reason: String) -> void:
	_fail(reason)


@rpc("authority", "call_remote", "reliable")
func _s_lobby(players: int, seconds_left: int) -> void:
	lobby_updated.emit(players, seconds_left)


@rpc("authority", "call_remote", "reliable")
func _s_start(seed_value: int, players: Dictionary) -> void:
	match_seed = seed_value
	roster = players
	in_match = true
	go_arrived = false
	_set_status("in_match")
	match_started.emit()


## Client battleground: island built, waiting for the server's go.
func send_ready() -> void:
	_c_ready.rpc_id(1)


@rpc("authority", "call_remote", "reliable")
func _s_go(bot_list: Array) -> void:
	bots = bot_list
	go_arrived = true
	go_received.emit()


@rpc("authority", "call_remote", "reliable")
func _s_end(winner_id: int, winner_name: String) -> void:
	match_ended.emit(winner_id, winner_name)


# --- In-match traffic ------------------------------------------------------------------------
# State entry: [id, pos, yaw, vel, stance, flags, weapon, health]
# flags: 1 aiming, 2 airborne, 4 parachute, 8 sprinting, 16 reloading, 32 alive

func send_state(state: Array) -> void:
	_c_state.rpc_id(1, state)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _c_state(state: Array) -> void:
	if is_server and battle:
		battle.call("net_client_state", multiplayer.get_remote_sender_id(), state)


func broadcast_snapshot(states: Array) -> void:
	for id in roster:
		if multiplayer.get_peers().has(id):
			_s_snapshot.rpc_id(id, states)


@rpc("authority", "call_remote", "unreliable_ordered")
func _s_snapshot(states: Array) -> void:
	if battle:
		battle.call("net_snapshot", states)


func send_fire(origin: Vector3, dir: Vector3) -> void:
	_c_fire.rpc_id(1, origin, dir)


@rpc("any_peer", "call_remote", "unreliable")
func _c_fire(origin: Vector3, dir: Vector3) -> void:
	if is_server:
		broadcast_fire(multiplayer.get_remote_sender_id(), origin, dir)


func broadcast_fire(shooter_id: int, origin: Vector3, dir: Vector3) -> void:
	for id in roster:
		if id != shooter_id and multiplayer.get_peers().has(id):
			_s_fire.rpc_id(id, shooter_id, origin, dir)


@rpc("authority", "call_remote", "unreliable")
func _s_fire(shooter_id: int, origin: Vector3, dir: Vector3) -> void:
	if battle:
		battle.call("net_remote_fire", shooter_id, origin, dir)


## A client's bullet hit `target_id` (or the client hurt itself, e.g. a fall).
func send_hit(target_id: int, damage: float, local_y: float) -> void:
	_c_hit.rpc_id(1, target_id, damage, local_y)


@rpc("any_peer", "call_remote", "reliable")
func _c_hit(target_id: int, damage: float, local_y: float) -> void:
	if is_server and battle:
		battle.call("net_client_hit", multiplayer.get_remote_sender_id(), target_id, damage, local_y)


func broadcast_damage(target_id: int, attacker_id: int, amount: float, headshot: bool, killed: bool, health: float) -> void:
	for id in roster:
		if multiplayer.get_peers().has(id):
			_s_damage.rpc_id(id, target_id, attacker_id, amount, headshot, killed, health)


@rpc("authority", "call_remote", "reliable")
func _s_damage(target_id: int, attacker_id: int, amount: float, headshot: bool, killed: bool, health: float) -> void:
	if battle:
		battle.call("net_damage", target_id, attacker_id, amount, headshot, killed, health)


func send_pickup(pickup_id: int) -> void:
	_c_pickup.rpc_id(1, pickup_id)


@rpc("any_peer", "call_remote", "reliable")
func _c_pickup(pickup_id: int) -> void:
	if not is_server:
		return
	var from := multiplayer.get_remote_sender_id()
	if battle:
		battle.call("net_remove_pickup", pickup_id)
	for id in roster:
		if id != from and multiplayer.get_peers().has(id):
			_s_pickup.rpc_id(id, pickup_id)


@rpc("authority", "call_remote", "reliable")
func _s_pickup(pickup_id: int) -> void:
	if battle:
		battle.call("net_remove_pickup", pickup_id)


## A weapon dropped by a player or a death: the server numbers it and tells everyone.
func send_drop(weapon_id: String, pos: Vector3, rounds: int) -> void:
	_c_drop.rpc_id(1, weapon_id, pos, rounds)


@rpc("any_peer", "call_remote", "reliable")
func _c_drop(weapon_id: String, pos: Vector3, rounds: int) -> void:
	if is_server:
		broadcast_drop(weapon_id, pos, rounds)


func broadcast_drop(weapon_id: String, pos: Vector3, rounds: int) -> void:
	_drop_id += 1
	if battle:
		battle.call("net_spawn_drop", _drop_id, weapon_id, pos, rounds)
	for id in roster:
		if multiplayer.get_peers().has(id):
			_s_drop.rpc_id(id, _drop_id, weapon_id, pos, rounds)


@rpc("authority", "call_remote", "reliable")
func _s_drop(drop_id: int, weapon_id: String, pos: Vector3, rounds: int) -> void:
	if battle:
		battle.call("net_spawn_drop", drop_id, weapon_id, pos, rounds)


func broadcast_zone(state: Array) -> void:
	for id in roster:
		if multiplayer.get_peers().has(id):
			_s_zone.rpc_id(id, state)


@rpc("authority", "call_remote", "unreliable_ordered")
func _s_zone(state: Array) -> void:
	if battle:
		battle.call("net_zone", state)
