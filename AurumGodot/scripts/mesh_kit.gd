extends RefCounted
## Tiny toolkit for building stylised props out of primitive meshes.
## Every helper adds a MeshInstance3D to `parent` and returns it.


static func mat(color: Color, roughness: float = 0.8, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


static func emissive(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var m := mat(color, 0.4)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func xform(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	var rot := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	return Transform3D(rot * Basis.from_scale(scl), pos)


## Orthonormal basis whose +Y axis points along `dir`.
static func basis_y_to(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


static func add(parent: Node3D, mesh: Mesh, material: Material, xf: Transform3D, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.transform = xf
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func box(parent: Node3D, size: Vector3, pos: Vector3, material: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return add(parent, m, material, xform(pos, rot_deg))


static func sphere(parent: Node3D, radius: float, pos: Vector3, material: Material, scl: Vector3 = Vector3.ONE, rot_deg: Vector3 = Vector3.ZERO, segments: int = 24) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segments
	m.rings = maxi(segments / 2, 4)
	return add(parent, m, material, xform(pos, rot_deg, scl))


static func cylinder(parent: Node3D, top_radius: float, bottom_radius: float, height: float, pos: Vector3, material: Material, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, segments: int = 18) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = top_radius
	m.bottom_radius = bottom_radius
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return add(parent, m, material, xform(pos, rot_deg, scl))


## Cylinder stretched between two points (pipes, rails, frame tubes, limbs).
static func tube(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: Material, segments: int = 10) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = maxf(a.distance_to(b), 0.001)
	m.radial_segments = segments
	m.rings = 1
	return add(parent, m, material, Transform3D(basis_y_to(b - a), (a + b) * 0.5))


## Capsule whose rounded ends sit exactly on `a` and `b` (good for limbs).
static func capsule(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: Material, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = a.distance_to(b) + radius * 2.0
	m.radial_segments = 16
	m.rings = 6
	return add(parent, m, material, Transform3D(basis_y_to(b - a) * Basis.from_scale(scl), (a + b) * 0.5))


static func torus(parent: Node3D, inner: float, outer: float, pos: Vector3, material: Material, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 24
	m.ring_segments = 10
	return add(parent, m, material, xform(pos, rot_deg, scl))


static func gradient(colors: Array, offsets: Array, constant: bool = false) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	if constant:
		g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	return g


static func noise_texture(colors: Array, offsets: Array, frequency: float, size: int = 256, seed_value: int = 1, constant: bool = false, cellular: bool = false) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR if cellular else FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = frequency
	n.fractal_octaves = 4
	n.seed = seed_value
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	t.color_ramp = gradient(colors, offsets, constant)
	return t
