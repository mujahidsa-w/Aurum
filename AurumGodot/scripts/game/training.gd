extends Node
## Training ground. Mostly about movement: walking quietly, sprinting, jumping hurdles, a low
## tunnel that can only be passed crouched, barbed wire that can only be passed prone and
## getting back up. Then an armory with every weapon in the game and a shooting range
## (prone + scope at 100 m, reload, heal). Finishing marks the player as trained.

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
		return Vector2(900, 900)


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

const LANE_HALF := 3.2
const RINGS := {
	0: Vector3(0, 0.05, -10), 1: Vector3(0, 0.05, -24), 2: Vector3(0, 0.05, -50),
	3: Vector3(0, 0.05, -77), 4: Vector3(0, 0.05, -99), 5: Vector3(0, 0.05, -120),
	6: Vector3(12, 0.05, -138),
}
const ARMORY := Vector3(17.0, 0.0, -138.0)
const FIRING_LINE := -150.0

var _step := 0
var _hits := 0
var _long_hit := false
var _timer := 0.0
var _done := false
var _marker: MeshInstance3D
var _ui_audio: AudioStreamPlayer
## Armory slots that restock after being taken: [kind, id_or_ammo, amount, position, pickup].
var _stock: Array = []
var _stock_t := 0.0

var _steps := [
	["Move", "Walk to the glowing ring.   WASD  /  left joystick.   Look with the mouse  /  right side of the screen."],
	["Walk quietly", "Hold ALT  (or push the joystick only a little)  to walk slowly - your footsteps get quiet.   Walk to the next ring."],
	["Sprint", "Hold SHIFT  /  tap the sprint button and sprint down the track.   Sprinting is fast and loud, and you cannot shoot."],
	["Jump", "Jump over the three hurdles.   SPACE  /  jump button.   Keep your speed - momentum carries the jump."],
	["Crouch", "The tunnel is too low to stand in.   Crouch (C  /  crouch button) and move through it."],
	["Prone", "Go prone (Z  /  prone button) and crawl under the barbed wire.   Prone is slow but very hard to spot and hit."],
	["Get up", "Stand up and run to the armory.   SPACE gets you up: prone -> crouch -> stand.   Sprinting also stands you up."],
	["Armory", "Every weapon in the game is on the racks.   Walk up to any gun and pick it up.   F  /  hand button."],
	["Ammo", "Each crate is labelled with its calibre.   Grab ammo that fits your weapon."],
	["Shoot", "Go to the firing line and hit 3 steel targets.   Left mouse  /  fire button."],
	["Prone + scope", "Go prone, aim down sights and hit the 100 m target.   Prone: less recoil and spread.   Right mouse  /  scope button."],
	["Reload", "Reload your weapon.   R  /  reload button."],
	["Heal", "You are hurt.   Pick up the first aid kit and use it.   H  /  medkit button."],
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
	_build_course()
	_build_armory()
	_build_range()
	_build_marker()
	_spawn_player()
	hud.player = player
	hud.battle = self
	hud.hide_loading()
	_set_step(0)


func _setup_input() -> void:
	var binds := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT], "jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "crouch": [KEY_C, KEY_CTRL],
		"prone": [KEY_Z], "reload": [KEY_R], "interact": [KEY_F, KEY_E], "switch_weapon": [KEY_Q, KEY_1, KEY_2],
		"fire_mode": [KEY_B], "heal": [KEY_H],
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


func _flat(color: Color, roughness: float = 0.8, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


## Solid box (visual + collision). `pos` is the centre.
func _block(size: Vector3, pos: Vector3, mat: Material, collide: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		body.position = pos
		add_child(body)
	return mi


func _sign(text: String, pos: Vector3, size: int = 64) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.006
	l.outline_size = 12
	l.modulate = Color(1.0, 0.85, 0.3)
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.position = pos
	add_child(l)


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
	env.fog_enabled = true
	env.fog_density = 0.0012
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.light_energy = 1.4
	sun.directional_shadow_max_distance = 160.0
	add_child(sun)
	sun.rotation_degrees = Vector3(-50, -35, 0)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(900, 900)
	ground.mesh = pm
	ground.material_override = _textured("grass", 0.2)
	ground.position = Vector3(0, 0, -200)
	add_child(ground)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	body.add_child(cs)
	add_child(body)


## Movement course along -Z: track, sprint lane, hurdles, crouch tunnel, prone wire.
func _build_course() -> void:
	var dirt := _textured("dirt", 0.15)
	var track := MeshInstance3D.new()
	var tm := PlaneMesh.new()
	tm.size = Vector2(LANE_HALF * 2.0, 128)
	track.mesh = tm
	track.material_override = dirt
	track.position = Vector3(0, 0.01, -62)
	add_child(track)
	var white := _flat(Color(0.95, 0.95, 0.92), 0.6)
	# Sprint lane markers every 10 m.
	for i in 6:
		_block(Vector3(LANE_HALF * 2.0, 0.02, 0.12), Vector3(0, 0.015, -26.0 - i * 4.8), white, false)
	_sign("SPRINT", Vector3(-4.6, 2.4, -30))
	# Side walls enclose the obstacle section so it has to be crossed.
	var wall := _textured("concrete", 0.4)
	for side in [-1.0, 1.0]:
		_block(Vector3(0.3, 1.3, 72.0), Vector3(side * (LANE_HALF + 0.15), 0.65, -88.0), wall)
	# Hurdles (0.55 m): too high to step over, easy to jump.
	var wood := _flat(Color(0.46, 0.33, 0.2), 0.85)
	for z in [-58.0, -64.0, -70.0]:
		_block(Vector3(LANE_HALF * 2.0, 0.55, 0.32), Vector3(0, 0.275, z), wood)
	_sign("JUMP", Vector3(-4.6, 2.4, -60))
	# Crouch tunnel: roof at 1.45 m (standing needs 1.8 m, crouching 1.25 m).
	var roof := _textured("concrete", 0.3)
	_block(Vector3(LANE_HALF * 2.0 + 0.6, 0.5, 12.0), Vector3(0, 1.7, -88.0), roof)
	for z in [-82.0, -88.0, -94.0]:
		for side in [-1.0, 1.0]:
			_block(Vector3(0.4, 1.45, 0.4), Vector3(side * (LANE_HALF - 0.1), 0.725, z), roof, false)
	_sign("CROUCH", Vector3(0, 2.4, -81.5))
	# Barbed wire: open below 0.8 m, so only prone fits (prone needs 0.62 m).
	var net := StandardMaterial3D.new()
	net.albedo_color = Color(0.25, 0.3, 0.18, 0.82)
	net.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	net.cull_mode = BaseMaterial3D.CULL_DISABLED
	_block(Vector3(LANE_HALF * 2.0, 0.7, 12.0), Vector3(0, 1.15, -110.0), net)
	var steel := _flat(Color(0.35, 0.35, 0.35), 0.4, 0.8)
	for z in range(-104, -117, -2):
		for side in [-1.0, 1.0]:
			_block(Vector3(0.08, 1.5, 0.08), Vector3(side * (LANE_HALF - 0.2), 0.75, float(z)), steel, false)
	for i in 5:
		var wire := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.012
		cm.bottom_radius = 0.012
		cm.height = 12.0
		cm.radial_segments = 4
		wire.mesh = cm
		wire.material_override = steel
		wire.rotation.x = PI * 0.5
		wire.position = Vector3(-LANE_HALF + 0.4 + i * 1.35, 0.8, -110.0)
		add_child(wire)
	_sign("PRONE", Vector3(0, 2.4, -103.5))


## Open-sided armory with every weapon on racks plus ammo crates per calibre and medkits.
func _build_armory() -> void:
	var pad := _textured("concrete", 0.35)
	_block(Vector3(14.0, 0.12, 20.0), ARMORY + Vector3(0, 0.06, 0), pad)
	_block(Vector3(14.6, 0.25, 20.6), ARMORY + Vector3(0, 3.4, 0), pad)
	var metal := _flat(Color(0.3, 0.32, 0.3), 0.5, 0.6)
	for dx in [-6.8, 6.8]:
		for dz in [-9.8, 9.8]:
			_block(Vector3(0.3, 3.3, 0.3), ARMORY + Vector3(dx, 1.65, dz), metal)
	_block(Vector3(0.3, 2.2, 20.0), ARMORY + Vector3(6.85, 1.1, 0), metal)
	_sign("ARMORY", ARMORY + Vector3(0, 4.2, 0), 96)
	var light := OmniLight3D.new()
	light.position = ARMORY + Vector3(0, 3.0, 0)
	light.omni_range = 14.0
	light.light_energy = 1.2
	add_child(light)
	# Racks (tables) along the back wall.
	var ids: Array = WeaponDB.WEAPONS.keys()
	var table_mat := _flat(Color(0.4, 0.29, 0.18), 0.8)
	var per_table := 4
	var tables := int(ceil(ids.size() / float(per_table)))
	for t in tables:
		var z := ARMORY.z - 7.5 + t * 5.0
		_block(Vector3(1.2, 0.9, 4.4), Vector3(ARMORY.x + 5.4, 0.57, z), table_mat)
		for k in per_table:
			var i := t * per_table + k
			if i >= ids.size():
				break
			var pos := Vector3(ARMORY.x + 5.4, 1.03, z - 1.6 + k * 1.07)
			_stock.append(["weapon", str(ids[i]), 0, pos, null])
	# Ammo crates (one per calibre) along the front edge.
	var calibres: Array = WeaponDB.AMMO.keys()
	for i in calibres.size():
		var pos := Vector3(ARMORY.x - 4.5 + (i % 5) * 1.5, 0.13, ARMORY.z + 8.0 - int(i / 5) * 1.4)
		var stack := int(WeaponDB.AMMO[calibres[i]]["stack"])
		_stock.append(["ammo", str(calibres[i]), stack, pos, null])
	for i in 2:
		_stock.append(["medkit", "", 1, Vector3(ARMORY.x - 5.5, 0.13, ARMORY.z - 8.0 + i * 1.0), null])
	for slot in _stock:
		_restock(slot)


func _restock(slot: Array) -> void:
	var pk := Pickup.new()
	pk.position = slot[3]
	match str(slot[0]):
		"weapon":
			pk.setup_weapon(str(slot[1]), -1)
		"ammo":
			pk.setup_ammo(str(slot[1]), int(slot[2]))
		_:
			pk.setup_medkit()
	_pickup(pk)
	slot[4] = pk


## Shooting range beyond the course: targets at ~15-25 m, 50 m, 100 m and 200 m.
func _build_range() -> void:
	var dirt := _textured("dirt", 0.12)
	var lane := MeshInstance3D.new()
	var lm := PlaneMesh.new()
	lm.size = Vector2(16, 220)
	lane.mesh = lm
	lane.material_override = dirt
	lane.position = Vector3(0, 0.012, FIRING_LINE - 110.0)
	add_child(lane)
	_block(Vector3(16.0, 0.05, 0.25), Vector3(0, 0.03, FIRING_LINE), _flat(Color(1.0, 0.8, 0.15), 0.5), false)
	_sign("FIRING LINE", Vector3(-9.0, 2.0, FIRING_LINE))
	var sandbag := _flat(Color(0.55, 0.5, 0.36), 0.95)
	_block(Vector3(3.0, 0.5, 0.6), Vector3(5.5, 0.25, FIRING_LINE - 0.6), sandbag)
	for i in 3:
		_target(Vector3(-4.0 + i * 4.0, 0.0, FIRING_LINE - 15.0 - i * 5.0), 0.35)
	_target(Vector3(-5.0, 0.0, FIRING_LINE - 50.0), 0.45)
	_target(Vector3(0.0, 0.0, FIRING_LINE - 100.0), 0.6)
	_target(Vector3(5.0, 0.0, FIRING_LINE - 200.0), 0.8)
	_sign("100 m", Vector3(0, 2.8, FIRING_LINE - 100.0), 90)
	_sign("200 m", Vector3(5, 3.2, FIRING_LINE - 200.0), 110)
	# Earth berm behind the targets.
	_block(Vector3(40.0, 8.0, 6.0), Vector3(0, 4.0, FIRING_LINE - 215.0), _textured("dirt", 0.1))


func _target(pos: Vector3, radius: float) -> void:
	var t := Target.new()
	t.build(radius)
	t.position = pos
	t.hit.connect(_on_target_hit)
	add_child(t)


func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 1.6
	ring.outer_radius = 1.85
	ring.rings = 40
	_marker.mesh = ring
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(1.0, 0.78, 0.1)
	mm.emission_enabled = true
	mm.emission = Color(1.0, 0.7, 0.1)
	mm.emission_energy_multiplier = 3.0
	_marker.material_override = mm
	_marker.visible = false
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
	SceneRouter.go("res://scenes/lobby.tscn", "LOBBY")


# --- Steps ------------------------------------------------------------------------------------

func _set_step(i: int) -> void:
	_step = i
	_timer = 0.0
	if i >= _steps.size():
		_complete()
		return
	var s: Array = _steps[i]
	hud.set_objective("Training  %d/%d  ·  %s" % [i + 1, _steps.size(), str(s[0])], str(s[1]))
	_ui_audio.stream = Sfx.hit_marker()
	_ui_audio.play()
	_marker.visible = RINGS.has(i)
	if RINGS.has(i):
		_marker.position = RINGS[i]
	match i:
		9:
			_hits = 0
		12:
			player.health = 55.0
			player.health_changed.emit(player.health)
			var med := Pickup.new()
			med.position = player.global_position + Vector3(1.5, 0.05, -1.0)
			med.setup_medkit()
			_pickup(med)


func _at_ring(i: int) -> bool:
	var r: Vector3 = RINGS[i]
	var pos := player.global_position
	return Vector2(pos.x, pos.z).distance_to(Vector2(r.x, r.z)) < 2.0


func _process(delta: float) -> void:
	if player == null:
		return
	_restock_tick(delta)
	if _done:
		return
	if _marker.visible:
		_marker.rotation.y += delta
	var horiz := Vector2(player.velocity.x, player.velocity.z).length()
	match _step:
		0:
			if _at_ring(0):
				_set_step(1)
		1:
			if horiz > 0.4 and horiz < 2.3 and player.stance == PlayerScript.STAND:
				_timer += delta
			if _at_ring(1) and _timer > 1.2:
				_set_step(2)
			elif _at_ring(1):
				hud.set_objective("Training  2/%d  ·  Walk quietly" % _steps.size(), "Too fast!  Hold ALT or push the joystick gently and walk slowly to the ring.")
		2:
			if player.sprinting and horiz > 5.0:
				_timer += delta
			if _at_ring(2) and _timer > 1.0:
				_set_step(3)
		3:
			if _at_ring(3):
				_set_step(4)
		4:
			if _at_ring(4):
				_set_step(5)
		5:
			if _at_ring(5):
				_set_step(6)
		6:
			if _at_ring(6) and player.stance == PlayerScript.STAND:
				_set_step(7)
		7:
			if player.has_weapon():
				_set_step(8)
		8:
			if player.has_weapon() and player.reserve_for_current() > int(player.weapon()["mag"]):
				_set_step(9)
		9:
			if _hits >= 3:
				_set_step(10)
		10:
			if _long_hit:
				_set_step(11)
		11:
			if player.is_reloading():
				_set_step(12)
		12:
			if player.health > 80.0:
				_set_step(13)


## Re-fills armory slots a few seconds after something was taken.
func _restock_tick(delta: float) -> void:
	_stock_t += delta
	if _stock_t < 0.5:
		return
	_stock_t = 0.0
	for slot in _stock:
		var pk: Variant = slot[4]
		if pk == null:
			continue
		if not is_instance_valid(pk) or (pk as Node).is_queued_for_deletion():
			slot[4] = null
			get_tree().create_timer(3.0).timeout.connect(_restock_if_empty.bind(slot))


func _restock_if_empty(slot: Array) -> void:
	if is_inside_tree() and slot[4] == null:
		_restock(slot)


func _on_target_hit(_target: Node, dist: float) -> void:
	_hits += 1
	if dist > 70.0 and player.aiming and player.stance == PlayerScript.PRONE:
		_long_hit = true
	elif dist > 70.0 and _step == 10:
		hud.set_objective("Training  11/%d  ·  Prone + scope" % _steps.size(), "Good hit - now do it while PRONE and aiming down sights.")


func _on_hit_confirmed(shooter: Node, _victim: Node, _damage: float, headshot: bool, killed: bool) -> void:
	if shooter == player:
		hud.flash_hit(headshot, killed)


func _complete() -> void:
	_done = true
	_marker.visible = false
	hud.set_objective("", "")
	GameState.trained = true
	GameState.save_state()
	hud.show_end("TRAINING COMPLETE", "You know how to move, loot and shoot. The course stays open for practice - or drop into Vis Island.", true)
