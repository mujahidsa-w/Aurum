extends Node3D
## The shrinking safe zone: each phase waits, then shrinks toward a new random circle
## inside the current one. Standing outside costs health every second.

signal phase_changed(index: int)

## [wait seconds, shrink seconds, radius as a fraction of the start radius, damage per second]
const PHASES := [
	[100.0, 70.0, 0.5, 1.0],
	[80.0, 55.0, 0.27, 2.0],
	[60.0, 45.0, 0.14, 4.0],
	[45.0, 35.0, 0.065, 7.0],
	[35.0, 30.0, 0.025, 10.0],
	[25.0, 25.0, 0.0, 15.0],
]

var center := Vector2.ZERO
var radius := 6000.0
var next_center := Vector2.ZERO
var next_radius := 6000.0
var damage := 0.6
var phase := -1
var shrinking := false
var timer := 0.0

var _start_radius := 6000.0
var _from_center := Vector2.ZERO
var _from_radius := 6000.0
var _shrink_time := 1.0
var _world: Node
var _wall: MeshInstance3D

const WALL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.15, 0.45, 1.0, 0.5);
void fragment() {
	float stripes = 0.5 + 0.5 * sin(UV.y * 900.0 - TIME * 3.0);
	float fade = smoothstep(0.0, 0.08, UV.y) * (1.0 - smoothstep(0.6, 1.0, UV.y));
	ALBEDO = tint.rgb * (0.6 + 0.4 * stripes);
	ALPHA = tint.a * fade;
}
"""


func setup(world: Node, start_center: Vector2, start_radius: float) -> void:
	_world = world
	center = start_center
	radius = start_radius
	_start_radius = start_radius
	next_center = center
	next_radius = radius
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 900.0
	mesh.radial_segments = 96
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	var sh := Shader.new()
	sh.code = WALL_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_wall = MeshInstance3D.new()
	_wall.mesh = mesh
	_wall.material_override = mat
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wall)
	_start_phase(0)


func _start_phase(index: int) -> void:
	phase = index
	if phase >= PHASES.size():
		return
	var p: Array = PHASES[phase]
	shrinking = false
	timer = float(p[0])
	damage = float(p[3])
	next_radius = _start_radius * float(p[2])
	# The next circle lies fully inside the current one, preferring land.
	var best := center
	for attempt in 30:
		var a := randf() * TAU
		var d := (radius - next_radius) * sqrt(randf())
		var c := center + Vector2(cos(a), sin(a)) * d
		best = c
		if _world and _world.call("is_land", c.x, c.y, 2.0):
			break
	next_center = best
	phase_changed.emit(phase)


func _process(delta: float) -> void:
	if phase < 0 or phase >= PHASES.size():
		_update_wall()
		return
	timer -= delta
	if not shrinking and timer <= 0.0:
		shrinking = true
		_from_center = center
		_from_radius = radius
		_shrink_time = float(PHASES[phase][1])
		timer = _shrink_time
	elif shrinking:
		var t := 1.0 - clampf(timer / _shrink_time, 0.0, 1.0)
		center = _from_center.lerp(next_center, t)
		radius = lerpf(_from_radius, next_radius, t)
		if timer <= 0.0:
			center = next_center
			radius = next_radius
			_start_phase(phase + 1)
	_update_wall()


func _update_wall() -> void:
	if _wall:
		_wall.scale = Vector3(maxf(radius, 0.5), 1.0, maxf(radius, 0.5))
		_wall.position = Vector3(center.x, 250.0, center.y)


func is_inside(p: Vector3) -> bool:
	return Vector2(p.x, p.z).distance_to(center) <= radius


func status_text() -> String:
	if phase >= PHASES.size():
		return "Final zone"
	var secs := maxi(int(ceil(timer)), 0)
	var mmss := "%d:%02d" % [secs / 60, secs % 60]
	return ("Zone shrinking  " if shrinking else "Zone shrinks in  ") + mmss
