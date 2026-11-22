extends Node
## Training ground: a guided tutorial that teaches movement, sprinting, jumping, crouching,
## looting (weapon + ammo), shooting steel targets, aiming with a scope at 100 m, reloading
## and healing. Finishing it marks the player as trained and opens the lobby.

const PlayerScript := preload("res://scripts/game/player.gd")
const Ballistics := preload("res://scripts/game/ballistics.gd")
const Hud := preload("res://scripts/game/game_hud.gd")
const Pickup := preload("res://scripts/game/pickup.gd")
const WeaponDB := preload("res://scripts/game/weapon_db.gd")
const SoldierMesh := preload("res://scripts/game/soldier_mesh.gd")
const Sfx := preload("res://scripts/game/sfx.gd")

const TEX := "res://assets/textures/"


## Minimal flat "world" so the player/HUD code can ask for ground height.
class FlatWorld extends Node3D:
	var origin := Vector2(-150, -150)

	func height_at(_x: float, _z: float) -> float:
		return 0.0

	func is_land(_x: float, _z: float, _m: float = 0.0) -> bool:
		return true

	func size() -> Vector2:
		return Vector2(300, 300)


## Steel plate target: falls back when hit, stands up again after a moment.
class Target extends StaticBody3D:
	signal hit(target: Node, distance: float)
	var plate: Node3D
	var _down := false

	func build(radius: float) -> void:
		collision_layer = 1
		collision_mask = 0
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.08, 1.2, 0.08)
		post.mesh = pm
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.4, 0.3, 0.18)
		post.material_override = wood
		post.position = Vector3(0, 0.6, 0)
		add_child(post)
		plate = Node3D.new()
		plate.position = Vector3(0, 1.2, 0)
		add_child(plate)
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = radius
		cm.bottom_radius = radius
		cm.height = 0.03
		cm.radial_segments = 32
		disc.mesh = cm
		disc.rotation.x = PI * 0.5
		disc.position = Vector3(0, radius, 0)
		var steel := StandardMaterial3D.new()
		steel.albedo_color = Color(0.92, 0.92, 0.9)
		steel.metallic = 0.6
		steel.roughness = 0.35
		disc.material_override = steel
		plate.add_child(disc)
		var bull := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = radius * 0.35
		bm.bottom_radius = radius * 0.35
		bm.height = 0.035
		bull.mesh = bm
		bull.rotation.x = PI * 0.5
		bull.position = Vector3(0, radius, 0.002)
		var red := StandardMaterial3D.new()
		red.albedo_color = Color(0.85, 0.12, 0.1)
		bull.material_override = red
		plate.add_child(bull)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(radius * 2.0, radius * 2.0 + 1.2, 0.2)
		cs.shape = shape
		cs.position = Vector3(0, (radius * 2.0 + 1.2) * 0.5, 0)
		add_child(cs)

	func take_hit(_damage: float, attacker: Node, _point: Vector3) -> Dictionary:
		if _down:
			return {"damage": 0.0, "headshot": false, "killed": false}
		_down = true
		var dist := 0.0
		if attacker is Node3D:
			dist = (attacker as Node3D).global_position.distance_to(global_position)
		hit.emit(self, dist)
		var tw := create_tween()
		tw.tween_property(plate, "rotation:x", -PI * 0.45, 0.15)
		tw.tween_interval(2.0)
		tw.tween_property(plate, "rotation:x", 0.0, 0.3)
		tw.tween_callback(_stand_up)
		return {"damage": 1.0, "headshot": false, "killed": true}

	func _stand_up() -> void:
		_down = false


var world: FlatWorld
var zone: Node = null
var player: PlayerScript
var hud: Hud
var ballistics: Ballistics

var _step := 0
var _hits := 0
var _long_hit := false
var _start_pos := Vector3.ZERO
var _reloaded := false
var _health_set := false
var _done := false
var _marker: MeshInstance3D
var _ui_audio: AudioStreamPlayer

var _steps := [
	["Move", "Walk to the glowing ring.   WASD  /  left joystick"],
	["Sprint", "Sprint to the next ring.   Hold SHIFT  /  sprint button"],
	["Jump", "Jump once.   SPACE  /  jump button"],
	["Crouch", "Crouch to make yourself a smaller target.   C  /  crouch button"],
	["Loot a weapon", "Walk to the table and pick up the rifle.   F  /  hand button"],
	["Loot ammo", "Pick up the ammo box next to it."],
	["Shoot", "Hit 3 steel targets.   Left mouse  /  fire button"],
	["Aim down sights", "Aim with the scope and hit the far target (100 m).   Right mouse  /  scope button"],
	["Reload", "Reload your weapon.   R  /  reload button"],
	["Heal", "You are hurt. Pick up the first aid kit and use it.   H  /  medkit button"],
]


func _ready() -> void:
	_setup_input()
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.show_map = false
	_ui_audio = AudioStreamPlayer.new()
	add_child(_ui_audio)
	world = FlatWorld.new()
	world.name = "World"
	add_child(world)
	_build_ground()
	SoldierMesh.ensure_built(self)
	ballistics = Ballistics.new()
	add_child(ballistics)
	ballistics.hit_confirmed.connect(_on_hit_confirmed)
	_build_range()
	_spawn_player()
	hud.player = player
	hud.battle = self
	hud.hide_loading()
	_set_step(0)


func _setup_input() -> void:
	var binds := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT], "jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "crouch": [KEY_C, KEY_CTRL],
		"reload": [KEY_R], "interact": [KEY_F, KEY_E], "switch_weapon": [KEY_Q, KEY_1, KEY_2], "fire_mode": [KEY_B], "heal": [KEY_H],
	}
	for action in binds:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in binds[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


func _textured(name_key: String, scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if ResourceLoader.exists(TEX + name_key + "_albedo.jpg"):
		m.albedo_texture = load(TEX + name_key + "_albedo.jpg")
	if ResourceLoader.exists(TEX + name_key + "_normal.jpg"):
		m.normal_enabled = true
		m.normal_texture = load(TEX + name_key + "_normal.jpg")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	return m


func _build_ground() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	if ResourceLoader.exists(TEX + "sky_partly_cloudy_2k.hdr"):
		pano.panorama = load(TEX + "sky_partly_cloudy_2k.hdr")
		sky.sky_material = pano
	else:
		sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.light_energy = 1.4
	add_child(sun)
	sun.rotation_degrees = Vector3(-50, -35, 0)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300, 300)
	ground.mesh = pm
	ground.material_override = _textured("grass", 0.2)
	add_child(ground)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var floor_shape := WorldBoundaryShape3D.new()
	cs.shape = floor_shape
	body.add_child(cs)
	add_child(body)
	# A dirt shooting lane.
	var lane := MeshInstance3D.new()
	var lm := PlaneMesh.new()
	lm.size = Vector2(12, 120)
	lane.mesh = lm
	lane.material_override = _textured("dirt", 0.15)
	lane.position = Vector3(0, 0.01, -95)
	add_child(lane)


func _build_range() -> void:
	# Loot table.
	var table := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(2.4, 0.9, 1.0)
	table.mesh = tm
	table.material_override = _textured("concrete", 0.4)
	table.position = Vector3(5.0, 0.45, -44.0)
	add_child(table)
	var tb := StaticBody3D.new()
	var tcs := CollisionShape3D.new()
	var tshape := BoxShape3D.new()
	tshape.size = tm.size
	tcs.shape = tshape
	tb.add_child(tcs)
	tb.position = table.position
	add_child(tb)
	# Steel targets at 15-25 m and one at 100 m.
	for i in 3:
		var t := Target.new()
		t.build(0.35)
		t.position = Vector3(-4.0 + i * 4.0, 0.0, -62.0 - i * 5.0)
		t.hit.connect(_on_target_hit)
		add_child(t)
	var far := Target.new()
	far.build(0.6)
	far.position = Vector3(0, 0, -145.0)
	far.hit.connect(_on_target_hit)
	add_child(far)
	_marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 1.0
	ring.outer_radius = 1.25
	ring.rings = 32
	_marker.mesh = ring
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(1.0, 0.78, 0.1)
	mm.emission_enabled = true
	mm.emission = Color(1.0, 0.7, 0.1)
	mm.emission_energy_multiplier = 3.0
	_marker.material_override = mm
	add_child(_marker)


func _spawn_player() -> void:
	player = PlayerScript.new()
	player.name = "Player"
	var cid := GameState.character_id if GameState.character_id != "" else "soldier"
	player.setup_body(Color(0.62, 0.05, 0.07), PlayerScript.LAYER_PLAYER, cid, GameState.outfit_id)
	player.ballistics = ballistics
	player.hud = hud
	player.position = Vector3(0, 0.2, 0)
	add_child(player)
	player.state = PlayerScript.State.GROUND
	_start_pos = player.position


func _pickup(pk: Area3D) -> void:
	add_child(pk)
	pk.body_entered.connect(_on_pickup_enter.bind(pk))
	pk.body_exited.connect(_on_pickup_exit.bind(pk))


func _on_pickup_enter(body: Node, pk: Area3D) -> void:
	if body == player and not player.nearby.has(pk):
		player.nearby.append(pk)


func _on_pickup_exit(body: Node, pk: Area3D) -> void:
	if body == player:
		player.nearby.erase(pk)


func drop_weapon(id: String, pos: Vector3, rounds: int) -> void:
	var pk := Pickup.new()
	pk.position = pos
	pk.setup_weapon(id, rounds)
	_pickup(pk)


# --- HUD / player API ------------------------------------------------------------------------

func combatants() -> Array:
	return [player]


func alive_count() -> int:
	return 1


func return_to_lobby() -> void:
	GameState.trained = true
	GameState.save_state()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


# --- Steps ------------------------------------------------------------------------------------

func _set_step(i: int) -> void:
	_step = i
	if i >= _steps.size():
		_complete()
		return
	var s: Array = _steps[i]
	hud.set_objective("Training  %d/%d  ·  %s" % [i + 1, _steps.size(), str(s[0])], str(s[1]))
	_ui_audio.stream = Sfx.hit_marker()
	_ui_audio.play()
	_marker.visible = false
	match i:
		0:
			_place_marker(Vector3(0, 0.05, -12))
		1:
			_place_marker(Vector3(0, 0.05, -40))
		4:
			var wid := GameState.equipped_weapon if GameState.equipped_weapon != "" else "m4a1"
			if str(WeaponDB.get_weapon(wid)["class"]) == "pistol":
				wid = "m4a1"
			var pk := Pickup.new()
			pk.position = Vector3(4.6, 0.92, -44.0)
			pk.setup_weapon(wid, -1)
			_pickup(pk)
		5:
			var w: Dictionary = player.weapon()
			var ammo := Pickup.new()
			ammo.position = Vector3(5.8, 0.92, -44.0)
			ammo.setup_ammo(str(w["ammo"]), int(w["mag"]) * 3)
			_pickup(ammo)
		9:
			player.health = 55.0
			var med := Pickup.new()
			med.position = player.global_position + Vector3(1.5, 0.05, -1.0)
			med.setup_medkit()
			_pickup(med)


func _place_marker(p: Vector3) -> void:
	_marker.position = p
	_marker.visible = true


func _process(delta: float) -> void:
	if _done or player == null:
		return
	if _marker.visible:
		_marker.rotation.y += delta
	var pos := player.global_position
	match _step:
		0:
			if Vector2(pos.x, pos.z).distance_to(Vector2(0, -12)) < 1.6:
				_set_step(1)
		1:
			if Vector2(pos.x, pos.z).distance_to(Vector2(0, -40)) < 1.8:
				_set_step(2)
		2:
			if player.velocity.y > 2.0:
				_set_step(3)
		3:
			if player.crouching:
				player.crouching = false
				_set_step(4)
		4:
			if player.has_weapon():
				_set_step(5)
		5:
			if player.reserve_for_current() > int(player.weapon()["mag"]):
				_set_step(6)
		6:
			if _hits >= 3:
				_set_step(7)
		7:
			if _long_hit:
				_set_step(8)
		8:
			if player.is_reloading():
				_set_step(9)
		9:
			if player.health > 80.0:
				_set_step(10)


func _on_target_hit(_target: Node, dist: float) -> void:
	_hits += 1
	if dist > 70.0 and player.aiming:
		_long_hit = true


func _on_hit_confirmed(shooter: Node, _victim: Node, _damage: float, headshot: bool, killed: bool) -> void:
	if shooter == player:
		hud.flash_hit(headshot, killed)


func _complete() -> void:
	_done = true
	_marker.visible = false
	hud.set_objective("", "")
	GameState.trained = true
	GameState.save_state()
	hud.show_end("TRAINING COMPLETE", "You know the basics. Time to drop into Vis Island.")
