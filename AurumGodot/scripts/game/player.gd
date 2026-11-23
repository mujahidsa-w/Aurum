extends "res://scripts/game/combatant.gd"
## The local player: over-the-shoulder camera, parachute drop, movement, aiming with real
## scope magnification, recoil, looting and healing. Works with keyboard/mouse and touch.

signal hit_marker(headshot: bool, killed: bool)
signal damaged(amount: float, from_dir: Vector3)
signal pickups_changed

enum State { FREEFALL, CHUTE, GROUND }

# Speeds (m/s) and inertia tuned for a heavy, grounded feel.
const WALK := 1.7
const RUN := 4.7
const SPRINT := 6.3
const CROUCH_SPEED := 2.2
const PRONE_SPEED := 1.15
const JUMP := 4.3
const ACCEL := 11.0
const SPRINT_ACCEL := 7.0
const DECEL := 15.0
const AIR_ACCEL := 6.0
## Body turn rate (rad/s) per posture; sprinting turns wide.
const TURN_RATE := [7.5, 5.5, 1.9]
const SPRINT_TURN := 3.6
const CAMERA_HEIGHT := [1.55, 1.12, 0.6]
const MOUSE_SENS := 0.0024
const TOUCH_SENS := 0.0045
const BASE_FOV := 72.0

var hud: Node
var state := State.FREEFALL
var aiming := false
## Compatibility with the HUD/tutorial: crouching maps onto the stance system.
var crouching: bool:
	get:
		return stance == CROUCH
	set(value):
		if value:
			set_stance(CROUCH)
		elif stance == CROUCH:
			set_stance(STAND)
var proning: bool:
	get:
		return stance == PRONE
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
var _landing_t := 0.0
var _air_time := 0.0
var _cam_height := 1.55
var _cam_dip := 0.0
var _cam_dip_v := 0.0
var _bob_phase := 0.0
var _cam_follow := Vector3.ZERO
## Number of stance changes / jumps performed (used by the training course).
var jumps_done := 0


func _ready() -> void:
	display_name = GameState.player_name
	show_tracers = true
	floor_snap_length = 0.5
	_yaw_node = Node3D.new()
	_yaw_node.position = Vector3(0, 1.55, 0)
	add_child(_yaw_node)
	# The camera rig follows the body with a slight lag for weight.
	_yaw_node.top_level = true
	_cam_follow = global_position
	_yaw_node.global_position = global_position + Vector3(0, 1.55, 0)
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
		toggle_crouch()
	elif event.is_action_pressed("prone"):
		toggle_prone()
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
		return
	if state != State.GROUND or not is_on_floor() or stance_locked():
		return
	# Like PC shooters: jump from prone gets you to a crouch, from a crouch you stand up.
	if stance == PRONE:
		set_stance(CROUCH)
		return
	if stance == CROUCH:
		set_stance(STAND)
		return
	if _landing_t > 0.12 or global_position.y < -1.2:
		return
	velocity.y = JUMP
	jumps_done += 1


func toggle_crouch() -> void:
	if state != State.GROUND or stance_locked() or global_position.y < -1.2:
		return
	set_stance(STAND if stance == CROUCH else CROUCH)


func toggle_prone() -> void:
	if state != State.GROUND or stance_locked() or not is_on_floor() or global_position.y < -1.2:
		return
	set_stance(CROUCH if stance == PRONE else PRONE)


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
	process_stance(delta)
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
	if state == State.GROUND:
		process_footsteps(delta)
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
	_landing_t = maxf(_landing_t - delta, 0.0)
	var in_water := global_position.y < -1.2
	if in_water and stance != STAND:
		set_stance(STAND)
	var want_sprint := Input.is_action_pressed("sprint") or (hud != null and bool(hud.get("sprint_lock")))
	want_sprint = want_sprint and input.y < -0.5 and not aiming and _healing <= 0.0 and not in_water
	# Sprinting from a crouch or prone gets the character up first.
	if want_sprint and stance != STAND and not stance_locked() and is_on_floor():
		set_stance(STAND if stance == CROUCH else CROUCH)
	sprinting = want_sprint and stance == STAND and not stance_locked()
	var speed := RUN
	match stance:
		CROUCH:
			speed = CROUCH_SPEED * (0.65 if aiming else 1.0)
		PRONE:
			speed = PRONE_SPEED * (0.5 if aiming else 1.0)
		_:
			if sprinting:
				speed = SPRINT
			elif aiming:
				speed = WALK
			elif Input.is_key_pressed(KEY_ALT):
				speed = WALK
	# Moving backwards or sideways is slower than forwards.
	if input.y > 0.2:
		speed *= 0.72
	elif absf(input.x) > 0.6 and input.y > -0.3:
		speed *= 0.88
	if stance_locked():
		speed *= 0.0 if stance == PRONE else 0.35
	if _landing_t > 0.0:
		speed *= 0.45
	if _healing > 0.0:
		speed = minf(speed, WALK)
	if is_reloading() and sprinting:
		speed = RUN
	var target := wish * speed
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var rate := ACCEL
	if target.length() < horiz.length() - 0.05:
		rate = DECEL
	elif sprinting:
		rate = SPRINT_ACCEL
	if not is_on_floor():
		rate = AIR_ACCEL
	horiz = horiz.move_toward(target, rate * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
		_land_speed = minf(_land_speed, velocity.y)
		_air_time += delta
	else:
		if _air_time > 0.25 and _land_speed < -4.5:
			_on_landed(-_land_speed)
		if _land_speed < -11.0:
			take_hit((-_land_speed - 11.0) * 9.0, self, global_position + Vector3(0, 1.0, 0))
		_land_speed = 0.0
		_air_time = 0.0
	move_and_slide()
	_turn_body(delta, horiz)
	if character == null:
		visual.scale.y = lerpf(visual.scale.y, float([1.0, 0.72, 0.3][stance]), 10.0 * delta)
	if in_water:
		# Swimming: slow and unable to shoot.
		velocity.y = maxf(velocity.y, 0.5)


## Turns the body toward the aim (when aiming/shooting) or the movement direction, with a
## limited turn rate so it never snaps.
func _turn_body(delta: float, horiz: Vector3) -> void:
	var target_yaw := visual.rotation.y
	var rate: float = TURN_RATE[stance]
	if aiming or _mouse_fire or (hud != null and bool(hud.get("fire_held"))):
		target_yaw = _yaw
		rate = maxf(rate * 1.6, 3.0)
	elif horiz.length() > 0.3:
		target_yaw = atan2(-horiz.x, -horiz.z)
		if sprinting:
			rate = SPRINT_TURN
	else:
		return
	var diff := angle_difference(visual.rotation.y, target_yaw)
	var step := clampf(diff * minf(1.0, 9.0 * delta), -rate * delta, rate * delta)
	visual.rotation.y += step


func _on_landed(impact: float) -> void:
	_landing_t = clampf(impact / 18.0, 0.12, 0.5)
	_cam_dip_v -= clampf(impact * 0.06, 0.15, 0.9)
	play_body_sound(Sfx.land_thud(), clampf(-14.0 + impact, -12.0, 0.0))
	if character and impact > 6.0 and stance == STAND:
		character.play_action("land", 0.32 + _landing_t * 0.5, 0.08)


func _open_chute() -> void:
	if state != State.FREEFALL:
		return
	state = State.CHUTE
	_canopy.visible = true


func _land() -> void:
	state = State.GROUND
	_canopy.visible = false
	_on_landed(8.0)
	_land_speed = 0.0


func _update_camera(delta: float) -> void:
	_recoil = move_toward(_recoil, 0.0, deg_to_rad(9.0) * delta)
	# Pivot height follows the posture; the rig trails the body slightly.
	_cam_height = lerpf(_cam_height, float(CAMERA_HEIGHT[stance]), 1.0 - exp(-7.0 * delta))
	var follow_k := 16.0 if state == State.GROUND else 80.0
	_cam_follow = _cam_follow.lerp(global_position, 1.0 - exp(-follow_k * delta))
	if _cam_follow.distance_to(global_position) > 4.0:
		_cam_follow = global_position
	# Landing dip (spring) and head bob from footsteps.
	_cam_dip_v += (-_cam_dip * 90.0 - _cam_dip_v * 12.0) * delta
	_cam_dip += _cam_dip_v * delta
	var horiz := Vector2(velocity.x, velocity.z).length()
	var bob := 0.0
	if state == State.GROUND and is_on_floor() and horiz > 0.5 and not aiming:
		_bob_phase += delta * horiz * (2.1 if stance == STAND else 1.6)
		var amp := 0.012 + clampf(horiz / SPRINT, 0.0, 1.0) * 0.03
		if stance == PRONE:
			amp *= 0.4
		bob = sin(_bob_phase * 2.0) * amp
		_yaw_node.rotation.z = sin(_bob_phase) * amp * 0.25
	else:
		_yaw_node.rotation.z = lerpf(_yaw_node.rotation.z, 0.0, 8.0 * delta)
	_yaw_node.global_position = _cam_follow + Vector3(0, _cam_height + _cam_dip + bob, 0)
	_yaw_node.rotation.y = _yaw
	_pitch_node.rotation.x = _pitch + _recoil
	var zoom := current_zoom()
	var fov := BASE_FOV / zoom
	if sprinting and horiz > 5.0:
		fov += 6.0
	camera.fov = lerpf(camera.fov, fov, 1.0 - exp(-10.0 * delta))
	var arm_len := 2.6
	if state != State.GROUND:
		arm_len = 7.0
	elif aiming:
		arm_len = 0.9 if zoom < 2.5 else 0.3
	elif stance == PRONE:
		arm_len = 2.2
	_arm.spring_length = lerpf(_arm.spring_length, arm_len, 1.0 - exp(-9.0 * delta))


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
	if stance == CROUCH:
		m *= 0.75
	elif stance == PRONE:
		m *= 0.55
	if not is_on_floor():
		m += 1.5
	return m


func _handle_fire() -> void:
	var held := _mouse_fire or (hud != null and bool(hud.get("fire_held")))
	var just := held and not _fire_was_held
	_fire_was_held = held
	if state != State.GROUND or not held or _healing > 0.0 or stance_locked():
		return
	if sprinting:
		# Sprinting lowers the weapon: firing stops the sprint first.
		sprinting = false
		if hud:
			hud.set("sprint_lock", false)
	if global_position.y < -1.0:
		return
	try_fire(aim_point(), spread_multiplier(), just)


func _on_fired(w: Dictionary) -> void:
	var kick := deg_to_rad(float(w["recoil"])) * randf_range(0.8, 1.2)
	if aiming:
		kick *= 0.7
	if stance == CROUCH:
		kick *= 0.8
	elif stance == PRONE:
		kick *= 0.6
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
