extends Node3D
## Every bullet is simulated as a projectile: real muzzle velocity, gravity drop and air drag,
## swept with a ray each physics step so fast rounds never tunnel through thin cover.

signal hit_confirmed(shooter: Node, victim: Node, damage: float, headshot: bool, killed: bool)

const GRAVITY := 9.81
const DRAG := 0.07
const MAX_LIFE := 3.5
const MASK := 1 | 2 | 4

var _bullets: Array = []
var _tracer_pool: Array[MeshInstance3D] = []
var _impact_pool: Array[CPUParticles3D] = []
var _impact_index := 0
var _tracer_mesh: CylinderMesh
var _tracer_mat: StandardMaterial3D
var _dust_mat: StandardMaterial3D
var _blood_mat: StandardMaterial3D


func _ready() -> void:
	_tracer_mesh = CylinderMesh.new()
	_tracer_mesh.top_radius = 0.01
	_tracer_mesh.bottom_radius = 0.01
	_tracer_mesh.height = 1.0
	_tracer_mesh.radial_segments = 4
	_tracer_mesh.rings = 1
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.albedo_color = Color(1.0, 0.82, 0.45)
	_tracer_mat.emission_enabled = true
	_tracer_mat.emission = Color(1.0, 0.75, 0.35)
	_tracer_mat.emission_energy_multiplier = 4.0
	_dust_mat = StandardMaterial3D.new()
	_dust_mat.albedo_color = Color(0.62, 0.57, 0.48)
	_dust_mat.roughness = 1.0
	_blood_mat = StandardMaterial3D.new()
	_blood_mat.albedo_color = Color(0.45, 0.02, 0.02)
	for i in 20:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 1.0
		p.amount = 10
		p.lifetime = 0.6
		var m := SphereMesh.new()
		m.radius = 0.025
		m.height = 0.05
		m.radial_segments = 6
		m.rings = 3
		p.mesh = m
		p.direction = Vector3.UP
		p.spread = 45.0
		p.initial_velocity_min = 1.5
		p.initial_velocity_max = 4.0
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.6
		add_child(p)
		_impact_pool.append(p)


## Launches one projectile.
func fire(origin: Vector3, dir: Vector3, speed: float, damage: float, shooter: Node, tracer: bool) -> void:
	var b := {
		"pos": origin,
		"vel": dir.normalized() * speed,
		"shooter": shooter,
		"rid": (shooter as CollisionObject3D).get_rid() if shooter is CollisionObject3D else RID(),
		"damage": damage,
		"life": 0.0,
		"tracer": _get_tracer() if tracer else null,
	}
	_bullets.append(b)


func _physics_process(delta: float) -> void:
	if _bullets.is_empty():
		return
	var space := get_world_3d().direct_space_state
	var i := _bullets.size() - 1
	while i >= 0:
		var b: Dictionary = _bullets[i]
		var pos: Vector3 = b["pos"]
		var vel: Vector3 = b["vel"]
		vel.y -= GRAVITY * delta
		vel *= 1.0 - DRAG * delta
		var next := pos + vel * delta
		var exclude: Array[RID] = []
		var rid: RID = b["rid"]
		if rid.is_valid():
			exclude.append(rid)
		var q := PhysicsRayQueryParameters3D.create(pos, next, MASK, exclude)
		var hit := space.intersect_ray(q)
		var life: float = float(b["life"]) + delta
		if not hit.is_empty():
			_on_hit(b, hit)
			_remove(i)
		elif life > MAX_LIFE or next.y < -60.0:
			_remove(i)
		else:
			b["pos"] = next
			b["vel"] = vel
			b["life"] = life
			var tr: MeshInstance3D = b["tracer"]
			if tr:
				var tail := next - vel.normalized() * minf(6.0, vel.length() * delta * 1.2)
				_place_tracer(tr, tail, next)
		i -= 1


func _on_hit(b: Dictionary, hit: Dictionary) -> void:
	var collider: Object = hit["collider"]
	var point: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var shooter: Node = b["shooter"]
	if float(b["damage"]) <= 0.0:
		# Visual replay of another machine's shot: effects only, the server decides damage.
		_spawn_impact(point, normal, collider != null and collider.has_method("take_hit"))
	elif collider and collider.has_method("take_hit"):
		var result: Dictionary = collider.call("take_hit", float(b["damage"]), shooter, point)
		_spawn_impact(point, normal, true)
		if float(result.get("damage", 0.0)) > 0.0:
			hit_confirmed.emit(shooter, collider as Node, float(result["damage"]), bool(result["headshot"]), bool(result["killed"]))
	else:
		_spawn_impact(point, normal, false)


func _remove(index: int) -> void:
	var b: Dictionary = _bullets[index]
	var tr: MeshInstance3D = b["tracer"]
	if tr:
		tr.visible = false
		_tracer_pool.append(tr)
	_bullets.remove_at(index)


func _get_tracer() -> MeshInstance3D:
	var tr: MeshInstance3D
	if _tracer_pool.is_empty():
		tr = MeshInstance3D.new()
		tr.mesh = _tracer_mesh
		tr.material_override = _tracer_mat
		tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tr)
	else:
		tr = _tracer_pool.pop_back()
	tr.visible = false
	return tr


func _place_tracer(tr: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.01:
		return
	var y := d / length
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	tr.transform = Transform3D(Basis(x, y * length, z), (a + b) * 0.5)
	tr.visible = true


func _spawn_impact(point: Vector3, normal: Vector3, flesh: bool) -> void:
	var p := _impact_pool[_impact_index]
	_impact_index = (_impact_index + 1) % _impact_pool.size()
	p.global_position = point + normal * 0.02
	p.direction = normal
	p.material_override = _blood_mat if flesh else _dust_mat
	p.restart()
	p.emitting = true
