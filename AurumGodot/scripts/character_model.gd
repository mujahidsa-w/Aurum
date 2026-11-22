extends Node3D
## The lobby hero: a stylised soldier in a hooded jacket, face mask, cargo pants and
## high-top sneakers, holding an assault rifle at low ready.
## Built entirely from primitives so it needs no imported assets.
## Origin = between the feet, facing +Z (towards the lobby camera).

const MK := preload("res://scripts/mesh_kit.gd")

const OUTFITS := [
	{"name": "Crimson", "color": Color(0.62, 0.05, 0.07)},
	{"name": "Gold", "color": Color(0.92, 0.66, 0.1)},
	{"name": "Cobalt", "color": Color(0.1, 0.34, 0.86)},
	{"name": "Jade", "color": Color(0.08, 0.6, 0.4)},
	{"name": "Violet", "color": Color(0.46, 0.18, 0.82)},
]

const RIFLE_SKINS := [
	{"name": "Glacier", "a": Color(0.36, 0.45, 0.56), "b": Color(0.8, 0.86, 0.93), "c": Color(0.2, 0.26, 0.34)},
	{"name": "Gilded", "a": Color(0.6, 0.42, 0.08), "b": Color(1.0, 0.8, 0.32), "c": Color(0.36, 0.24, 0.05)},
	{"name": "Carbon", "a": Color(0.07, 0.07, 0.08), "b": Color(0.26, 0.26, 0.28), "c": Color(0.15, 0.15, 0.16)},
	{"name": "Jungle", "a": Color(0.2, 0.29, 0.15), "b": Color(0.5, 0.5, 0.3), "c": Color(0.12, 0.16, 0.09)},
]

# Joint layout (metres).
const SHOULDER_R := Vector3(-0.205, 1.43, -0.01)
const SHOULDER_L := Vector3(0.205, 1.43, -0.01)
const HAND_R := Vector3(-0.085, 1.06, 0.215)
const UPPER_ARM := 0.27
const FOREARM := 0.27

## When false the procedural rifle is not built (the game attaches real weapon models instead).
var show_rifle := true
## Transform (in character space) of a weapon held in both hands; +X = muzzle direction.
var weapon_transform := Transform3D.IDENTITY

var accent_mat: StandardMaterial3D
var camo_mat: StandardMaterial3D
var camo_tex: NoiseTexture2D

var _upper: Node3D
var _head: Node3D
var _t := 0.0
var _emote_tween: Tween

var _jacket: StandardMaterial3D
var _shirt: StandardMaterial3D
var _pants: StandardMaterial3D
var _skin: StandardMaterial3D
var _hair: StandardMaterial3D
var _mask: StandardMaterial3D
var _shoe: StandardMaterial3D
var _sole: StandardMaterial3D
var _strap: StandardMaterial3D
var _metal: StandardMaterial3D
var _eye: StandardMaterial3D


func _ready() -> void:
	_make_materials()
	_build_legs()
	_upper = Node3D.new()
	_upper.name = "Upper"
	add_child(_upper)
	_build_torso()
	_build_head()
	_build_arms_and_rifle()


func _make_materials() -> void:
	_jacket = MK.mat(Color(0.05, 0.05, 0.06), 0.5)
	_jacket.rim_enabled = true
	_jacket.rim = 0.35
	_jacket.rim_tint = 0.4
	_shirt = MK.mat(Color(0.86, 0.86, 0.84), 0.9)
	_pants = MK.mat(Color(0.065, 0.065, 0.075), 0.75)
	_pants.rim_enabled = true
	_pants.rim = 0.25
	_skin = MK.mat(Color(0.78, 0.56, 0.44), 0.55)
	_skin.subsurf_scatter_enabled = true
	_skin.subsurf_scatter_strength = 0.25
	_hair = MK.mat(Color(0.05, 0.04, 0.035), 0.6)
	_mask = MK.mat(Color(0.025, 0.025, 0.03), 0.95)
	_shoe = MK.mat(Color(0.93, 0.93, 0.92), 0.6)
	_sole = MK.mat(Color(0.84, 0.82, 0.78), 0.85)
	_strap = MK.mat(Color(0.32, 0.21, 0.12), 0.7)
	_metal = MK.mat(Color(0.1, 0.1, 0.11), 0.38, 0.75)
	_eye = MK.mat(Color(0.08, 0.05, 0.04), 0.2)
	accent_mat = MK.mat(Color(0.62, 0.05, 0.07), 0.45)
	camo_tex = MK.noise_texture([Color(0.36, 0.45, 0.56), Color(0.8, 0.86, 0.93), Color(0.2, 0.26, 0.34)], [0.0, 0.45, 0.72], 0.035, 256, 7, true)
	camo_mat = StandardMaterial3D.new()
	camo_mat.albedo_texture = camo_tex
	camo_mat.uv1_triplanar = true
	camo_mat.uv1_scale = Vector3(5.0, 5.0, 5.0)
	camo_mat.metallic = 0.35
	camo_mat.roughness = 0.4


# --- Outfit customisation -------------------------------------------------

func set_outfit(index: int) -> void:
	var o: Dictionary = OUTFITS[clampi(index, 0, OUTFITS.size() - 1)]
	accent_mat.albedo_color = o["color"]


func set_rifle_skin(index: int) -> void:
	var s: Dictionary = RIFLE_SKINS[clampi(index, 0, RIFLE_SKINS.size() - 1)]
	camo_tex.color_ramp = MK.gradient([s["a"], s["b"], s["c"]], [0.0, 0.45, 0.72], true)


# --- Animation --------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	# Idle: breathing bob, a slight weight shift and a slow look-around.
	_upper.position.y = sin(_t * 1.7) * 0.004
	_upper.rotation.z = sin(_t * 0.6) * 0.012
	_upper.rotation.x = sin(_t * 1.7 + 0.6) * 0.006
	_head.rotation.y = sin(_t * 0.45) * 0.12
	_head.rotation.x = sin(_t * 0.33) * 0.03


## Short celebration: hop and spin on the spot.
func play_emote() -> void:
	if _emote_tween and _emote_tween.is_running():
		return
	_emote_tween = create_tween()
	_emote_tween.set_parallel(true)
	_emote_tween.tween_property(self, "rotation:y", rotation.y + TAU, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_emote_tween.tween_property(self, "position:y", 0.16, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_emote_tween.tween_property(self, "position:y", 0.0, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT).set_delay(0.3)
	_emote_tween.chain().tween_callback(_reset_spin)


func _reset_spin() -> void:
	rotation.y = wrapf(rotation.y, -PI, PI)


# --- Body parts ---------------------------------------------------------------

func _build_legs() -> void:
	for side in [-1.0, 1.0]:
		var s: float = side
		var hip := Vector3(0.11 * s, 0.93, 0.0)
		var knee := Vector3(0.125 * s, 0.5, 0.035)
		var ankle := Vector3(0.135 * s, 0.13, 0.0)
		MK.capsule(self, hip, knee, 0.088, _pants)
		MK.capsule(self, knee, ankle, 0.072, _pants)
		# Side piping in the accent colour.
		MK.tube(self, hip + Vector3(0.085 * s, -0.02, 0.0), knee + Vector3(0.07 * s, 0.0, 0.0), 0.011, accent_mat, 6)
		MK.tube(self, knee + Vector3(0.07 * s, 0.0, 0.0), ankle + Vector3(0.06 * s, 0.05, 0.0), 0.01, accent_mat, 6)
		# Cargo pocket.
		MK.box(self, Vector3(0.05, 0.15, 0.12), Vector3(0.19 * s, 0.68, 0.01), _pants, Vector3(0, 0, -4.0 * s))
		# High-top sneaker.
		MK.box(self, Vector3(0.12, 0.04, 0.27), Vector3(0.135 * s, 0.02, 0.045), _sole)
		MK.box(self, Vector3(0.112, 0.085, 0.22), Vector3(0.135 * s, 0.08, 0.03), _shoe)
		MK.sphere(self, 0.058, Vector3(0.135 * s, 0.065, 0.14), _shoe, Vector3(0.98, 0.72, 1.0))
		MK.box(self, Vector3(0.116, 0.06, 0.1), Vector3(0.135 * s, 0.1, -0.04), accent_mat)
		MK.cylinder(self, 0.066, 0.07, 0.11, Vector3(0.135 * s, 0.16, -0.005), _shoe)
		MK.box(self, Vector3(0.05, 0.012, 0.12), Vector3(0.135 * s, 0.128, 0.07), accent_mat, Vector3(-18, 0, 0))
	# Leg holster straps on the right thigh.
	MK.cylinder(self, 0.094, 0.094, 0.028, Vector3(-0.115, 0.62, 0.02), _strap)
	MK.cylinder(self, 0.09, 0.09, 0.028, Vector3(-0.118, 0.74, 0.015), _strap)
	# Hips and belt.
	MK.box(self, Vector3(0.34, 0.16, 0.21), Vector3(0, 0.94, 0), _pants)
	MK.box(self, Vector3(0.352, 0.045, 0.222), Vector3(0, 1.0, 0), MK.mat(Color(0.04, 0.04, 0.045), 0.5))
	MK.box(self, Vector3(0.05, 0.035, 0.01), Vector3(0.0, 1.0, 0.113), MK.mat(Color(0.7, 0.7, 0.72), 0.3, 0.9))
	# Chain hanging from the belt.
	MK.torus(self, 0.03, 0.05, Vector3(-0.16, 0.9, 0.06), MK.mat(Color(0.75, 0.75, 0.78), 0.25, 1.0), Vector3(90, 0, 20), Vector3(1.4, 1.0, 1.0))


func _build_torso() -> void:
	var u := _upper
	# Jacket body: tapered elliptic cylinder.
	MK.cylinder(u, 0.215, 0.18, 0.5, Vector3(0, 1.235, -0.005), _jacket, Vector3.ZERO, Vector3(1.0, 1.0, 0.6), 24)
	# Ribbed hem.
	MK.cylinder(u, 0.188, 0.188, 0.06, Vector3(0, 1.005, -0.005), MK.mat(Color(0.035, 0.035, 0.04), 0.9), Vector3.ZERO, Vector3(1.0, 1.0, 0.62), 24)
	# White tee under the open jacket.
	MK.box(u, Vector3(0.13, 0.44, 0.02), Vector3(0, 1.245, 0.112), _shirt)
	MK.sphere(u, 0.07, Vector3(0, 1.43, 0.085), _shirt, Vector3(1.0, 0.35, 0.5))
	# Zipper edges in the accent colour.
	for side in [-1.0, 1.0]:
		var s: float = side
		var x: float = 0.072 * s
		MK.box(u, Vector3(0.022, 0.46, 0.022), Vector3(x, 1.245, 0.117), accent_mat)
		# Shoulders.
		MK.sphere(u, 0.07, Vector3(0.195 * s, 1.425, -0.01), _jacket, Vector3(1.1, 0.8, 1.0))
		# Chest pocket flap.
		MK.box(u, Vector3(0.08, 0.012, 0.02), Vector3(0.14 * s, 1.34, 0.095), MK.mat(Color(0.09, 0.09, 0.1), 0.6), Vector3(0, -30.0 * s, 0))
	# Chest emblem.
	MK.box(u, Vector3(0.04, 0.04, 0.008), Vector3(0.135, 1.38, 0.098), MK.mat(Color(0.92, 0.92, 0.92), 0.5), Vector3(0, 30, 45))
	# Hood bunched behind the neck + collar.
	MK.sphere(u, 0.13, Vector3(0, 1.5, -0.085), _jacket, Vector3(1.25, 0.72, 0.75))
	MK.torus(u, 0.06, 0.115, Vector3(0, 1.485, -0.01), _jacket, Vector3.ZERO, Vector3(1.15, 1.6, 1.0))
	MK.tube(u, Vector3(-0.05, 1.47, 0.07), Vector3(-0.065, 1.33, 0.1), 0.006, _shirt, 6)
	MK.tube(u, Vector3(0.05, 1.47, 0.07), Vector3(0.06, 1.35, 0.1), 0.006, _shirt, 6)


func _build_head() -> void:
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0, 1.53, 0)
	_upper.add_child(_head)
	var h := _head
	var o := Vector3(0, -1.53, 0) # so parts can be written in body space
	MK.cylinder(h, 0.048, 0.055, 0.12, o + Vector3(0, 1.545, 0.0), _skin)
	MK.sphere(h, 0.105, o + Vector3(0, 1.67, 0.0), _skin, Vector3(0.92, 1.08, 1.0))
	for s in [-1.0, 1.0]:
		var x: float = s
		MK.sphere(h, 0.026, o + Vector3(0.096 * x, 1.67, -0.005), _skin, Vector3(0.5, 1.0, 0.8))
		MK.sphere(h, 0.0135, o + Vector3(0.036 * x, 1.692, 0.091), _eye)
		MK.box(h, Vector3(0.036, 0.009, 0.012), o + Vector3(0.037 * x, 1.713, 0.095), _hair, Vector3(0, 0, -8.0 * x))
	# Face mask covering nose, chin and neck.
	MK.sphere(h, 0.104, o + Vector3(0, 1.6, 0.006), _mask, Vector3(0.96, 0.64, 1.04))
	MK.cylinder(h, 0.07, 0.075, 0.09, o + Vector3(0, 1.53, 0.0), _mask)
	# Hair: swept-up quiff.
	MK.sphere(h, 0.112, o + Vector3(0, 1.735, -0.024), _hair, Vector3(0.98, 0.72, 1.03))
	MK.sphere(h, 0.068, o + Vector3(0.005, 1.795, 0.02), _hair, Vector3(1.3, 0.62, 1.2), Vector3(-14, 0, 0))
	MK.sphere(h, 0.048, o + Vector3(-0.025, 1.775, 0.07), _hair, Vector3(1.45, 0.55, 0.9), Vector3(-28, 15, 0))
	# Short sideburns.
	for side in [-1.0, 1.0]:
		var sx: float = side
		MK.box(h, Vector3(0.012, 0.04, 0.03), o + Vector3(0.094 * sx, 1.69, 0.02), _hair)


func _build_arms_and_rifle() -> void:
	var u := _upper
	# --- Rifle pose: muzzle to the character's left, angled down and slightly forward.
	var rifle_basis := Basis(Vector3.UP, deg_to_rad(-16.0)) * Basis(Vector3(0, 0, 1), deg_to_rad(-15.0))
	var grip_local := Vector3(-0.03, -0.075, 0.0)
	var support_local := Vector3(0.27, -0.035, 0.0)
	var rifle_origin := HAND_R - rifle_basis * grip_local
	var hand_l := rifle_origin + rifle_basis * support_local

	weapon_transform = Transform3D(rifle_basis, rifle_origin)
	if show_rifle:
		var rifle := Node3D.new()
		rifle.name = "Rifle"
		rifle.transform = weapon_transform
		u.add_child(rifle)
		_build_rifle(rifle)

	_build_arm(SHOULDER_R, HAND_R, Vector3(-1.0, -0.35, -0.55), -1.0)
	_build_arm(SHOULDER_L, hand_l, Vector3(1.0, -0.6, -0.2), 1.0)


func _build_arm(shoulder: Vector3, hand: Vector3, pole: Vector3, side: float) -> void:
	var u := _upper
	var elbow := _solve_elbow(shoulder, hand, UPPER_ARM, FOREARM, pole)
	var dir := (hand - elbow).normalized()
	var wrist := hand - dir * 0.075
	MK.capsule(u, shoulder, elbow, 0.055, _jacket)
	MK.capsule(u, elbow, wrist, 0.046, _jacket)
	# Sleeve stripe on the outside of the arm.
	var out := Vector3(side * 0.048, 0.0, -0.012)
	MK.tube(u, shoulder + out + Vector3(0, -0.02, 0), elbow + out, 0.01, accent_mat, 6)
	MK.tube(u, elbow + out, wrist + out * 0.9, 0.009, accent_mat, 6)
	# Ribbed cuff, then the bare hand closing around the rifle.
	MK.tube(u, wrist - dir * 0.02, wrist + dir * 0.022, 0.05, accent_mat, 12)
	MK.sphere(u, 0.046, hand, _skin, Vector3(0.95, 1.1, 0.85))
	MK.sphere(u, 0.022, hand + Vector3(0, -0.01, 0.03), _skin, Vector3(1.0, 0.8, 1.6))


## Two-bone IK: returns the elbow position for an arm reaching from `s` to `h`.
static func _solve_elbow(s: Vector3, h: Vector3, l1: float, l2: float, pole: Vector3) -> Vector3:
	var d := h - s
	var dist := clampf(d.length(), 0.01, l1 + l2 - 0.002)
	var dir := d.normalized()
	var a := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var height := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var bend := (pole - dir * pole.dot(dir)).normalized()
	return s + dir * a + bend * height


func _build_rifle(r: Node3D) -> void:
	var dark := _metal
	var glass := MK.mat(Color(0.15, 0.3, 0.45), 0.05, 0.6)
	# Receiver, magazine, grip.
	MK.box(r, Vector3(0.3, 0.062, 0.052), Vector3(0.05, 0.0, 0), camo_mat)
	MK.box(r, Vector3(0.2, 0.05, 0.046), Vector3(0.02, -0.048, 0), camo_mat)
	MK.box(r, Vector3(0.058, 0.17, 0.036), Vector3(0.085, -0.14, 0), dark, Vector3(0, 0, 10))
	MK.box(r, Vector3(0.038, 0.105, 0.032), Vector3(-0.035, -0.095, 0), dark, Vector3(0, 0, -18))
	MK.box(r, Vector3(0.075, 0.008, 0.026), Vector3(0.0, -0.085, 0), dark)
	# Handguard with rail slots.
	MK.box(r, Vector3(0.28, 0.06, 0.058), Vector3(0.34, -0.004, 0), camo_mat)
	for i in 5:
		MK.box(r, Vector3(0.03, 0.012, 0.06), Vector3(0.24 + i * 0.05, -0.004, 0), dark)
	# Top rail, optic.
	MK.box(r, Vector3(0.44, 0.014, 0.03), Vector3(0.17, 0.037, 0), dark)
	MK.box(r, Vector3(0.06, 0.03, 0.03), Vector3(0.05, 0.055, 0), dark)
	MK.tube(r, Vector3(-0.02, 0.085, 0), Vector3(0.13, 0.085, 0), 0.024, dark, 16)
	MK.tube(r, Vector3(0.128, 0.085, 0), Vector3(0.134, 0.085, 0), 0.02, glass, 16)
	MK.box(r, Vector3(0.012, 0.045, 0.012), Vector3(0.45, 0.055, 0), dark)
	# Barrel and muzzle brake.
	MK.tube(r, Vector3(0.47, 0.0, 0), Vector3(0.63, 0.0, 0), 0.011, dark, 10)
	MK.tube(r, Vector3(0.62, 0.0, 0), Vector3(0.69, 0.0, 0), 0.018, dark, 10)
	# Stock.
	MK.tube(r, Vector3(-0.1, -0.005, 0), Vector3(-0.29, -0.01, 0), 0.016, dark, 10)
	MK.box(r, Vector3(0.18, 0.068, 0.042), Vector3(-0.3, -0.025, 0), camo_mat, Vector3(0, 0, -4))
	MK.box(r, Vector3(0.022, 0.095, 0.046), Vector3(-0.395, -0.035, 0), dark, Vector3(0, 0, -4))
	# Charging handle + ejection port.
	MK.box(r, Vector3(0.03, 0.012, 0.07), Vector3(-0.08, 0.025, 0), dark)
	MK.box(r, Vector3(0.07, 0.022, 0.004), Vector3(0.07, 0.006, 0.027), dark)
