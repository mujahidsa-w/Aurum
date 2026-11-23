extends "res://scripts/game/combatant.gd"
## A combatant controlled over the network: another player (or, on clients, a server bot).
## Position and facing are interpolated from snapshots, posture/weapon/animation follow the
## sent state, shots are replayed visually. On the dedicated server it also receives the
## real damage (server-authoritative); on clients a hit is reported to the server instead.

var net_id := 0
var aiming_remote := false
var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _remote_vel := Vector3.ZERO
var _airborne := false
var _has_state := false


func _ready() -> void:
	show_tracers = true
	infinite_reserve = true
	_target_pos = global_position


func apply_state(state: Array) -> void:
	# [id, pos, yaw, vel, stance, flags, weapon, health]
	if state.size() < 8:
		return
	_target_pos = state[1]
	_target_yaw = float(state[2])
	_remote_vel = state[3]
	var flags := int(state[5])
	aiming_remote = (flags & 1) != 0
	_airborne = (flags & 2) != 0
	sprinting = (flags & 8) != 0
	var st := int(state[4])
	if st != stance and alive:
		stance = st
		_apply_capsule()
	var wid := str(state[6])
	if wid != "" and wid != current_id():
		weapons.clear()
		give_weapon(wid)
	if not _has_state:
		global_position = _target_pos
		_has_state = true
	if Net.is_client_match():
		health = float(state[7])


func _physics_process(delta: float) -> void:
	process_weapon(delta)
	if not alive or not _has_state:
		return
	var d := global_position.distance_to(_target_pos)
	if d > 12.0:
		global_position = _target_pos
	else:
		global_position = global_position.lerp(_target_pos + _remote_vel * 0.05, 1.0 - exp(-14.0 * delta))
	velocity = _remote_vel
	visual.rotation.y = lerp_angle(visual.rotation.y, _target_yaw, 1.0 - exp(-12.0 * delta))
	if character:
		var horiz := Vector2(_remote_vel.x, _remote_vel.z).length()
		var pistol := has_weapon() and str(weapon()["class"]) == "pistol"
		character.set_state(horiz, has_weapon(), pistol, aiming_remote, _airborne, stance, sprinting)
	process_footsteps(delta)


## Replays a shot fired by this player on another machine (tracer, flash and sound only).
func remote_fire(origin: Vector3, dir: Vector3) -> void:
	if not has_weapon() or ballistics == null:
		return
	var w := weapon()
	_flash_t = 0.05
	_play_shot(w)
	ballistics.call("fire", origin, dir, float(w["velocity"]), 0.0, self, true)


func take_hit(damage: float, attacker: Node, point: Vector3) -> Dictionary:
	if Net.is_client_match():
		if not alive or damage <= 0.0:
			return {"damage": 0.0, "headshot": false, "killed": false}
		# Report to the server; show the hit marker right away (predicted).
		var local_y := point.y - global_position.y
		Net.send_hit(net_id, damage, local_y)
		var head := local_y > float(STANCE_HEAD[stance])
		return {"damage": damage, "headshot": head, "killed": false}
	return super.take_hit(damage, attacker, point)


## Applies a damage event decided by the server.
func net_set_health(value: float, killer: Node, killed: bool) -> void:
	health = value
	health_changed.emit(health)
	if killed and alive:
		die(killer)
