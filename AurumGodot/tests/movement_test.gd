extends Node
## Automated check of the movement system on the training course (run headless on CI with
## --fixed-fps 60). Drives the real player with input actions and verifies that the
## obstacles behave: hurdles need a jump, the tunnel needs a crouch, the wire needs prone.

const TrainingScene := preload("res://scenes/training.tscn")

var training: Node
var player: Node
var _failures := 0


func _ready() -> void:
	training = TrainingScene.instantiate()
	add_child(training)
	await _frames(30)
	player = training.get("player")
	await _run()
	print("MOVEMENT TEST: %s (%d failures)" % ["ALL PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _run() -> void:
	# Sprint reaches sprint speed after a short build-up (inertia).
	await _place(Vector3(0, 0.1, -2))
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _frames(6)
	var early := _speed()
	await _seconds(1.5)
	_check("sprint builds up (not instant)", early < 4.0, "speed after 0.1 s = %.2f" % early)
	_check("sprint reaches ~6.3 m/s", _speed() > 5.8 and bool(player.get("sprinting")), "speed %.2f" % _speed())
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _seconds(0.6)
	_check("stops with momentum then halts", _speed() < 0.3, "speed %.2f" % _speed())

	# Hurdles block walking but can be jumped.
	await _place(Vector3(0, 0.1, -55))
	Input.action_press("move_forward")
	await _seconds(2.5)
	_check("hurdle blocks walking", _z() > -58.0, "z = %.2f" % _z())
	for i in 12:
		if bool(player.call("is_on_floor")):
			player.call("jump_or_open_chute")
		await _seconds(0.5)
		if _z() < -71.0:
			break
	_check("hurdles can be jumped", _z() < -71.0, "z = %.2f" % _z())
	Input.action_release("move_forward")

	# Tunnel: standing is blocked, crouching passes.
	await _place(Vector3(0, 0.1, -79))
	Input.action_press("move_forward")
	await _seconds(2.5)
	_check("tunnel blocks a standing player", _z() > -82.6, "z = %.2f" % _z())
	Input.action_release("move_forward")
	player.call("toggle_crouch")
	await _seconds(0.6)
	_check("crouch stance", int(player.get("stance")) == 1, "stance %d" % int(player.get("stance")))
	Input.action_press("move_forward")
	await _seconds(3.0)
	Input.action_release("move_forward")
	player.call("toggle_crouch")
	await _seconds(0.5)
	_check("cannot stand up under the roof", int(player.get("stance")) == 1, "stance %d" % int(player.get("stance")))
	Input.action_press("move_forward")
	await _seconds(5.0)
	_check("crouching passes the tunnel", _z() < -95.0, "z = %.2f" % _z())
	Input.action_release("move_forward")

	# Wire: crouched is blocked, prone passes.
	await _place(Vector3(0, 0.1, -101))
	player.call("toggle_crouch")
	await _seconds(0.6)
	Input.action_press("move_forward")
	await _seconds(2.5)
	_check("wire blocks a crouched player", _z() > -104.3, "z = %.2f stance %d" % [_z(), int(player.get("stance"))])
	Input.action_release("move_forward")
	player.call("toggle_prone")
	await _seconds(1.2)
	_check("prone stance", int(player.get("stance")) == 2, "stance %d" % int(player.get("stance")))
	Input.action_press("move_forward")
	await _seconds(16.0)
	_check("prone crawls under the wire", _z() < -117.0, "z = %.2f" % _z())
	Input.action_release("move_forward")
	# Getting up: prone -> crouch -> stand with the jump key.
	await _seconds(1.0)
	player.call("jump_or_open_chute")
	await _seconds(1.0)
	player.call("jump_or_open_chute")
	await _seconds(0.8)
	_check("jump key gets up (prone -> crouch -> stand)", int(player.get("stance")) == 0, "stance %d" % int(player.get("stance")))


func _place(p: Vector3) -> void:
	for a in ["move_forward", "sprint"]:
		Input.action_release(a)
	if int(player.get("stance")) != 0:
		player.set("stance", 0)
		player.call("_apply_capsule")
	player.set("global_position", p)
	player.set("velocity", Vector3.ZERO)
	await _frames(2)


func _speed() -> float:
	var v: Vector3 = player.get("velocity")
	return Vector2(v.x, v.z).length()


func _z() -> float:
	return (player as Node3D).global_position.z


func _check(label: String, ok: bool, detail: String) -> void:
	print("MOVEMENT TEST: %-45s %s   (%s)" % [label, "PASS" if ok else "FAIL", detail])
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await _frames(int(s * 60.0))
