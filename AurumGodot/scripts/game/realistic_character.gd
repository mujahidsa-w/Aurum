extends Node3D
## A realistic animated character: loads the .glb, applies an outfit, cross-fades between
## animations from simple state (speed, aiming, armed, airborne) and keeps a held weapon
## between the hands by reading the hand bones every frame.

const CharacterDB := preload("res://scripts/game/character_db.gd")

const LOOPING := ["idle", "walk", "run", "sprint", "rifle_idle", "rifle_walk", "rifle_run", "rifle_aim",
	"pistol_idle", "pose_idle", "crouch_idle", "crouch_walk", "crouch_aim", "prone_idle", "prone_crawl",
	"prone_aim", "fire_walk", "fire_stand"]

const STAND := 0
const CROUCH := 1
const PRONE := 2

## Gameplay speed (m/s) at which each locomotion clip plays at its natural rate. The clip is
## sped up or slowed down with the real speed so feet do not slide.
const CLIP_SPEED := {
	"walk": 1.7, "run": 4.7, "sprint": 6.3, "rifle_walk": 1.8, "rifle_run": 4.7, "fire_walk": 1.8,
	"crouch_walk": 2.2, "prone_crawl": 1.15,
}

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
var _action := ""
var _action_until := 0.0
var _action_total := 1.0
var _dead := false


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


func animation_length(anim_name: String) -> float:
	if not has_animation(anim_name):
		return 0.0
	return _anim.get_animation(anim_name).length


func play(anim_name: String, blend: float = 0.2, speed: float = 1.0) -> void:
	if _anim == null or not _anim.has_animation(anim_name):
		return
	if anim_name == _current:
		_anim.speed_scale = speed
		return
	_current = anim_name
	_anim.speed_scale = speed
	_anim.play(anim_name, blend)


## Plays a one-shot clip (reload, stance change, landing...) stretched to `duration`
## seconds; locomotion resumes when it ends.
func play_action(anim_name: String, duration: float = -1.0, blend: float = 0.15, backwards: bool = false) -> void:
	if _anim == null or _dead or not _anim.has_animation(anim_name):
		return
	var length := _anim.get_animation(anim_name).length
	if duration <= 0.0:
		duration = length
	_action = anim_name
	_action_total = duration
	_action_until = Time.get_ticks_msec() + duration * 1000.0
	_current = ""
	_anim.speed_scale = clampf(length / maxf(duration, 0.05), 0.25, 4.0)
	if backwards:
		_anim.play_backwards(anim_name, blend)
	else:
		_anim.play(anim_name, blend)


func cancel_action() -> void:
	_action_until = 0.0
	_action = ""


func is_in_action() -> bool:
	return Time.get_ticks_msec() < _action_until


## Death clip chosen by stance and hit; the final pose is held.
func play_death(stance: int, headshot: bool) -> bool:
	var clip := "death"
	if headshot and has_animation("death_head") and stance == STAND:
		clip = "death_head"
	elif stance == CROUCH and has_animation("death_crouch"):
		clip = "death_crouch"
	elif stance == PRONE and has_animation("death_prone"):
		clip = "death_prone"
	if not has_animation(clip):
		return false
	_dead = true
	_current = clip
	_anim.speed_scale = 1.0
	_anim.play(clip, 0.12)
	return true


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


## Chooses a locomotion animation from gameplay state.
func set_state(speed: float, armed: bool, pistol: bool, aiming: bool, airborne: bool, stance: int = STAND, sprinting: bool = false) -> void:
	_pistol = pistol
	var moving := speed > 0.35
	if is_in_action() and stance == STAND and _action.begins_with("reload_"):
		_match_reload_to_movement(moving)
	if _dead or Time.get_ticks_msec() < _emote_until or is_in_action():
		return
	var rifle := armed and not pistol
	var anim := "idle"
	if airborne and stance == STAND:
		anim = "jump"
	elif stance == PRONE:
		if moving:
			anim = "prone_crawl"
		elif aiming:
			anim = "prone_aim"
		else:
			anim = "prone_idle"
	elif stance == CROUCH:
		if moving:
			anim = "crouch_walk"
		elif aiming:
			anim = "crouch_aim"
		else:
			anim = "crouch_idle"
	elif rifle:
		if sprinting and speed > 5.2:
			anim = "sprint"
		elif aiming:
			anim = "fire_walk" if moving else "rifle_aim"
		elif speed > 3.2:
			anim = "rifle_run"
		elif moving:
			anim = "rifle_walk"
		else:
			anim = "rifle_idle"
	else:
		if sprinting and speed > 5.2:
			anim = "run"
		elif speed > 3.2:
			anim = "run"
		elif moving:
			anim = "walk"
		elif pistol:
			anim = "pistol_idle"
	if not has_animation(anim):
		anim = "idle"
	var rate := 1.0
	if CLIP_SPEED.has(anim):
		rate = clampf(speed / float(CLIP_SPEED[anim]), 0.55, 1.45)
	var blend := 0.28
	if anim == "jump":
		blend = 0.12
	elif _current.begins_with("prone") != anim.begins_with("prone"):
		blend = 0.4
	play(anim, blend, rate)


## Keeps a standing reload in sync with the legs: switches between the standing and the
## walking reload clip at the same point of the reload when the player starts/stops moving.
func _match_reload_to_movement(moving: bool) -> void:
	var want := "reload_walk" if moving else "reload_stand"
	if want == _action or not has_animation(want):
		return
	var remaining := (_action_until - Time.get_ticks_msec()) / 1000.0
	var frac := clampf(1.0 - remaining / maxf(_action_total, 0.05), 0.0, 1.0)
	var length := _anim.get_animation(want).length
	_action = want
	_anim.speed_scale = clampf(length / maxf(_action_total, 0.05), 0.25, 4.0)
	_anim.play(want, 0.25)
	_anim.seek(frac * length, false)


func play_emote() -> void:
	_current = ""
	play("jump_full" if has_animation("jump_full") else "jump", 0.1)
	_emote_until = Time.get_ticks_msec() + 1100


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
