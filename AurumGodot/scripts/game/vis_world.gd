extends Node3D
## Vis Island (Croatia) built from real elevation data: terrain, sea, sky, towns at the real
## town locations, former military sites, the Plisko Polje airfield and Mediterranean nature.
## Everything is generated at load time from res://maps/vis + the CC0 assets in res://assets.

const MapData := preload("res://maps/vis/vis_map.gd")
const MK := preload("res://scripts/mesh_kit.gd")
const OsmBuilder := preload("res://scripts/game/osm_builder.gd")

const CHUNK := 48
const TEX := "res://assets/textures/"
const ENV := "res://assets/env/"

const TERRAIN_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D grass_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro : filter_linear_mipmap, repeat_enable;
uniform float tile = 0.16;

varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float m = texture(macro, wp.xz * 0.0035).r;
	float m2 = texture(macro, wp.xz * 0.03 + vec2(0.5)).r;
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	vec2 uv = wp.xz * tile;
	vec2 uv_far = wp.xz * tile * 0.21 + vec2(0.37, 0.11);
	vec2 side = abs(wn.x) > abs(wn.z) ? wp.zy : wp.xy;
	vec2 ruv = mix(wp.xz, side, smoothstep(0.3, 0.5, slope)) * tile * 0.6;

	float w_rock = smoothstep(0.2, 0.4, slope + (m2 - 0.5) * 0.15);
	float w_sand = (1.0 - smoothstep(0.8, 2.6, wp.y + (m2 - 0.5) * 1.5)) * (1.0 - w_rock);
	float w_dirt = smoothstep(0.52, 0.72, m) * (1.0 - w_rock) * (1.0 - w_sand) * 0.85;
	float w_grass = clamp(1.0 - w_rock - w_sand - w_dirt, 0.0, 1.0);

	vec3 ga = mix(texture(grass_a, uv).rgb, texture(grass_a, uv_far).rgb, 0.45);
	vec3 da = mix(texture(dirt_a, uv).rgb, texture(dirt_a, uv_far).rgb, 0.35);
	vec3 ra = texture(rock_a, ruv).rgb;
	vec3 sa = texture(sand_a, uv * 1.3).rgb;
	vec3 col = ga * w_grass + da * w_dirt + ra * w_rock + sa * w_sand;
	col *= 0.86 + (m - 0.5) * 0.35;
	ALBEDO = col;

	vec3 n = texture(grass_n, uv).rgb * w_grass + texture(dirt_n, uv).rgb * w_dirt
		+ texture(rock_n, ruv).rgb * w_rock + texture(sand_n, uv * 1.3).rgb * w_sand;
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = mix(0.92, 0.8, w_rock);
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx;

uniform vec3 deep : source_color = vec3(0.01, 0.11, 0.2);
uniform vec3 shallow : source_color = vec3(0.06, 0.42, 0.45);
uniform sampler2D wave : filter_linear_mipmap, repeat_enable;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv1 = wp.xz * 0.018 + TIME * vec2(0.011, 0.006);
	vec2 uv2 = wp.xz * 0.047 - TIME * vec2(0.007, 0.013);
	NORMAL_MAP = mix(texture(wave, uv1).rgb, texture(wave, uv2).rgb, 0.5);
	NORMAL_MAP_DEPTH = 0.7;
	float shore = COLOR.r;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	ALBEDO = mix(deep, shallow, shore) + vec3(0.08, 0.12, 0.14) * fres;
	ROUGHNESS = 0.06;
	SPECULAR = 0.65;
}
"""

var heights: PackedFloat32Array
var width := 0
var depth := 0
var spacing := 32.0
var origin := Vector2.ZERO
var sun: DirectionalLight3D
var env: Environment
var loot_points: Array[Vector3] = []
var rng := RandomNumberGenerator.new()

var _plaster_mats: Array[StandardMaterial3D] = []
var _roof_mat: StandardMaterial3D
var _window_mat: StandardMaterial3D
var _shutter_mats: Array[StandardMaterial3D] = []
var _concrete_mat: StandardMaterial3D
var _asphalt_mat: StandardMaterial3D
var _tree_trunk_mat: StandardMaterial3D
var _dirt_mat: StandardMaterial3D
var _tree_leaf_mat: StandardMaterial3D


## Builds the whole island. Call with `await` so a loading screen can update between steps.
func build(progress: Callable) -> void:
	rng.seed = 2026
	var shape := load(MapData.HEIGHTMAP) as HeightMapShape3D
	width = shape.map_width
	depth = shape.map_depth
	heights = shape.map_data
	spacing = MapData.SPACING
	origin = Vector2(-(width - 1) * spacing * 0.5, -(depth - 1) * spacing * 0.5)
	_make_materials()
	progress.call(0.1, "Sky and light")
	_build_environment()
	await get_tree().process_frame
	progress.call(0.2, "Terrain (real elevation)")
	_build_terrain()
	await get_tree().process_frame
	progress.call(0.45, "Sea")
	_build_sea()
	await get_tree().process_frame
	if OsmBuilder.available():
		progress.call(0.55, "Real buildings and roads (OpenStreetMap)")
		await get_tree().process_frame
		var built := OsmBuilder.build(self)
		if built < 50:
			_build_towns()
	else:
		progress.call(0.55, "Towns")
		_build_towns()
	await get_tree().process_frame
	progress.call(0.7, "Military sites")
	_build_military()
	_build_airfield()
	await get_tree().process_frame
	progress.call(0.8, "Nature")
	_build_nature()
	await get_tree().process_frame
	progress.call(0.95, "Ready")


# --- Height queries -----------------------------------------------------------------

func _h(i: int, j: int) -> float:
	return heights[clampi(j, 0, depth - 1) * width + clampi(i, 0, width - 1)]


func height_at(x: float, z: float) -> float:
	var gx := (x - origin.x) / spacing
	var gz := (z - origin.y) / spacing
	var i := clampi(int(floor(gx)), 0, width - 2)
	var j := clampi(int(floor(gz)), 0, depth - 2)
	var fx := clampf(gx - i, 0.0, 1.0)
	var fz := clampf(gz - j, 0.0, 1.0)
	var a := lerpf(_h(i, j), _h(i + 1, j), fx)
	var b := lerpf(_h(i, j + 1), _h(i + 1, j + 1), fx)
	return lerpf(a, b, fz)


func normal_at(x: float, z: float) -> Vector3:
	var e := spacing * 0.5
	return Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e, height_at(x, z - e) - height_at(x, z + e)).normalized()


func is_land(x: float, z: float, min_height: float = 1.5) -> bool:
	return height_at(x, z) > min_height


func ground_point(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)


## Random dry land point, optionally within `radius` of `center`.
func random_land_point(center: Vector2 = Vector2.ZERO, radius: float = -1.0, max_slope: float = 0.35) -> Vector3:
	for attempt in 80:
		var p: Vector2
		if radius > 0.0:
			var a := rng.randf() * TAU
			p = center + Vector2(cos(a), sin(a)) * radius * sqrt(rng.randf())
		else:
			p = Vector2(rng.randf_range(origin.x, -origin.x), rng.randf_range(origin.y, -origin.y))
		if is_land(p.x, p.y, 2.0) and 1.0 - normal_at(p.x, p.y).y < max_slope:
			return ground_point(p.x, p.y)
	return ground_point(center.x, center.y)


func size() -> Vector2:
	return Vector2((width - 1) * spacing, (depth - 1) * spacing)


# --- Environment ------------------------------------------------------------------

func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	var sky_tex := TEX + "sky_partly_cloudy_2k.hdr"
	if ResourceLoader.exists(sky_tex):
		pano.panorama = load(sky_tex)
		sky.sky_material = pano
	else:
		sky.sky_material = ProceduralSkyMaterial.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.8, 0.9)
	env.fog_density = 0.00018
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 160.0
	add_child(sun)
	sun.transform = Transform3D(Basis.looking_at(Vector3(0.45, -0.62, -0.64), Vector3.UP), Vector3(0, 100, 0))


func _make_materials() -> void:
	var tints := [Color(0.98, 0.95, 0.88), Color(0.95, 0.88, 0.74), Color(0.9, 0.9, 0.88), Color(0.97, 0.86, 0.7)]
	for t: Color in tints:
		var m := _textured("plaster", 0.25)
		m.albedo_color = t
		_plaster_mats.append(m)
	_roof_mat = _textured("roof", 0.5)
	_roof_mat.albedo_color = Color(0.92, 0.6, 0.45)
	_window_mat = MK.mat(Color(0.06, 0.08, 0.1), 0.08, 0.5)
	for c: Color in [Color(0.16, 0.32, 0.2), Color(0.32, 0.2, 0.12), Color(0.2, 0.3, 0.42)]:
		_shutter_mats.append(MK.mat(c, 0.7))
	_concrete_mat = _textured("concrete", 0.2)
	_asphalt_mat = _textured("asphalt", 0.08)
	_dirt_mat = _textured("dirt", 0.12)
	_tree_trunk_mat = MK.mat(Color(0.32, 0.24, 0.17), 0.95)
	_tree_leaf_mat = MK.mat(Color(0.2, 0.32, 0.14), 0.9)
	_tree_leaf_mat.albedo_texture = MK.noise_texture([Color(0.14, 0.24, 0.1), Color(0.26, 0.38, 0.17), Color(0.33, 0.42, 0.2)], [0.0, 0.6, 1.0], 0.08, 128, 9)
	_tree_leaf_mat.uv1_triplanar = true
	_tree_leaf_mat.uv1_scale = Vector3(0.6, 0.6, 0.6)


## Materials shared with the OpenStreetMap building/road builder.
func osm_materials() -> Dictionary:
	return {
		"plaster": _plaster_mats,
		"shutters": _shutter_mats,
		"roof": _roof_mat,
		"window": _window_mat,
		"concrete": _concrete_mat,
		"asphalt": _asphalt_mat,
		"dirt": _dirt_mat,
	}


## World-space textured PBR material from res://assets/textures/<name>_*.jpg
func _textured(tex_name: String, scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var a := TEX + tex_name + "_albedo.jpg"
	var n := TEX + tex_name + "_normal.jpg"
	var r := TEX + tex_name + "_rough.jpg"
	if ResourceLoader.exists(a):
		m.albedo_texture = load(a)
	if ResourceLoader.exists(n):
		m.normal_enabled = true
		m.normal_texture = load(n)
	if ResourceLoader.exists(r):
		m.roughness_texture = load(r)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	return m


# --- Terrain ------------------------------------------------------------------------

func _build_terrain() -> void:
	var sh := Shader.new()
	sh.code = TERRAIN_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	for layer in ["grass", "dirt", "rock", "sand"]:
		var a: String = TEX + layer + "_albedo.jpg"
		var n: String = TEX + layer + "_normal.jpg"
		if ResourceLoader.exists(a):
			mat.set_shader_parameter(layer + "_a", load(a))
		if ResourceLoader.exists(n):
			mat.set_shader_parameter(layer + "_n", load(n))
	mat.set_shader_parameter("macro", MK.noise_texture([Color.BLACK, Color.WHITE], [0.0, 1.0], 0.01, 256, 31))

	for cj in range(0, depth - 1, CHUNK):
		for ci in range(0, width - 1, CHUNK):
			var i1 := mini(ci + CHUNK, width - 1)
			var j1 := mini(cj + CHUNK, depth - 1)
			var max_h := -100.0
			for j in range(cj, j1 + 1, 4):
				for i in range(ci, i1 + 1, 4):
					max_h = maxf(max_h, _h(i, j))
			if max_h < -4.0:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = _chunk_mesh(ci, cj, i1, j1)
			mi.material_override = mat
			add_child(mi)

	# Collision: a uniformly scaled heightmap (heights divided by the grid spacing).
	var col := HeightMapShape3D.new()
	col.map_width = width
	col.map_depth = depth
	var scaled := heights.duplicate()
	for k in scaled.size():
		scaled[k] = scaled[k] / spacing
	col.map_data = scaled
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = col
	cs.scale = Vector3(spacing, spacing, spacing)
	body.add_child(cs)
	add_child(body)


func _grid_normal(i: int, j: int) -> Vector3:
	return Vector3(_h(i - 1, j) - _h(i + 1, j), 2.0 * spacing, _h(i, j - 1) - _h(i, j + 1)).normalized()


func _chunk_mesh(i0: int, j0: int, i1: int, j1: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var cols := i1 - i0 + 1
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			verts.append(Vector3(origin.x + i * spacing, _h(i, j), origin.y + j * spacing))
			norms.append(_grid_normal(i, j))
	for j in range(j1 - j0):
		for i in range(cols - 1):
			var a := j * cols + i
			var b := a + 1
			var c := a + cols
			var d := c + 1
			idx.append_array(PackedInt32Array([a, b, d, a, d, c]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- Sea ----------------------------------------------------------------------------

func _build_sea() -> void:
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var wave := NoiseTexture2D.new()
	wave.width = 256
	wave.height = 256
	wave.seamless = true
	wave.as_normal_map = true
	wave.bump_strength = 6.0
	var n := FastNoiseLite.new()
	n.frequency = 0.03
	n.fractal_octaves = 3
	wave.noise = n
	mat.set_shader_parameter("wave", wave)
	# Sea surface over the map, with vertex colour = how shallow the water is.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 4
	var sea_cols := 0
	for j in range(0, depth, step):
		sea_cols = 0
		for i in range(0, width, step):
			var h := _h(i, j)
			var shallow := clampf(1.0 + h / 12.0, 0.0, 1.0)
			st.set_color(Color(shallow, 0, 0))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(origin.x + i * spacing, 0.0, origin.y + j * spacing))
			sea_cols += 1
	var sea_rows := int(ceil(float(depth) / step))
	for j in sea_rows - 1:
		for i in sea_cols - 1:
			var a := j * sea_cols + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + sea_cols + 1)
			st.add_index(a)
			st.add_index(a + sea_cols + 1)
			st.add_index(a + sea_cols)
	var sea := MeshInstance3D.new()
	sea.mesh = st.commit()
	sea.material_override = mat
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	# Open sea to the horizon.
	var far := PlaneMesh.new()
	far.size = Vector2(80000, 80000)
	var far_mi := MeshInstance3D.new()
	far_mi.mesh = far
	far_mi.material_override = mat
	far_mi.position = Vector3(0, -0.15, 0)
	far_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far_mi)


# --- Mesh merging helper ------------------------------------------------------------------

## Collects primitive parts and commits them as one ArrayMesh (one surface per material).
class Merger:
	var tools := {}
	var order: Array = []

	func add(mesh: Mesh, xf: Transform3D, mat: Material) -> void:
		if not tools.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mat] = st
			order.append(mat)
		var t: SurfaceTool = tools[mat]
		t.append_from(mesh, 0, xf)

	func box(size: Vector3, xf: Transform3D, mat: Material) -> void:
		var m := BoxMesh.new()
		m.size = size
		add(m, xf, mat)

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for mat in order:
			var st: SurfaceTool = tools[mat]
			st.generate_tangents()
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
		return mesh


func _static_box(pos: Vector3, size: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	body.add_child(cs)
	add_child(body)
	body.transform = Transform3D(Basis(Vector3.UP, yaw), pos)


# --- Towns ----------------------------------------------------------------------------

func _build_towns() -> void:
	for poi in MapData.POIS:
		var kind := str(poi["kind"])
		var c: Vector2 = poi["pos"]
		var count := 0
		var radius := 0.0
		match kind:
			"town":
				count = 46
				radius = 260.0
			"village":
				count = 14
				radius = 120.0
			_:
				continue
		var placed: Array[Vector2] = []
		var tries := 0
		while placed.size() < count and tries < count * 30:
			tries += 1
			var a := rng.randf() * TAU
			var p := c + Vector2(cos(a), sin(a)) * radius * sqrt(rng.randf())
			if not is_land(p.x, p.y, 2.5) or 1.0 - normal_at(p.x, p.y).y > 0.3:
				continue
			var ok := true
			for q in placed:
				if q.distance_to(p) < 16.0:
					ok = false
					break
			if not ok:
				continue
			placed.append(p)
			_house(p, a + PI * 0.5 + rng.randf_range(-0.3, 0.3))


func _house(p: Vector2, yaw: float) -> void:
	var w := rng.randf_range(7.0, 12.0)
	var d := rng.randf_range(6.0, 9.5)
	var floors := rng.randi_range(1, 3)
	var fh := 3.1
	var wall_h := floors * fh
	# Lowest corner decides the base so the house never floats.
	var base := INF
	var rot := Basis(Vector3.UP, yaw)
	for cx: float in [-0.5, 0.5]:
		for cz: float in [-0.5, 0.5]:
			var corner := rot * Vector3(cx * w, 0, cz * d)
			base = minf(base, height_at(p.x + corner.x, p.y + corner.z))
	var foundation := 2.0
	var merger := Merger.new()
	var plaster: StandardMaterial3D = _plaster_mats[rng.randi() % _plaster_mats.size()]
	var shutter: StandardMaterial3D = _shutter_mats[rng.randi() % _shutter_mats.size()]
	merger.box(Vector3(w, wall_h + foundation, d), Transform3D(Basis(), Vector3(0, (wall_h - foundation) * 0.5, 0)), plaster)
	# Terracotta gable roof.
	var roof := PrismMesh.new()
	roof.size = Vector3(w + 0.6, 2.2, d + 0.6)
	merger.add(roof, Transform3D(Basis(), Vector3(0, wall_h + 1.1, 0)), _roof_mat)
	# Windows with shutters on the long sides, a door on the front.
	var per_row := maxi(int(w / 3.0), 1)
	for f in floors:
		for k in per_row:
			var x := (float(k) + 0.5) / per_row * w - w * 0.5
			var y := f * fh + 1.6
			for side: float in [-1.0, 1.0]:
				if f == 0 and k == per_row / 2 and side > 0.0:
					merger.box(Vector3(1.1, 2.2, 0.08), Transform3D(Basis(), Vector3(x, 1.1, side * (d * 0.5 + 0.02))), shutter)
					continue
				merger.box(Vector3(0.9, 1.2, 0.06), Transform3D(Basis(), Vector3(x, y, side * (d * 0.5 + 0.02))), _window_mat)
				merger.box(Vector3(0.4, 1.25, 0.05), Transform3D(Basis(), Vector3(x - 0.68, y, side * (d * 0.5 + 0.05))), shutter)
				merger.box(Vector3(0.4, 1.25, 0.05), Transform3D(Basis(), Vector3(x + 0.68, y, side * (d * 0.5 + 0.05))), shutter)
	var mi := MeshInstance3D.new()
	mi.mesh = merger.commit()
	mi.visibility_range_end = 1400.0
	add_child(mi)
	mi.transform = Transform3D(rot, Vector3(p.x, base, p.y))
	_static_box(Vector3(p.x, base + wall_h * 0.5, p.y), Vector3(w, wall_h + 1.0, d), yaw)
	# Loot at the doorstep and beside the house.
	var door := rot * Vector3(0, 0, d * 0.5 + 1.2)
	loot_points.append(ground_point(p.x + door.x, p.y + door.z) + Vector3(0, 0.05, 0))
	var side_pt := rot * Vector3(w * 0.5 + 1.3, 0, 0)
	loot_points.append(ground_point(p.x + side_pt.x, p.y + side_pt.z) + Vector3(0, 0.05, 0))


# --- Military sites -------------------------------------------------------------------------

func _load_mesh(file: String) -> Mesh:
	var path := ENV + file
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var inst := scene.instantiate()
	var found: Mesh = null
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		found = (n as MeshInstance3D).mesh
		break
	inst.free()
	return found


func _prop(mesh: Mesh, pos: Vector3, yaw: float, collision_size: Vector3 = Vector3.ZERO) -> void:
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.visibility_range_end = 450.0
	add_child(mi)
	mi.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	if collision_size != Vector3.ZERO:
		_static_box(pos + Vector3(0, collision_size.y * 0.5, 0), collision_size, yaw)


func _build_military() -> void:
	var barrier := _load_mesh("concrete_road_barrier_02.glb")
	var crate_a := _load_mesh("wooden_military_crate.glb")
	var crate_b := _load_mesh("old_military_crate.glb")
	var barrel := _load_mesh("barrel_01.glb")
	var jerry := _load_mesh("metal_jerrycan_green.glb")
	var box := _load_mesh("utility_box_01.glb")
	for poi in MapData.POIS:
		var kind := str(poi["kind"])
		if kind != "military" and kind != "airfield" and kind != "peak":
			continue
		var c: Vector2 = poi["pos"]
		var centre := random_land_point(c, 120.0, 0.25)
		# Concrete bunker with a firing slit.
		var bunker := Merger.new()
		bunker.box(Vector3(9, 4, 7), Transform3D(Basis(), Vector3(0, 0.5, 0)), _concrete_mat)
		bunker.box(Vector3(5, 0.5, 0.1), Transform3D(Basis(), Vector3(0, 1.4, 3.52)), _window_mat)
		var bm := MeshInstance3D.new()
		bm.mesh = bunker.commit()
		add_child(bm)
		var yaw := rng.randf() * TAU
		bm.transform = Transform3D(Basis(Vector3.UP, yaw), centre)
		_static_box(centre + Vector3(0, 0.5, 0), Vector3(9, 4, 7), yaw)
		# Barriers, crates, barrels and loot around it.
		for k in 22:
			var p := random_land_point(Vector2(centre.x, centre.z), 45.0, 0.3)
			var r := rng.randi() % 6
			var py := rng.randf() * TAU
			match r:
				0:
					_prop(barrier, p, py, Vector3(2.0, 1.0, 0.6))
				1:
					_prop(crate_a, p, py, Vector3(1.2, 0.8, 0.8))
				2:
					_prop(crate_b, p, py, Vector3(1.0, 0.7, 0.7))
				3:
					_prop(barrel, p, py, Vector3(0.6, 0.9, 0.6))
				4:
					_prop(jerry, p, py)
				5:
					_prop(box, p, py, Vector3(0.8, 1.2, 0.5))
			if k % 2 == 0:
				loot_points.append(p + Vector3(rng.randf_range(-1.5, 1.5), 0.05, rng.randf_range(-1.5, 1.5)))


func _build_airfield() -> void:
	for poi in MapData.POIS:
		if str(poi["kind"]) != "airfield":
			continue
		var c: Vector2 = poi["pos"]
		var length := 900.0
		var segs := 18
		for s in segs:
			var x := c.x - length * 0.5 + (s + 0.5) * length / segs
			var y := height_at(x, c.y)
			var m := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(length / segs + 0.5, 0.6, 28.0)
			m.mesh = b
			m.material_override = _asphalt_mat
			add_child(m)
			m.position = Vector3(x, y - 0.1, c.y)
			_static_box(m.position, b.size, 0.0)


# --- Nature ----------------------------------------------------------------------------------

func _multimesh(mesh: Mesh, xforms: Array[Transform3D], range_end: float, shadows: bool) -> void:
	if mesh == null or xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.visibility_range_end = range_end
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _pine_mesh() -> ArrayMesh:
	# Mediterranean (Aleppo) pine: leaning trunk with an umbrella-shaped crown.
	var merger := Merger.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.3
	trunk.height = 7.0
	trunk.radial_segments = 7
	merger.add(trunk, Transform3D(Basis(Vector3(0, 0, 1), 0.08), Vector3(0.25, 3.5, 0)), _tree_trunk_mat)
	for k in 5:
		var s := SphereMesh.new()
		s.radius = 2.4
		s.height = 2.2
		s.radial_segments = 10
		s.rings = 5
		var a := k * TAU / 5.0
		var off := Vector3(cos(a) * 1.6, 7.2 + (k % 2) * 0.6, sin(a) * 1.6) if k > 0 else Vector3(0.4, 7.9, 0)
		merger.add(s, Transform3D(Basis(), off), _tree_leaf_mat)
	return merger.commit()


func _near_poi(x: float, z: float, radius: float) -> bool:
	for poi in MapData.POIS:
		var c: Vector2 = poi["pos"]
		if c.distance_squared_to(Vector2(x, z)) < radius * radius:
			return true
	return false


func _build_nature() -> void:
	var cell := 1500.0
	var groups := {}
	var rocks := [_load_mesh("rock_07.glb"), _load_mesh("rock_09.glb"), _load_mesh("rock_moss_set_01.glb")]
	var shrubs := [_load_mesh("shrub_03.glb"), _load_mesh("shrub_04.glb")]
	var pine := _pine_mesh()
	var noise := FastNoiseLite.new()
	noise.frequency = 0.0012
	noise.seed = 77
	var sz := size()
	var area := sz.x * sz.y
	var samples := int(area / 2500.0)
	for k in samples:
		var x := rng.randf_range(origin.x, -origin.x)
		var z := rng.randf_range(origin.y, -origin.y)
		var h := height_at(x, z)
		if h < 2.0:
			continue
		var n := normal_at(x, z)
		var slope := 1.0 - n.y
		var forest := noise.get_noise_2d(x, z)
		var key := Vector2i(int(floor(x / cell)), int(floor(z / cell)))
		var kind := ""
		var mesh: Mesh = null
		if slope > 0.22 and rng.randf() < 0.6:
			kind = "rock"
			mesh = rocks[rng.randi() % rocks.size()]
		elif forest > 0.15 and rng.randf() < 0.75:
			kind = "pine"
			mesh = pine
		elif rng.randf() < 0.55:
			kind = "shrub"
			mesh = shrubs[rng.randi() % shrubs.size()]
		if mesh == null:
			continue
		var s := rng.randf_range(0.7, 1.4)
		if kind == "rock":
			s = rng.randf_range(0.8, 2.6)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, h - 0.15, z))
		var id := "%s_%d_%d_%d" % [kind, mesh.get_instance_id(), key.x, key.y]
		if not groups.has(id):
			var fresh: Array[Transform3D] = []
			groups[id] = {"mesh": mesh, "kind": kind, "xforms": fresh}
		var g: Dictionary = groups[id]
		var list: Array[Transform3D] = g["xforms"]
		list.append(xf)
		# Collision for trunks and big rocks near places where fights happen, so they work as cover.
		if _near_poi(x, z, 900.0):
			if kind == "pine":
				_static_box(Vector3(x, h + 3.0, z), Vector3(0.6, 6.0, 0.6), 0.0)
			elif kind == "rock" and s > 1.4:
				_static_box(Vector3(x, h + 0.4 * s, z), Vector3(1.2, 0.9, 1.2) * s, 0.0)
	for id in groups:
		var g: Dictionary = groups[id]
		var kind := str(g["kind"])
		var list: Array[Transform3D] = g["xforms"]
		var range_end := 260.0
		if kind == "pine":
			range_end = 900.0
		elif kind == "rock":
			range_end = 500.0
		_multimesh(g["mesh"], list, range_end, kind != "shrub")
