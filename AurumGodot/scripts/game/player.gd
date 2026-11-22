extends "res://scripts/game/combatant.gd"
## The local player: over-the-shoulder camera, parachute drop, movement, aiming with real
## scope magnification, recoil, looting and healing. Works with keyboard/mouse and touch.

signal hit_marker(headshot: bool, killed: bool)
signal damaged(amount: float, from_dir: Vector3)
signal pickups_changed

enum State { FREEFALL, CHUTE, GROUND }

const WALK := 2.1
const RUN := 4.6
const SPRINT := 6.3
const CROUCH := 2.0
const JUMP := 4.0
const MOUSE_SENS := 0.0024
const TOUCH_SENS := 0.0045
const BASE_FOV := 72.0

var hud: Node
var state := State.FREEFALL
var aiming := false
var crouching := false
var nearby: Array[Area3D] = []

var _yaw := 0.0
var _pitch := -0.1
var _recoil := 0.0
var _yaw_node: Node3D
var _pitch_node: Node3D
var _arm: SpringArm3D
var camera: Camera3D
var _canopy: Node3D
var _fire_was_held := false
var _mouse_fire := false
var _healing := 0.0
var _land_speed := 0.0


func _ready() -> void:
	display_name = GameState.player_name
	show_tracers = true
	floor_snap_length = 0.5
	_yaw_node = Node3D.new()
	_yaw_node.position = Vector3(0, 1.55, 0)
	add_child(_yaw_node)
	_pitch_node = Node3D.new()
	_yaw_node.add_child(_pitch_node)
	_arm = SpringArm3D.new()
	_arm.spring_length = 7.0
	_arm.collision_mask = LAYER_WORLD
	_arm.margin = 0.2
	_arm.position = Vector3(0.55, 0.15, 0)
	_arm.add_excluded_object(get_rid())
	_pitch_node.add_child(_arm)
	camera = Camera3D.new()
	camera.fov = BASE_FOV
	camera.near = 0.05
	camera.far = 20000.0
	_arm.add_child(camera)
	camera.current = true
	_build_canopy()
	if not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_canopy() -> void:
	_canopy = Node3D.new()
	_canopy.position = Vector3(0, 4.2, 0)
	_canopy.visible = false
	add_child(_canopy)
	var dome := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 3.2
	s.height = 3.2
	s.is_hemisphere = true
	s.radial_segments = 24
	s.rings = 8
	dome.mesh = s
	dome.scale = Vector3(1.0, 0.45, 0.7)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.62, 0.12)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	dome.material_override = m
	_canopy.add_child(dome)
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.2, 0.2, 0.2)
	for k in 6:
		var a := k * TAU / 6.0
		var line := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.01
		c.bottom_radius = 0.01
		c.height = 4.0
		c.radial_segments = 4
		line.mesh = c
		line.material_override = line_mat
		var top := Vector3(cos(a) * 3.0, 0.0, sin(a) * 2.1)
		var bottom := Vector3(0, -3.0, 0)
		var dir := (top - bottom)
		line.transform = Transform3D(_basis_y(dir), (top + bottom) * 0.5)
		_canopy.add_child(line)


static func _basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	return Basis(x, y * dir.length() / 4.0, x.cross(y).normalized())


# --- Input ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not alive:
		return
	var motion := event as InputEventMouseMotion
	if motion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(motion.relative * MOUSE_SENS)
		return
	var mb := event as InputEventMouseButton
	if mb and not DisplayServer.is_touchscreen_available():
		if mb.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_mouse_fire = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			aiming = mb.pressed
	if event.is_action_pressed("reload"):
		start_reload()
	elif event.is_action_pressed("interact"):
		interact()
	elif event.is_action_pressed("switch_weapon"):
		switch_slot()
	elif event.is_action_pressed("fire_mode"):
		cycle_fire_mode()
	elif event.is_action_pressed("heal"):
		start_heal()
	elif event.is_action_pressed("crouch"):
		crouching = not crouching
	elif event.is_action_pressed("jump"):
		jump_or_open_chute()


func _look(delta: Vector2) -> void:
	var zoom := current_zoom()
	_yaw -= delta.x / zoom
	_pitch = clampf(_pitch - delta.y / zoom, deg_to_rad(-80.0), deg_to_rad(65.0))


func current_zoom() -> float:
	if aiming and has_weapon() and state == State.GROUND:
		return float(weapon()["zoom"])
	return 1.0


func jump_or_open_chute() -> void:
	if state == State.FREEFALL:
		_open_chute()
	elif state == State.GROUND and is_on_floor():
		velocity.y = JUMP
		crouching = false


func interact() -> void:
	var best: Area3D = null
	var best_d := INF
	for p in nearby:
		if is_instance_valid(p):
			var d := p.global_position.distance_to(global_position)
			if d < best_d:
				best_d = d
				best = p
	if best == null:
		return
	var kind := str(best.get("kind"))
	match kind:
		"weapon":
			var dropped := give_weapon(str(best.get("weapon_id")), int(best.get("loaded")))
			var w := weapon()
			# A fresh weapon comes with one spare magazine.
			add_ammo(str(w["ammo"]), int(w["mag"]))
			if dropped != "" and get_parent().has_method("drop_weapon"):
				get_parent().call("drop_weapon", dropped, global_position + _forward() * 0.8, int(mags.get(dropped, 0)))
		"ammo":
			add_ammo(str(best.get("ammo_type")), int(best.get("amount")))
		"medkit":
			medkits += 1
	nearby.erase(best)
	best.queue_free()
	pickups_changed.emit()
	weapon_changed.emit()


func start_heal() -> void:
	if medkits <= 0 or health >= MAX_HEALTH or _healing > 0.0:
		return
	_healing = 3.0


func nearest_pickup_text() -> String:
	var best_d := INF
	var text := ""
	for p in nearby:
		if is_instance_valid(p):
			var d := p.global_position.distance_to(global_position)
			if d < best_d:
				best_d = d
				text = str(p.call("describe"))
	return text


func healing_progress() -> float:
	return 1.0 - _healing / 3.0 if _healing > 0.0 else 0.0


# --- Simulation ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	process_weapon(delta)
	if not alive:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	var touch_look: Vector2 = hud.call("consume_look") if hud else Vector2.ZERO
	if touch_look != Vector2.ZERO:
		_look(touch_look * TOUCH_SENS)
	var input := _move_input()
	var yaw_basis := Basis(Vector3.UP, _yaw)
	var wish := yaw_basis * Vector3(input.x, 0, input.y)
	match state:
		State.FREEFALL:
			_air(delta, wish, 55.0, 20.0)
			if global_position.y - _ground_y() < 160.0:
				_open_chute()
		State.CHUTE:
			_air(delta, wish, 5.5, 9.0)
		State.GROUND:
			_ground(delta, wish, input)
	if (state == State.FREEFALL or state == State.CHUTE) and is_on_floor():
		_land()
	_update_camera(delta)
	update_animation(aiming or _mouse_fire)
	_handle_fire()
	if _healing > 0.0:
		_healing -= delta
		if _healing <= 0.0 and medkits > 0:
			medkits -= 1
			heal(75.0)
			pickups_changed.emit()


func _ground_y() -> float:
	var w: Variant = get_parent().get("world")
	if w == null:
		return 0.0
	return float(w.call("height_at", global_position.x, global_position.z))


func _move_input() -> Vector2:
	var v := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_forward", "move_back"))
	if hud:
		var t: Vector2 = hud.get("move_vec")
		if t.length() > v.length():
			v = t
	return v.limit_length(1.0)


func _air(delta: float, wish: Vector3, fall_speed: float, glide: float) -> void:
	velocity.y = move_toward(velocity.y, -fall_speed, GRAVITY * 1.6 * delta)
	var target := wish * glide
	velocity.x = move_toward(velocity.x, target.x, 12.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 12.0 * delta)
	_land_speed = velocity.y
	move_and_slide()
	visual.rotation.y = lerp_angle(visual.rotation.y, _yaw, 4.0 * delta)


func _ground(delta: float, wish: Vector3, input: Vector2) -> void:
	var sprinting := Input.is_action_pressed("sprint") and input.y < -0.5 and not aiming and not crouching
	if hud and bool(hud.get("sprint_lock")) and input.y < -0.5 and not aiming:
		sprinting = true
	var speed := RUN
	if crouching:
		speed = CROUCH
	elif aiming:
		speed = WALK
	elif sprinting:
		speed = SPRINT
	var target := wish * speed
	var accel := 18.0 if is_on_floor() else 3.0
	velocity.x = move_toward(velocity.x, target.x, accel * delta * maxf(speed, 1.0))
	velocity.z = move_toward(velocity.z, target.z, accel * delta * maxf(speed, 1.0))
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
		_land_speed = minf(_land_speed, velocity.y)
	else:
		if _land_speed < -11.0:
			take_hit((-_land_speed - 11.0) * 9.0, self, global_position + Vector3(0, 1.0, 0))
		_land_speed = 0.0
	move_and_slide()
	# Face where the camera looks when aiming/shooting/moving.
	if aiming or _mouse_fire or wish.length() > 0.1:
		visual.rotation.y = lerp_angle(visual.rotation.y, _yaw, 12.0 * delta)
	if character == null:
		visual.scale.y = lerpf(visual.scale.y, 0.72 if crouching else 1.0, 10.0 * delta)
	if global_position.y < -1.5:
		# Swimming: slow and unable to shoot.
		velocity.y = maxf(velocity.y, 0.5)


func _open_chute() -> void:
	if state != State.FREEFALL:
		return
	state = State.CHUTE
	_canopy.visible = true


func _land() -> void:
	state = State.GROUND
	_canopy.visible = false
	_land_speed = 0.0


func _update_camera(delta: float) -> void:
	_recoil = move_toward(_recoil, 0.0, deg_to_rad(9.0) * delta)
	_yaw_node.rotation.y = _yaw
	_pitch_node.rotation.x = _pitch + _recoil
	var zoom := current_zoom()
	camera.fov = lerpf(camera.fov, BASE_FOV / zoom, 14.0 * delta)
	var arm_len := 2.6
	if state != State.GROUND:
		arm_len = 7.0
	elif aiming:
		arm_len = 0.9 if zoom < 2.5 else 0.3
	_arm.spring_length = lerpf(_arm.spring_length, arm_len, 10.0 * delta)


func aim_point() -> Vector3:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * 2000.0
	var exclude: Array[RID] = [get_rid()]
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD | LAYER_BOT, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return to
	return hit["position"]


func spread_multiplier() -> float:
	var m := 1.0
	if aiming:
		m = 0.22
	var horiz := Vector2(velocity.x, velocity.z).length()
	m += clampf(horiz / SPRINT, 0.0, 1.0) * 0.8
	if crouching:
		m *= 0.75
	if not is_on_floor():
		m += 1.5
	return m


func _handle_fire() -> void:
	var held := _mouse_fire or (hud != null and bool(hud.get("fire_held")))
	var just := held and not _fire_was_held
	_fire_was_held = held
	if state != State.GROUND or not held or _healing > 0.0:
		return
	if global_position.y < -1.0:
		return
	try_fire(aim_point(), spread_multiplier(), just)


func _on_fired(w: Dictionary) -> void:
	var kick := deg_to_rad(float(w["recoil"])) * randf_range(0.8, 1.2)
	if aiming:
		kick *= 0.7
	if crouching:
		kick *= 0.8
	_recoil += kick * 0.35
	_pitch = clampf(_pitch + kick * 0.65, deg_to_rad(-80.0), deg_to_rad(65.0))
	_yaw += randf_range(-0.3, 0.3) * kick
	_healing = 0.0


func _on_damaged(amount: float, attacker: Node) -> void:
	var from_dir := Vector3.ZERO
	if attacker is Node3D and attacker != self:
		from_dir = ((attacker as Node3D).global_position - global_position).normalized()
	damaged.emit(amount, from_dir)
	_healing = 0.0


func _forward() -> Vector3:
	return Basis(Vector3.UP, _yaw) * Vector3(0, 0, -1)


func heading_degrees() -> float:
	return fposmod(-rad_to_deg(_yaw), 360.0)


func altitude() -> float:
	return global_position.y - _ground_y()
