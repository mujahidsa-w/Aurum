extends "res://scripts/game/combatant.gd"
## AI soldier: roams inside the safe zone, picks the nearest visible enemy (player or bot),
## reacts with a human-like delay, keeps a distance that suits its weapon, strafes and fires
## with distance-dependent inaccuracy. Uses the same ballistics as the player.

const RUN_SPEED := 4.4
const SIGHT := 140.0

var battle: Node
var skill := 0.5

var _think := 0.0
var _target: Node3D
var _reaction := 0.0
var _dest := Vector3.ZERO
var _strafe := 1.0
var _strafe_t := 0.0
var _semi_wait := 0.0
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO


func _ready() -> void:
	show_tracers = false
	infinite_reserve = true
	floor_snap_length = 0.5
	_dest = global_position
	_last_pos = global_position


func _physics_process(delta: float) -> void:
	process_weapon(delta)
	if not alive:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	_think -= delta
	if _think <= 0.0:
		_think = randf_range(0.25, 0.5)
		_decide()
	var move := Vector3.ZERO
	var face_dir := Vector3.ZERO
	if _target and is_instance_valid(_target) and bool(_target.get("alive")):
		var to_t := _target.global_position - global_position
		to_t.y = 0.0
		var dist := to_t.length()
		var dir := to_t / maxf(dist, 0.001)
		face_dir = dir
		var pref := _preferred_range()
		_strafe_t -= delta
		if _strafe_t <= 0.0:
			_strafe_t = randf_range(0.8, 2.2)
			_strafe = -_strafe if randf() < 0.6 else _strafe
		var side := Vector3(-dir.z, 0, dir.x) * _strafe
		if dist > pref * 1.25:
			move = (dir * 0.8 + side * 0.4).normalized()
		elif dist < pref * 0.6:
			move = (-dir * 0.7 + side * 0.5).normalized()
		else:
			move = side
		_reaction -= delta
		if _reaction <= 0.0:
			_shoot_at(_target, dist, delta)
	else:
		var to_d := _dest - global_position
		to_d.y = 0.0
		if to_d.length() < 3.0:
			_pick_destination()
		else:
			move = to_d.normalized()
			face_dir = move
	# Never walk into the sea.
	if move != Vector3.ZERO and battle:
		var ahead := global_position + move * 3.0
		var world: Variant = battle.get("world")
		if world != null and float(world.call("height_at", ahead.x, ahead.z)) < 1.0:
			move = -move
			_pick_destination()
	var speed := RUN_SPEED * (0.75 if _target else 1.0)
	velocity.x = move_toward(velocity.x, move.x * speed, 20.0 * delta)
	velocity.z = move_toward(velocity.z, move.z * speed, 20.0 * delta)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if face_dir != Vector3.ZERO:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-face_dir.x, -face_dir.z), 8.0 * delta)
	update_animation(_target != null)
	# Unstick: if barely moving while trying to, jump and choose a new destination.
	_stuck_t += delta
	if _stuck_t > 1.5:
		if move != Vector3.ZERO and global_position.distance_to(_last_pos) < 0.8:
			if is_on_floor():
				velocity.y = 4.0
			_pick_destination()
		_last_pos = global_position
		_stuck_t = 0.0


func _preferred_range() -> float:
	if not has_weapon():
		return 10.0
	match str(weapon()["class"]):
		"pistol", "shotgun":
			return 9.0
		"smg":
			return 16.0
		"dmr", "sniper":
			return 70.0
	return 35.0


func _decide() -> void:
	if battle == null:
		return
	var zone: Variant = battle.get("zone")
	if zone != null and not zone.call("is_inside", global_position) and (_target == null or randf() < 0.5):
		_target = null
		var c: Vector2 = zone.get("next_center")
		_dest = Vector3(c.x, global_position.y, c.y)
		return
	var best: Node3D = null
	var best_d := SIGHT * (1.8 if has_weapon() and str(weapon()["class"]) in ["dmr", "sniper"] else 1.0)
	var everyone: Array = battle.call("combatants")
	for c in everyone:
		var other := c as Node3D
		if other == null or other == self or not bool(other.get("alive")):
			continue
		var d := other.global_position.distance_to(global_position)
		if d < best_d and _can_see(other):
			best_d = d
			best = other
	if best != _target:
		_reaction = randf_range(0.45, 1.1) * (1.4 - skill)
	_target = best


func _can_see(other: Node3D) -> bool:
	var from := global_position + Vector3(0, 1.55, 0)
	var to := other.global_position + Vector3(0, 1.3, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _shoot_at(target: Node3D, dist: float, delta: float) -> void:
	if not has_weapon():
		return
	if rounds_in_mag() == 0:
		start_reload()
		return
	var w := weapon()
	var modes: Array = w["modes"]
	var auto := str(modes[fire_mode % modes.size()]) == "auto"
	_semi_wait -= delta
	if not auto and _semi_wait > 0.0:
		return
	# Aim error grows with distance and shrinks with skill.
	var err_deg := lerpf(2.6, 0.7, skill) + dist * 0.01
	var aim := target.global_position + Vector3(0, randf_range(1.0, 1.65), 0)
	var muzzle_pos := muzzle.global_position if muzzle else global_position + Vector3(0, 1.4, 0)
	var dir := spread_dir((aim - muzzle_pos).normalized(), err_deg * 2.0)
	if try_fire(muzzle_pos + dir * dist, 1.0, true):
		_semi_wait = randf_range(0.25, 0.6)


func _pick_destination() -> void:
	if battle == null:
		return
	var world: Variant = battle.get("world")
	var zone: Variant = battle.get("zone")
	if world == null:
		return
	var center := Vector2(global_position.x, global_position.z)
	var radius := 300.0
	if zone != null:
		var zc: Vector2 = zone.get("next_center")
		var zr: float = zone.get("next_radius")
		if Vector2(global_position.x, global_position.z).distance_to(zc) > zr:
			center = zc
			radius = maxf(zr * 0.6, 20.0)
	_dest = world.call("random_land_point", center, radius, 0.4)


func _on_damaged(_amount: float, attacker: Node) -> void:
	# Turn toward whoever shoots us.
	if attacker is Node3D and attacker != self and bool(attacker.get("alive")):
		if _target != attacker:
			_reaction = randf_range(0.3, 0.7)
		_target = attacker as Node3D
