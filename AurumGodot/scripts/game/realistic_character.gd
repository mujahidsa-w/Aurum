extends Node3D
## A realistic animated character: loads the .glb, applies an outfit, cross-fades between
## animations from simple state (speed, aiming, armed, airborne) and keeps a held weapon
## between the hands by reading the hand bones every frame.

const CharacterDB := preload("res://scripts/game/character_db.gd")

const LOOPING := ["idle", "walk", "run", "rifle_idle", "rifle_walk", "rifle_run", "rifle_aim", "pistol_idle", "pose_idle"]

var character_id := ""
var outfit_id := "original"
var head_height := 1.6
## Where a held weapon goes: origin = right hand, -Z = aiming direction. Updated every frame.
var weapon_socket: Node3D

var _model: Node3D
var _anim: AnimationPlayer
var _skeleton: Skeleton3D
var _hand_r := -1
var _hand_l := -1
var _current := ""
var _pistol := false
var _emote_until := 0.0


func setup(id: String, outfit: String = "original") -> bool:
	character_id = id
	head_height = float(CharacterDB.get_character(id)["head"])
	var path := CharacterDB.model_path(id)
	if not ResourceLoader.exists(path):
		return false
	var scene := load(path) as PackedScene
	if scene == null:
		return false
	_model = scene.instantiate() as Node3D
	if _model == null:
		return false
	_model.rotation.y = PI # glTF faces +Z, gameplay forward is -Z
	add_child(_model)
	weapon_socket = Node3D.new()
	weapon_socket.name = "WeaponSocket"
	add_child(weapon_socket)
	for n in _model.find_children("*", "AnimationPlayer", true, false):
		_anim = n as AnimationPlayer
		break
	for n in _model.find_children("*", "Skeleton3D", true, false):
		_skeleton = n as Skeleton3D
		break
	if _skeleton:
		var re_r := RegEx.create_from_string("(hand_r(_\\d+)?$)|(RightHand(_\\d+)?$)")
		var re_l := RegEx.create_from_string("(hand_l(_\\d+)?$)|(LeftHand(_\\d+)?$)")
		for b in _skeleton.get_bone_count():
			var bn := _skeleton.get_bone_name(b)
			if _hand_r < 0 and re_r.search(bn):
				_hand_r = b
			if _hand_l < 0 and re_l.search(bn):
				_hand_l = b
	_prepare_animations()
	apply_outfit(outfit)
	play("pose_idle" if has_animation("pose_idle") else "idle", 0.0)
	return true


func _prepare_animations() -> void:
	if _anim == null:
		return
	for lib_name in _anim.get_animation_library_list():
		var lib := _anim.get_animation_library(lib_name)
		for anim_name in lib.get_animation_list():
			var a := lib.get_animation(anim_name)
			if str(anim_name) in LOOPING:
				a.loop_mode = Animation.LOOP_LINEAR
			# Keep animations in place: the character body moves, not the hips.
			for t in a.get_track_count():
				if a.track_get_type(t) != Animation.TYPE_POSITION_3D:
					continue
				var path := str(a.track_get_path(t))
				if not (path.to_lower().contains("hip")):
					continue
				if a.track_get_key_count(t) == 0:
					continue
				var first: Vector3 = a.track_get_key_value(t, 0)
				for k in a.track_get_key_count(t):
					var v: Vector3 = a.track_get_key_value(t, k)
					a.track_set_key_value(t, k, Vector3(first.x, v.y, first.z))


func has_animation(anim_name: String) -> bool:
	return _anim != null and _anim.has_animation(anim_name)


func play(anim_name: String, blend: float = 0.2) -> void:
	if _anim == null or anim_name == _current or not _anim.has_animation(anim_name):
		return
	_current = anim_name
	_anim.play(anim_name, blend)


func apply_outfit(outfit: String) -> void:
	outfit_id = outfit
	if _model == null:
		return
	var tex: Texture2D = null
	if character_id != "soldier" and outfit != "original":
		var tp := CharacterDB.outfit_texture(character_id, outfit)
		if ResourceLoader.exists(tp):
			tex = load(tp)
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if base == null:
				continue
			if outfit == "original":
				mi.set_surface_override_material(s, null)
				continue
			var m := base.duplicate() as StandardMaterial3D
			if character_id == "soldier":
				var lname := base.resource_name.to_lower()
				if lname.contains("vest") or lname.contains("pants") or lname.contains("hat"):
					m.albedo_color = CharacterDB.SOLDIER_TINT.get(outfit, Color.WHITE)
			elif tex:
				m.albedo_texture = tex
			mi.set_surface_override_material(s, m)


## Chooses an animation from gameplay state.
func set_state(speed: float, armed: bool, pistol: bool, aiming: bool, airborne: bool) -> void:
	_pistol = pistol
	if Time.get_ticks_msec() < _emote_until:
		return
	var anim := "idle"
	if airborne:
		anim = "jump"
	elif armed and not pistol:
		if aiming and speed < 2.5:
			anim = "rifle_aim"
		elif speed > 5.0:
			anim = "rifle_run"
		elif speed > 0.4:
			anim = "rifle_walk"
		else:
			anim = "rifle_idle"
	elif armed and pistol:
		if speed > 5.0:
			anim = "run"
		elif speed > 0.4:
			anim = "walk"
		else:
			anim = "pistol_idle"
	else:
		if speed > 5.0:
			anim = "run"
		elif speed > 0.4:
			anim = "walk"
	play(anim, 0.18)


func play_emote() -> void:
	_current = ""
	play("jump", 0.1)
	_emote_until = Time.get_ticks_msec() + 900


func _process(_delta: float) -> void:
	_update_weapon_socket()


func _update_weapon_socket() -> void:
	if weapon_socket == null or _skeleton == null or _hand_r < 0:
		return
	var sk := _skeleton.global_transform
	var r := sk * _skeleton.get_bone_global_pose(_hand_r).origin
	var forward := -global_transform.basis.z
	if not _pistol and _hand_l >= 0:
		var l := sk * _skeleton.get_bone_global_pose(_hand_l).origin
		var d := l - r
		if d.length() > 0.12:
			forward = d.normalized()
	var up := global_transform.basis.y
	if absf(forward.dot(up)) > 0.95:
		up = global_transform.basis.z
	var x := up.cross(-forward).normalized()
	var y := (-forward).cross(x).normalized()
	weapon_socket.global_transform = Transform3D(Basis(x, y, -forward), r)
