extends Node
## Match controller for Vis Island: builds the world, spawns the player (parachute drop) and
## bots, scatters loot, runs the zone, the kill feed and the end of the match.

const VisWorld := preload("res://scripts/game/vis_world.gd")
const Ballistics := preload("res://scripts/game/ballistics.gd")
const Zone := preload("res://scripts/game/zone.gd")
const PlayerScript := preload("res://scripts/game/player.gd")
const BotScript := preload("res://scripts/game/bot.gd")
const Hud := preload("res://scripts/game/game_hud.gd")
const Pickup := preload("res://scripts/game/pickup.gd")
const WeaponDB := preload("res://scripts/game/weapon_db.gd")
const SoldierMesh := preload("res://scripts/game/soldier_mesh.gd")
const Sfx := preload("res://scripts/game/sfx.gd")
const CharacterModel := preload("res://scripts/character_model.gd")
const CharacterDB := preload("res://scripts/game/character_db.gd")
const MapData := preload("res://maps/vis/vis_map.gd")
const RemoteCombatant := preload("res://scripts/net/remote_combatant.gd")
const NetConfig := preload("res://scripts/net/net_config.gd")

const BOT_COUNT := 23
const MAX_LOOT := 340
const GOLD := Color(1.0, 0.78, 0.1)
const BOT_NAMES := ["Rania", "Omar", "Leo", "Mina", "Yusuf", "Kai", "Sara", "Ivan", "Luka", "Ana", "Marko", "Noor", "Elena", "Tariq", "Petra", "Hana", "Josip", "Zara", "Ali", "Nika", "Dario", "Lina", "Karim", "Mateo"]

var world: VisWorld
var ballistics: Ballistics
var zone: Zone
var player: PlayerScript
var hud: Hud
var rng := RandomNumberGenerator.new()

var _all: Array = []
var _zone_tick := 0.0
var _finished := false
var _ui_audio: AudioStreamPlayer
# Online match state.
var _net := {}            # net id -> combatant (players by peer id, bots by negative id)
var _pickups := {}        # pickup id -> Area3D (same ids on every machine)
var _next_pickup := 1
var _send_t := 0.0
var _zone_sync_t := 0.0
var _started := false
var _server_go := false


func _ready() -> void:
	if Net.in_match:
		rng.seed = Net.match_seed
	else:
		rng.randomize()
	_setup_input()
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	_ui_audio = AudioStreamPlayer.new()
	add_child(_ui_audio)
	world = VisWorld.new()
	world.name = "World"
	add_child(world)
	await world.build(hud.set_loading)
	SoldierMesh.ensure_built(self)
	ballistics = Ballistics.new()
	ballistics.name = "Ballistics"
	add_child(ballistics)
	ballistics.hit_confirmed.connect(_on_hit_confirmed)
	if Net.in_match:
		# Same seed on every machine -> identical loot with identical ids.
		seed(Net.match_seed)
		rng.seed = Net.match_seed
	_spawn_loot()
	zone = Zone.new()
	zone.name = "Zone"
	add_child(zone)
	var start := world.random_land_point(Vector2.ZERO, 2500.0, 0.6)
	zone.setup(world, Vector2(start.x, start.z), 6200.0)
	zone.follower = Net.is_client_match()
	if Net.is_server:
		_start_server_match()
		return
	if Net.is_client_match():
		# Everyone shares the match seed; give each player their own drop point.
		seed(Net.match_seed + Net.my_id() * 7919)
	_spawn_player()
	if Net.is_client_match():
		Net.battle = self
		player.set_meta("net_id", Net.my_id())
		player.fired_shot.connect(_on_local_fired)
		_spawn_roster_puppets()
		Net.match_ended.connect(_on_net_match_ended)
		Net.connection_lost.connect(_on_net_connection_lost)
		hud.set_loading(0.99, "Waiting for the other players")
		player.process_mode = Node.PROCESS_MODE_DISABLED
		Net.send_ready()
		if not Net.go_arrived:
			await Net.go_received
		_spawn_bot_puppets(Net.bots)
		player.process_mode = Node.PROCESS_MODE_INHERIT
	else:
		_spawn_bots(BOT_COUNT)
	_started = true
	hud.player = player
	hud.battle = self
	hud.hide_loading()
	var mode := "online" if Net.is_client_match() else "vs bots"
	hud.add_feed("Vis Island  ·  %d players (%s)  ·  good luck" % [_all.size(), mode], GOLD)


func _setup_input() -> void:
	_bind("move_forward", [KEY_W, KEY_UP])
	_bind("move_back", [KEY_S, KEY_DOWN])
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("jump", [KEY_SPACE])
	_bind("sprint", [KEY_SHIFT])
	_bind("crouch", [KEY_C, KEY_CTRL])
	_bind("prone", [KEY_Z])
	_bind("reload", [KEY_R])
	_bind("interact", [KEY_F, KEY_E])
	_bind("switch_weapon", [KEY_Q, KEY_1, KEY_2])
	_bind("fire_mode", [KEY_B])
	_bind("heal", [KEY_H])


func _bind(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


# --- Spawning ------------------------------------------------------------------------------

func _spawn_player() -> void:
	player = PlayerScript.new()
	player.name = "Player"
	var accent: Dictionary = CharacterModel.OUTFITS[clampi(GameState.outfit_index, 0, CharacterModel.OUTFITS.size() - 1)]
	var cid := GameState.character_id if GameState.character_id != "" else "soldier"
	player.setup_body(accent["color"], PlayerScript.LAYER_PLAYER, cid, GameState.outfit_id)
	player.ballistics = ballistics
	player.hud = hud
	var drop := world.random_land_point(zone.center, 1800.0, 0.8)
	player.position = drop + Vector3(0, 700.0, 0)
	add_child(player)
	player.give_weapon("m1911")
	player.add_ammo(".45ACP", 14)
	player.died.connect(_on_died)
	player.damaged.connect(_on_player_damaged)
	_all.append(player)


func _spawn_bots(count: int) -> void:
	for i in count:
		var b := BotScript.new()
		b.name = "Bot%d" % i
		b.display_name = str(BOT_NAMES[i % BOT_NAMES.size()])
		var bc: Dictionary = CharacterDB.CHARACTERS[rng.randi() % CharacterDB.CHARACTERS.size()]
		var bo: Dictionary = CharacterDB.OUTFITS[rng.randi() % CharacterDB.OUTFITS.size()]
		# The headless server never draws anyone: a light body saves memory on small VMs.
		var body_id := "" if Net.is_server else str(bc["id"])
		b.setup_body(Color.from_hsv(rng.randf(), 0.6, 0.7), BotScript.LAYER_BOT, body_id, str(bo["id"]))
		b.ballistics = ballistics
		b.battle = self
		b.skill = rng.randf_range(0.25, 0.8)
		var spot: Vector3
		if rng.randf() < 0.7:
			var poi: Dictionary = MapData.POIS[rng.randi() % MapData.POIS.size()]
			spot = world.random_land_point(poi["pos"], 500.0, 0.4)
		else:
			spot = world.random_land_point()
		b.position = spot + Vector3(0, 0.4, 0)
		add_child(b)
		b.give_weapon(WeaponDB.random_id(rng))
		b.died.connect(_on_died)
		b.set_meta("net_id", -(i + 1))
		b.set_meta("look", [str(bc["id"]), str(bo["id"])])
		_all.append(b)


func _spawn_loot() -> void:
	var pts: Array = world.loot_points.duplicate()
	pts.shuffle()
	var count := mini(MAX_LOOT, pts.size())
	for i in count:
		var p: Vector3 = pts[i]
		var roll := rng.randf()
		if roll < 0.55:
			var id := WeaponDB.random_id(rng)
			_weapon_pickup(id, p, -1, _alloc_pickup())
			var w := WeaponDB.get_weapon(id)
			_ammo_pickup(str(w["ammo"]), int(w["mag"]), p + Vector3(0.7, 0, 0.4), _alloc_pickup())
		elif roll < 0.85:
			var w2 := WeaponDB.get_weapon(WeaponDB.random_id(rng))
			_ammo_pickup(str(w2["ammo"]), int(w2["mag"]) * 2, p, _alloc_pickup())
		else:
			_medkit_pickup(p, _alloc_pickup())
		if i % 60 == 0:
			hud.set_loading(0.95, "Loot %d / %d" % [i, count])


func _alloc_pickup() -> int:
	_next_pickup += 1
	return _next_pickup


func _register_pickup(pk: Area3D, pid: int) -> void:
	add_child(pk)
	_ready_pickup_signals(pk)
	if pid > 0:
		pk.set_meta("pid", pid)
		_pickups[pid] = pk


func _ammo_pickup(ammo: String, amount: int, pos: Vector3, pid: int = -1) -> void:
	var pk := Pickup.new()
	pk.position = pos
	pk.setup_ammo(ammo, amount)
	_register_pickup(pk, pid)


func _medkit_pickup(pos: Vector3, pid: int = -1) -> void:
	var med := Pickup.new()
	med.position = pos
	med.setup_medkit()
	_register_pickup(med, pid)


func _weapon_pickup(id: String, pos: Vector3, rounds: int, pid: int = -1) -> void:
	var pk := Pickup.new()
	pk.position = pos + Vector3(0, 0.05, 0)
	pk.setup_weapon(id, rounds)
	_register_pickup(pk, pid)


## Puts a weapon on the ground when the player swaps weapons. Online, the server numbers
## the drop and tells every machine, so everybody sees (and can loot) the same gun.
func drop_weapon(id: String, pos: Vector3, rounds: int) -> void:
	if Net.is_client_match():
		Net.send_drop(id, pos, rounds)
		return
	_weapon_pickup(id, pos, rounds)


## The local player looted something: other machines remove it too.
func on_pickup_taken(pk: Area3D) -> void:
	if not pk.has_meta("pid"):
		return
	var pid := int(pk.get_meta("pid"))
	_pickups.erase(pid)
	if Net.is_client_match():
		Net.send_pickup(pid)


func _ready_pickup_signals(pk: Area3D) -> void:
	pk.body_entered.connect(_on_pickup_enter.bind(pk))
	pk.body_exited.connect(_on_pickup_exit.bind(pk))


func _on_pickup_enter(body: Node, pk: Area3D) -> void:
	if body == player and not player.nearby.has(pk):
		player.nearby.append(pk)


func _on_pickup_exit(body: Node, pk: Area3D) -> void:
	if body == player:
		player.nearby.erase(pk)


# --- Match flow -------------------------------------------------------------------------------

func combatants() -> Array:
	return _all


func alive_count() -> int:
	var n := 0
	for c in _all:
		if bool(c.get("alive")):
			n += 1
	return n


func _physics_process(delta: float) -> void:
	if not Net.in_match or not _started:
		return
	_send_t += delta
	if _send_t >= 1.0 / NetConfig.SNAPSHOT_HZ:
		_send_t = 0.0
		if Net.is_server:
			var states: Array = []
			for c in _all:
				states.append(_state_of(c))
			Net.broadcast_snapshot(states)
		elif player:
			Net.send_state(_state_of(player))
	if Net.is_server:
		_zone_sync_t += delta
		if _zone_sync_t >= 1.0:
			_zone_sync_t = 0.0
			Net.broadcast_zone(zone.get_state())


func _process(delta: float) -> void:
	if _finished or zone == null or Net.is_client_match():
		return
	if Net.is_server and not _server_go:
		return
	_zone_tick += delta
	if _zone_tick >= 1.0:
		_zone_tick = 0.0
		for c in _all:
			var body := c as Node3D
			if body == null or not bool(c.get("alive")):
				continue
			if c.get("_has_state") != null and not bool(c.get("_has_state")):
				continue
			if not zone.is_inside(body.global_position) or body.global_position.y < -40.0:
				c.call("take_hit", zone.damage, null, body.global_position + Vector3(0, 1.1, 0))


func _on_hit_confirmed(shooter: Node, _victim: Node, _damage: float, headshot: bool, killed: bool) -> void:
	if shooter == player:
		hud.flash_hit(headshot, killed)
		_ui_audio.stream = Sfx.hit_marker()
		_ui_audio.play()


func _on_player_damaged(amount: float, _from_dir: Vector3) -> void:
	hud.flash_damage(amount)


func _on_died(victim: Node, killer: Node) -> void:
	var vname := str(victim.get("display_name"))
	var text := ""
	if killer and killer != victim:
		var gun := ""
		if bool(killer.call("has_weapon")):
			var w: Dictionary = killer.call("weapon")
			gun = str(w["name"])
		text = "%s  [%s]  %s" % [str(killer.get("display_name")), gun, vname]
	else:
		text = "%s was lost to the zone" % vname
	var color := GOLD if player != null and (killer == player or victim == player) else Color.WHITE
	hud.add_feed(text, color)
	# Death loot: weapons, ammo and sometimes a first aid kit. Online the ids are derived from
	# the victim so every machine creates the same pickups.
	var pos := (victim as Node3D).global_position
	var ws: Array = victim.get("weapons")
	var vm: Dictionary = victim.get("mags")
	var vid := absi(_nid(victim)) % 100000
	var base := 1000000 + vid * 10 if Net.in_match else -1
	var k := 0
	for id in ws:
		_weapon_pickup(str(id), pos + Vector3(0.6 * k - 0.3, 0, 0.5), int(vm.get(id, 0)), base + k if base > 0 else -1)
		var w2 := WeaponDB.get_weapon(str(id))
		_ammo_pickup(str(w2["ammo"]), int(w2["mag"]) * 2, pos + Vector3(-0.6, 0, -0.5 + k), base + 4 + k if base > 0 else -1)
		k += 1
	if (vid % 2 == 0) if Net.in_match else rng.randf() < 0.5:
		_medkit_pickup(pos + Vector3(0.5, 0, -0.6), base + 9 if base > 0 else -1)
	if Net.is_server:
		_server_check_end()
		return
	if _finished or player == null:
		return
	if victim == player:
		_end_match(false)
	elif alive_count() <= 1 and player.alive and not Net.is_client_match():
		_end_match(true)


func _end_match(won: bool) -> void:
	_finished = true
	var place := 1 if won else alive_count() + 1
	var gold := player.kills * 25 + (300 if won else maxi(0, (BOT_COUNT + 2 - place) * 8))
	GameState.add_gold(gold)
	if won:
		hud.show_end("VICTORY", "Last one standing on Vis Island      Kills  %d      +%d Gold" % [player.kills, gold])
	else:
		hud.show_end("ELIMINATED", "Place  #%d      Kills  %d      +%d Gold" % [place, player.kills, gold])


func return_to_lobby() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Net.leave()
	Online.push_save()
	SceneRouter.go("res://scenes/lobby.tscn", "LOBBY", "Back to base")


# --- Online match ---------------------------------------------------------------------------

func _nid(c: Object) -> int:
	if c != null and c.has_meta("net_id"):
		return int(c.get_meta("net_id"))
	return 0


func _state_of(c: Node) -> Array:
	var flags := 0
	var aim := false
	if c == player:
		aim = player.aiming
	elif c.get("aiming_remote") != null:
		aim = bool(c.get("aiming_remote"))
	elif c.get("_target") != null:
		aim = true
	if aim:
		flags |= 1
	var airborne := not (c as CharacterBody3D).is_on_floor()
	if c.get("_airborne") != null:
		airborne = bool(c.get("_airborne"))
	if airborne:
		flags |= 2
	if c == player and player.state == PlayerScript.State.CHUTE:
		flags |= 4
	if bool(c.get("sprinting")):
		flags |= 8
	if bool(c.call("is_reloading")):
		flags |= 16
	if bool(c.get("alive")):
		flags |= 32
	var vis: Node3D = c.get("visual")
	return [_nid(c), (c as Node3D).global_position, vis.rotation.y if vis else 0.0, c.get("velocity"), int(c.get("stance")), flags, str(c.call("current_id")), float(c.get("health"))]


func _make_puppet(id: int, display: String, character_id: String, outfit: String) -> RemoteCombatant:
	var p := RemoteCombatant.new()
	p.name = "Net%d" % id if id > 0 else "NetBot%d" % -id
	p.display_name = display
	p.net_id = id
	p.set_meta("net_id", id)
	var body_id := character_id if character_id != "" else "soldier"
	if Net.is_server:
		body_id = ""
	p.setup_body(Color.from_hsv(randf(), 0.6, 0.7), RemoteCombatant.LAYER_BOT, body_id, outfit)
	p.ballistics = ballistics
	p.position = Vector3(0, -500, 0)
	add_child(p)
	p.died.connect(_on_died)
	_net[id] = p
	_all.append(p)
	return p


func _spawn_roster_puppets() -> void:
	for id in Net.roster:
		if int(id) == Net.my_id():
			continue
		var info: Dictionary = Net.roster[id]
		_make_puppet(int(id), str(info.get("name", "Player")), str(info.get("character", "")), str(info.get("outfit", "original")))


func _spawn_bot_puppets(list: Array) -> void:
	for entry in list:
		var e: Array = entry
		var p := _make_puppet(int(e[0]), str(e[1]), str(e[2]), str(e[3]))
		if str(e[4]) != "":
			p.give_weapon(str(e[4]))


## Dedicated server: puppets for the connected players, bots for the empty slots.
func _start_server_match() -> void:
	Net.battle = self
	_spawn_roster_puppets()
	_spawn_bots(maxi(0, NetConfig.MAX_PLAYERS - Net.roster.size()))
	var bot_list: Array = []
	for c in _all:
		var nid := _nid(c)
		if nid < 0:
			_net[nid] = c
			var look: Array = c.get_meta("look", ["soldier", "original"])
			bot_list.append([nid, str(c.get("display_name")), str(look[0]), str(look[1]), str(c.call("current_id"))])
			var shooter: Node = c
			shooter.connect("fired_shot", _on_bot_fired.bind(nid))
		var hurt_node: Node = c
		hurt_node.connect("hurt", _on_server_hurt.bind(c))
	# Bots and the zone wait until every player has loaded the island.
	for c in _all:
		if _nid(c) < 0:
			var bot_node: Node = c
			bot_node.process_mode = Node.PROCESS_MODE_DISABLED
	zone.process_mode = Node.PROCESS_MODE_DISABLED
	Net.go_received.connect(_on_server_go, CONNECT_ONE_SHOT)
	hud.hide_loading()
	_started = true
	Net.server_world_ready(bot_list)


func _on_server_go() -> void:
	_server_go = true
	for c in _all:
		var n: Node = c
		n.process_mode = Node.PROCESS_MODE_INHERIT
	zone.process_mode = Node.PROCESS_MODE_INHERIT


func _on_bot_fired(origin: Vector3, dir: Vector3, nid: int) -> void:
	Net.broadcast_fire(nid, origin, dir)


func _on_local_fired(origin: Vector3, dir: Vector3) -> void:
	Net.send_fire(origin, dir)


func _on_server_hurt(amount: float, attacker: Node, headshot: bool, killed: bool, victim: Node) -> void:
	Net.broadcast_damage(_nid(victim), _nid(attacker), amount, headshot, killed, float(victim.get("health")))


func _server_check_end() -> void:
	var alive_total := 0
	var humans_alive := 0
	var last: Node = null
	for c in _all:
		if bool(c.get("alive")):
			alive_total += 1
			last = c
			if _nid(c) > 0:
				humans_alive += 1
	if alive_total <= 1 or humans_alive == 0:
		var wid := _nid(last) if alive_total == 1 else 0
		Net.server_end_match(wid, str(last.get("display_name")) if last and alive_total == 1 else "")


func net_client_state(peer: int, state: Array) -> void:
	var p: Node = _net.get(peer)
	if p and state.size() >= 8:
		state[0] = peer
		p.call("apply_state", state)


func net_snapshot(states: Array) -> void:
	var me := Net.my_id()
	for s in states:
		var st: Array = s
		if st.is_empty() or int(st[0]) == me:
			continue
		var p: Node = _net.get(int(st[0]))
		if p:
			p.call("apply_state", st)


func net_remote_fire(shooter_id: int, origin: Vector3, dir: Vector3) -> void:
	var p: Node = _net.get(shooter_id)
	if p:
		p.call("remote_fire", origin, dir)


## Server: a client reports a bullet hit (or its own fall damage).
func net_client_hit(from_peer: int, target_id: int, damage: float, local_y: float) -> void:
	var attacker: Node3D = _net.get(from_peer)
	var target: Node3D = _net.get(target_id)
	if attacker == null or target == null or not bool(target.get("alive")):
		return
	# Hits are reported by the shooter's machine (dead shooters cannot hit).
	if target != attacker and not bool(attacker.get("alive")):
		return
	target.call("take_hit", clampf(damage, 0.0, 250.0), attacker, target.global_position + Vector3(0, local_y, 0))


## Client: damage decided by the server.
func net_damage(target_id: int, attacker_id: int, amount: float, headshot: bool, killed: bool, health: float) -> void:
	var me := Net.my_id()
	var attacker: Node = player if attacker_id == me else _net.get(attacker_id)
	if target_id == me:
		player.net_damaged(amount, attacker, health, killed)
	else:
		var p: Node = _net.get(target_id)
		if p:
			p.call("net_set_health", health, attacker, killed)
	if attacker_id == me and killed and target_id != me:
		hud.flash_hit(headshot, true)


func net_remove_pickup(pid: int) -> void:
	var pk: Variant = _pickups.get(pid)
	_pickups.erase(pid)
	if pk != null and is_instance_valid(pk):
		if player:
			player.nearby.erase(pk)
		var pk_node: Node = pk
		pk_node.queue_free()


func net_spawn_drop(pid: int, weapon_id: String, pos: Vector3, rounds: int) -> void:
	_weapon_pickup(weapon_id, pos, rounds, pid)


func net_zone(state: Array) -> void:
	if zone:
		zone.apply_state(state)


## Server: a player disconnected mid-match.
func net_peer_left(peer: int) -> void:
	var p: Node3D = _net.get(peer)
	if p and bool(p.get("alive")):
		p.call("take_hit", 9999.0, null, p.global_position + Vector3(0, 1.0, 0))


func _on_net_match_ended(winner_id: int, winner_name: String) -> void:
	if _finished:
		return
	if winner_id == Net.my_id() and player.alive:
		_end_match(true)
	else:
		_finished = true
		var who := winner_name if winner_name != "" else "nobody"
		hud.show_end("MATCH OVER", "Winner: %s      Your kills  %d" % [who, player.kills])


func _on_net_connection_lost(reason: String) -> void:
	if _finished:
		return
	_finished = true
	hud.show_end("CONNECTION LOST", reason)
