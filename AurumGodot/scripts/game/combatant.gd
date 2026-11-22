extends CharacterBody3D
## Shared logic for the player and bots: health, two weapon slots, ammo, firing with real
## projectile ballistics, reloading, fire modes, hit zones (head / body / legs) and death.

signal died(victim: Node, killer: Node)
signal health_changed(value: float)
signal weapon_changed

const WeaponDB := preload("res://scripts/game/weapon_db.gd")
const SoldierMesh := preload("res://scripts/game/soldier_mesh.gd")
const Sfx := preload("res://scripts/game/sfx.gd")
const RealisticCharacter := preload("res://scripts/game/realistic_character.gd")

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_BOT := 4
const LAYER_PICKUP := 8
const GRAVITY := 9.81
const MAX_HEALTH := 100.0
const HEAD_HEIGHT := 1.5

var display_name := "Soldier"
var health := MAX_HEALTH
var alive := true
var kills := 0
var ballistics: Node
var show_tracers := true
var infinite_reserve := false

var weapons: Array[String] = []
var slot := 0
var mags := {}
var reserve := {}
var fire_mode := 0
var medkits := 0

var visual: Node3D
var body_mesh: MeshInstance3D
## Realistic animated body (null when the stylised fallback soldier is used).
var character: RealisticCharacter
var weapon_socket: Node3D
var weapon_node: Node3D
var muzzle: Node3D

var _cooldown := 0.0
var _reload_left := 0.0
var _flash_t := 0.0
var _flash_light: OmniLight3D
var _flash_mesh: MeshInstance3D
var _audio: AudioStreamPlayer3D
var _fx_audio: AudioStreamPlayer3D


func setup_body(accent: Color, layer: int, character_id: String = "", outfit: String = "original") -> void:
	collision_layer = layer
	collision_mask = LAYER_WORLD | LAYER_PLAYER | LAYER_BOT
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.33
	cap.height = 1.8
	shape.shape = cap
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	if character_id != "":
		var rc := RealisticCharacter.new()
		visual.add_child(rc)
		if rc.setup(character_id, outfit):
			character = rc
			weapon_socket = rc.weapon_socket
		else:
			rc.queue_free()
	if character == null:
		body_mesh = SoldierMesh.create(accent)
		body_mesh.rotation.y = PI # the soldier model faces +Z; gameplay forward is -Z
		visual.add_child(body_mesh)
		weapon_socket = Node3D.new()
		body_mesh.add_child(weapon_socket)
		weapon_socket.transform = SoldierMesh.weapon_transform()
	_audio = AudioStreamPlayer3D.new()
	_audio.max_polyphony = 6
	_audio.unit_size = 14.0
	_audio.max_distance = 700.0
	add_child(_audio)
	_fx_audio = AudioStreamPlayer3D.new()
	_fx_audio.unit_size = 4.0
	_fx_audio.max_distance = 40.0
	add_child(_fx_audio)


# --- Weapons -------------------------------------------------------------------

func has_weapon() -> bool:
	return slot < weapons.size()


func current_id() -> String:
	return weapons[slot] if has_weapon() else ""


func weapon() -> Dictionary:
	return WeaponDB.get_weapon(current_id())


func rounds_in_mag() -> int:
	return int(mags.get(current_id(), 0))


func reserve_for_current() -> int:
	if not has_weapon():
		return 0
	return int(reserve.get(str(weapon()["ammo"]), 0))


func is_reloading() -> bool:
	return _reload_left > 0.0


func fire_mode_name() -> String:
	if not has_weapon():
		return ""
	var modes: Array = weapon()["modes"]
	return str(modes[fire_mode % modes.size()]).to_upper()


## Adds a weapon. Returns the id that had to be dropped to make room ("" if none).
func give_weapon(id: String, loaded: int = -1) -> String:
	var w := WeaponDB.get_weapon(id)
	var dropped := ""
	if weapons.has(id):
		var ammo := str(w["ammo"])
		reserve[ammo] = int(reserve.get(ammo, 0)) + int(w["mag"])
		return ""
	if weapons.size() < 2:
		weapons.append(id)
		slot = weapons.size() - 1
	else:
		dropped = weapons[slot]
		weapons[slot] = id
	mags[id] = int(w["mag"]) if loaded < 0 else loaded
	fire_mode = 0
	_reload_left = 0.0
	_attach_weapon_model(id)
	weapon_changed.emit()
	return dropped


func switch_slot() -> void:
	if weapons.size() < 2:
		return
	slot = (slot + 1) % weapons.size()
	fire_mode = 0
	_reload_left = 0.0
	_cooldown = 0.35
	_attach_weapon_model(current_id())
	weapon_changed.emit()


func cycle_fire_mode() -> void:
	if not has_weapon():
		return
	var modes: Array = weapon()["modes"]
	fire_mode = (fire_mode + 1) % modes.size()
	_play_fx(Sfx.click())
	weapon_changed.emit()


func _attach_weapon_model(id: String) -> void:
	if weapon_node:
		weapon_node.queue_free()
		weapon_node = null
		muzzle = null
	var w := WeaponDB.get_weapon(id)
	var length := float(w["length"])
	var grip_frac := 0.22 if str(w["class"]) == "pistol" else 0.34
	# Grip point in model space (muzzle along -Z, model centred on its bounding box).
	var grip := Vector3(0.0, -0.04, length * 0.5 - grip_frac * length)
	var holder := Node3D.new()
	holder.name = "Weapon"
	if character:
		# Realistic body: the socket sits in the right hand and already points along the aim (-Z).
		holder.transform = Transform3D(Basis(), -grip)
	else:
		var rot := Basis(Vector3.UP, -PI * 0.5) # model -Z -> socket +X
		holder.transform = Transform3D(rot, Vector3(-0.03, -0.075, 0.0) - rot * grip)
	weapon_socket.add_child(holder)
	var path := WeaponDB.model_path(id)
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene:
			holder.add_child(scene.instantiate())
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0.02, -length * 0.5 - 0.02)
	holder.add_child(muzzle)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.75, 0.4)
	_flash_light.light_energy = 4.0
	_flash_light.omni_range = 5.0
	_flash_light.visible = false
	muzzle.add_child(_flash_light)
	_flash_mesh = MeshInstance3D.new()
	var q := SphereMesh.new()
	q.radius = 0.05
	q.height = 0.1
	q.radial_segments = 8
	q.rings = 4
	_flash_mesh.mesh = q
	_flash_mesh.scale = Vector3(1.0, 1.0, 2.2)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.8, 0.35)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.7, 0.3)
	fm.emission_energy_multiplier = 6.0
	_flash_mesh.material_override = fm
	_flash_mesh.visible = false
	_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	muzzle.add_child(_flash_mesh)
	weapon_node = holder
	if bool(w.get("suppressed", false)):
		_flash_light.light_energy = 0.8


## Fires toward `target` if possible. `just_pressed` is required for semi / pump / bolt.
func try_fire(target: Vector3, spread_mult: float, just_pressed: bool) -> bool:
	if not alive or not has_weapon() or is_reloading() or _cooldown > 0.0 or ballistics == null:
		return false
	var w := weapon()
	var modes: Array = w["modes"]
	var mode := str(modes[fire_mode % modes.size()])
	if mode != "auto" and not just_pressed:
		return false
	var id := current_id()
	if int(mags.get(id, 0)) <= 0:
		if just_pressed:
			_play_fx(Sfx.click())
			start_reload()
		return false
	mags[id] = int(mags[id]) - 1
	_cooldown = WeaponDB.fire_interval(w)
	var origin := muzzle.global_position if muzzle else global_position + Vector3(0, 1.4, 0)
	var dir := (target - origin).normalized()
	var pellets := int(w.get("pellets", 1))
	var spread := float(w["spread"]) * spread_mult
	if pellets > 1:
		spread = maxf(spread, 3.5)
	for i in pellets:
		ballistics.call("fire", origin, spread_dir(dir, spread), float(w["velocity"]), float(w["damage"]), self, show_tracers and (pellets == 1 or i < 3))
	_flash_t = 0.05
	_play_shot(w)
	_on_fired(w)
	if int(mags[id]) == 0 and reserve_for_current() > 0:
		start_reload()
	return true


## Random direction inside a cone of `deg` degrees (full angle) around `dir`.
static func spread_dir(dir: Vector3, deg: float) -> Vector3:
	if deg <= 0.0:
		return dir
	var a := deg_to_rad(deg) * 0.5 * sqrt(randf())
	var phi := randf() * TAU
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var x := dir.cross(up).normalized()
	var y := x.cross(dir).normalized()
	return (dir * cos(a) + (x * cos(phi) + y * sin(phi)) * sin(a)).normalized()


func start_reload() -> void:
	if not has_weapon() or is_reloading():
		return
	var w := weapon()
	var need := int(w["mag"]) - rounds_in_mag()
	if need <= 0:
		return
	if not infinite_reserve and reserve_for_current() <= 0:
		return
	_reload_left = float(w["reload"])
	_play_fx(Sfx.reload_sound())


func _finish_reload() -> void:
	if not has_weapon():
		return
	var w := weapon()
	var id := current_id()
	var ammo := str(w["ammo"])
	var need := int(w["mag"]) - rounds_in_mag()
	var take := need if infinite_reserve else mini(need, int(reserve.get(ammo, 0)))
	mags[id] = rounds_in_mag() + take
	if not infinite_reserve:
		reserve[ammo] = int(reserve.get(ammo, 0)) - take
	weapon_changed.emit()


func add_ammo(ammo: String, amount: int) -> void:
	reserve[ammo] = int(reserve.get(ammo, 0)) + amount
	weapon_changed.emit()


func process_weapon(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_reload_left = 0.0
			_finish_reload()
	if _flash_t > 0.0:
		_flash_t -= delta
	var show := _flash_t > 0.0
	if _flash_light:
		_flash_light.visible = show
	if _flash_mesh:
		_flash_mesh.visible = show
		if show:
			_flash_mesh.rotation.z = randf() * TAU


## Drives the realistic body's animation from movement and weapon state.
func update_animation(aiming: bool) -> void:
	if character == null:
		return
	var horiz := Vector2(velocity.x, velocity.z).length()
	var pistol := has_weapon() and str(weapon()["class"]) == "pistol"
	character.set_state(horiz, has_weapon(), pistol, aiming, not is_on_floor() and absf(velocity.y) > 1.0)


# --- Damage --------------------------------------------------------------------

func take_hit(damage: float, attacker: Node, point: Vector3) -> Dictionary:
	if not alive:
		return {"damage": 0.0, "headshot": false, "killed": false}
	var local_y := point.y - global_position.y
	var head := local_y > HEAD_HEIGHT
	var mult := WeaponDB.HEADSHOT if head else (WeaponDB.LIMB if local_y < 0.8 else 1.0)
	var dmg := damage * mult
	health = maxf(health - dmg, 0.0)
	health_changed.emit(health)
	_on_damaged(dmg, attacker)
	var killed := false
	if health <= 0.0:
		die(attacker)
		killed = true
	return {"damage": dmg, "headshot": head, "killed": killed}


func heal(amount: float) -> void:
	if not alive:
		return
	health = minf(health + amount, MAX_HEALTH)
	health_changed.emit(health)


func die(killer: Node) -> void:
	if not alive:
		return
	alive = false
	health = 0.0
	if killer and killer != self and "kills" in killer:
		killer.set("kills", int(killer.get("kills")) + 1)
	collision_layer = 0
	collision_mask = LAYER_WORLD
	_flash_t = 0.0
	if visual:
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(visual, "rotation:x", -PI * 0.5, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(visual, "position:y", 0.25, 0.45)
	died.emit(self, killer)


# --- Sound -----------------------------------------------------------------------

func _play_shot(w: Dictionary) -> void:
	var kind := "rifle"
	if bool(w.get("suppressed", false)):
		kind = "suppressed"
	else:
		match str(w["class"]):
			"pistol":
				kind = "pistol"
			"smg":
				kind = "smg"
			"shotgun":
				kind = "shotgun"
			"sniper", "dmr":
				kind = "sniper"
	_audio.stream = Sfx.gunshot(kind)
	_audio.pitch_scale = randf_range(0.94, 1.06)
	_audio.play()


func _play_fx(stream: AudioStream) -> void:
	if _fx_audio:
		_fx_audio.stream = stream
		_fx_audio.play()


# --- Hooks for subclasses -----------------------------------------------------------

func _on_fired(_w: Dictionary) -> void:
	pass


func _on_damaged(_amount: float, _attacker: Node) -> void:
	pass
