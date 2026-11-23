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


func _ready() -> void:
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
	_spawn_loot()
	zone = Zone.new()
	zone.name = "Zone"
	add_child(zone)
	var start := world.random_land_point(Vector2.ZERO, 2500.0, 0.6)
	zone.setup(world, Vector2(start.x, start.z), 6200.0)
	_spawn_player()
	_spawn_bots()
	hud.player = player
	hud.battle = self
	hud.hide_loading()
	hud.add_feed("Vis Island  ·  %d players  ·  good luck" % _all.size(), GOLD)


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


func _spawn_bots() -> void:
	for i in BOT_COUNT:
		var b := BotScript.new()
		b.name = "Bot%d" % i
		b.display_name = str(BOT_NAMES[i % BOT_NAMES.size()])
		var bc: Dictionary = CharacterDB.CHARACTERS[rng.randi() % CharacterDB.CHARACTERS.size()]
		var bo: Dictionary = CharacterDB.OUTFITS[rng.randi() % CharacterDB.OUTFITS.size()]
		b.setup_body(Color.from_hsv(rng.randf(), 0.6, 0.7), BotScript.LAYER_BOT, str(bc["id"]), str(bo["id"]))
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
			drop_weapon(id, p, -1)
			var w := WeaponDB.get_weapon(id)
			_ammo_pickup(str(w["ammo"]), int(w["mag"]), p + Vector3(0.7, 0, 0.4))
		elif roll < 0.85:
			var w2 := WeaponDB.get_weapon(WeaponDB.random_id(rng))
			_ammo_pickup(str(w2["ammo"]), int(w2["mag"]) * 2, p)
		else:
			var med := Pickup.new()
			med.position = p
			med.setup_medkit()
			add_child(med)
			_ready_pickup_signals(med)
		if i % 60 == 0:
			hud.set_loading(0.95, "Loot %d / %d" % [i, count])


func _ammo_pickup(ammo: String, amount: int, pos: Vector3) -> void:
	var pk := Pickup.new()
	pk.position = pos
	pk.setup_ammo(ammo, amount)
	add_child(pk)
	_ready_pickup_signals(pk)


## Puts a weapon on the ground (used for loot, deaths and swapping weapons).
func drop_weapon(id: String, pos: Vector3, rounds: int) -> void:
	var pk := Pickup.new()
	pk.position = pos + Vector3(0, 0.05, 0)
	pk.setup_weapon(id, rounds)
	add_child(pk)
	_ready_pickup_signals(pk)


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


func _process(delta: float) -> void:
	if _finished or zone == null:
		return
	_zone_tick += delta
	if _zone_tick >= 1.0:
		_zone_tick = 0.0
		for c in _all:
			var body := c as Node3D
			if body == null or not bool(c.get("alive")):
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
	var color := GOLD if killer == player or victim == player else Color.WHITE
	hud.add_feed(text, color)
	# Death loot: weapons, ammo and sometimes a first aid kit.
	var pos := (victim as Node3D).global_position
	var ws: Array = victim.get("weapons")
	var vm: Dictionary = victim.get("mags")
	var k := 0
	for id in ws:
		drop_weapon(str(id), pos + Vector3(0.6 * k - 0.3, 0, 0.5), int(vm.get(id, 0)))
		var w2 := WeaponDB.get_weapon(str(id))
		_ammo_pickup(str(w2["ammo"]), int(w2["mag"]) * 2, pos + Vector3(-0.6, 0, -0.5 + k))
		k += 1
	if rng.randf() < 0.5:
		var med := Pickup.new()
		med.position = pos + Vector3(0.5, 0, -0.6)
		med.setup_medkit()
		add_child(med)
		_ready_pickup_signals(med)
	if _finished:
		return
	if victim == player:
		_end_match(false)
	elif alive_count() <= 1 and player.alive:
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
	Online.push_save()
	SceneRouter.go("res://scenes/lobby.tscn", "LOBBY", "Back to base")
