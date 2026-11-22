extends Node3D
## The 3D lobby backdrop: animated sky, sun + rim lighting, a small military outpost,
## an off-road buggy, a crashed transport plane, mountains with a radio mast,
## trees, wind-blown grass and the hero character on a dirt patch.

const MK := preload("res://scripts/mesh_kit.gd")
const CharacterModel := preload("res://scripts/character_model.gd")

const SKY_SHADER := """
shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.12, 0.35, 0.78);
uniform vec3 horizon_color : source_color = vec3(0.64, 0.79, 0.95);
uniform vec3 ground_color : source_color = vec3(0.40, 0.45, 0.43);
uniform vec3 cloud_light : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shadow : source_color = vec3(0.58, 0.66, 0.78);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.5;
uniform float cloud_speed = 0.006;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * vnoise(p);
		p = p * 2.03 + vec2(3.1, 1.7);
		amp *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float h = dir.y;
	vec3 col = mix(horizon_color, zenith_color, pow(clamp(h, 0.0, 1.0), 0.6));
	col = mix(col, ground_color, 1.0 - smoothstep(-0.08, 0.0, h));
	col += vec3(0.08, 0.06, 0.03) * pow(1.0 - abs(h), 10.0);
	if (h > 0.0) {
		vec2 uv = dir.xz / (h + 0.12);
		uv = uv * 0.9 + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.35);
		float n = fbm(uv * 1.3);
		float n2 = fbm(uv * 2.6 + vec2(5.2, 1.3));
		float cover = smoothstep(cloud_coverage, cloud_coverage + 0.22, n);
		float shade = smoothstep(0.35, 0.85, n2);
		vec3 ccol = mix(cloud_shadow, cloud_light, shade);
		float fade = smoothstep(0.0, 0.2, h);
		col = mix(col, ccol, cover * fade * 0.92);
	}
	if (LIGHT0_ENABLED) {
		float sd = max(dot(dir, LIGHT0_DIRECTION), 0.0);
		col += LIGHT0_COLOR * 0.22 * pow(sd, 24.0);
		col += LIGHT0_COLOR * smoothstep(0.9994, 0.9998, sd) * 6.0;
	}
	COLOR = col;
}
"""

const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform vec3 base_color : source_color = vec3(0.16, 0.27, 0.07);
uniform vec3 tip_color : source_color = vec3(0.56, 0.6, 0.24);
uniform float sway = 0.07;

varying float blade_h;

void vertex() {
	blade_h = UV.y;
	vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float t = TIME * 1.7 + world_pos.x * 0.35 + world_pos.z * 0.27;
	float k = blade_h * blade_h;
	VERTEX.x += sin(t) * sway * k;
	VERTEX.z += cos(t * 0.8) * sway * 0.6 * k;
}

void fragment() {
	ALBEDO = mix(base_color, tip_color, blade_h) * COLOR.rgb;
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.22, 0.26, 0.08);
}
"""

const DIRT_SHADER := """
shader_type spatial;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 dirt_a : source_color = vec3(0.30, 0.27, 0.23);
uniform vec3 dirt_b : source_color = vec3(0.47, 0.44, 0.38);
uniform vec3 wet_color : source_color = vec3(0.09, 0.09, 0.1);
uniform vec2 puddle_center = vec2(0.6, 0.47);

void fragment() {
	float n = texture(noise_tex, UV * 3.0).r;
	float n2 = texture(noise_tex, UV * 0.7 + vec2(0.31, 0.17)).r;
	float r = length(UV - vec2(0.5)) * 2.0;
	if (r + (n2 - 0.5) * 0.5 > 0.93) {
		discard;
	}
	vec3 col = mix(dirt_a, dirt_b, n);
	float d = length((UV - puddle_center) * vec2(1.0, 1.7)) + (n2 - 0.5) * 0.08;
	float p = 1.0 - smoothstep(0.075, 0.1, d);
	ALBEDO = mix(col, wet_color, p * 0.9);
	ROUGHNESS = mix(0.95, 0.03, p);
	SPECULAR = mix(0.35, 0.9, p);
}
"""

const FENCE_SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform vec3 wire_color : source_color = vec3(0.56, 0.58, 0.6);
uniform vec2 panel_size = vec2(6.0, 2.0);

void fragment() {
	vec2 p = UV * panel_size * 7.0;
	vec2 r = vec2(p.x + p.y, p.x - p.y);
	vec2 g = abs(fract(r) - 0.5);
	float wire = smoothstep(0.38, 0.44, max(g.x, g.y));
	ALBEDO = wire_color;
	METALLIC = 0.6;
	ROUGHNESS = 0.45;
	ALPHA = wire;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
"""

const DIRT_RADIUS := 3.4
const CRATE_MODEL := "res://models/wooden_crate_1.fbx"
const BUGGY_POS := Vector3(-3.5, 0.0, -4.7)

var camera: Camera3D
var camera_attributes: CameraAttributesPractical
var sun: DirectionalLight3D
var env: Environment
var character_pivot: Node3D
var character: CharacterModel

var _grass_mm: MultiMesh
var _grass_total := 0
var _terrain_noise: FastNoiseLite
var _beacon: MeshInstance3D
var _t := 0.0


func _ready() -> void:
	_terrain_noise = FastNoiseLite.new()
	_terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_terrain_noise.frequency = 0.008
	_terrain_noise.fractal_octaves = 4
	_terrain_noise.seed = 42

	_build_environment()
	_build_lights()
	_build_camera()
	_build_ground()
	_build_terrain()
	_build_outpost()
	_build_fences()
	_build_buggy()
	_build_wreck()
	_build_props()
	_build_trees()
	_build_grass()
	_build_character()


func _process(delta: float) -> void:
	_t += delta
	if _beacon:
		_beacon.visible = fmod(_t, 1.6) < 0.8


## 0 = Smooth, 1 = Balanced, 2 = HD, 3 = Ultra HD
func apply_quality(q: int) -> void:
	q = clampi(q, 0, 3)
	var vp := get_viewport()
	env.glow_enabled = q >= 1
	env.ssao_enabled = q >= 2
	env.ssr_enabled = q >= 3
	sun.shadow_enabled = q >= 1
	if q >= 2:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	else:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	camera_attributes.dof_blur_far_enabled = q >= 2
	var msaa_levels := [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X]
	var scales := [0.7, 0.85, 1.0, 1.0]
	vp.msaa_3d = msaa_levels[q]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q <= 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.scaling_3d_scale = scales[q]
	if _grass_mm:
		var density := [0.3, 0.6, 1.0, 1.0]
		var ratio: float = density[q]
		_grass_mm.visible_instance_count = int(_grass_total * ratio)


# --- Environment & lights ------------------------------------------------------

func _build_environment() -> void:
	var sky_shader := Shader.new()
	sky_shader.code = SKY_SHADER
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = sky_shader
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.77, 0.9)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.15
	env.fog_density = 0.0028
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.06

	camera_attributes = CameraAttributesPractical.new()
	camera_attributes.dof_blur_far_enabled = true
	camera_attributes.dof_blur_far_distance = 14.0
	camera_attributes.dof_blur_far_transition = 25.0
	camera_attributes.dof_blur_amount = 0.05

	var we := WorldEnvironment.new()
	we.environment = env
	we.camera_attributes = camera_attributes
	add_child(we)


func _build_lights() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.55
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
	# Light travels away from the camera, towards the right: shadows fall back-right.
	sun.transform = Transform3D(Basis.looking_at(Vector3(0.42, -0.72, -0.55), Vector3.UP), Vector3(0, 20, 0))

	# Cool rim light behind the hero so the silhouette pops off the background.
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.72, 0.84, 1.0)
	rim.light_energy = 2.2
	rim.omni_range = 4.0
	rim.position = Vector3(1.1, 2.3, -1.4)
	add_child(rim)

	# Warm fill from the camera side.
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.9, 0.8)
	fill.light_energy = 0.7
	fill.omni_range = 7.0
	fill.position = Vector3(-1.6, 1.8, 2.6)
	add_child(fill)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "LobbyCamera"
	camera.fov = 40.0
	camera.near = 0.05
	camera.far = 1500.0
	add_child(camera)
	camera.position = Vector3(0.0, 1.02, 3.4)
	camera.look_at(Vector3(0.0, 0.93, 0.0), Vector3.UP)
	camera.current = true


# --- Ground ---------------------------------------------------------------------

func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(1400, 1400)
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = MK.noise_texture(
		[Color(0.19, 0.28, 0.1), Color(0.31, 0.4, 0.15), Color(0.44, 0.47, 0.23), Color(0.36, 0.34, 0.22)],
		[0.0, 0.38, 0.7, 1.0], 0.012, 512, 3)
	gm.uv1_scale = Vector3(220, 220, 1)
	gm.roughness = 0.95
	MK.add(self, plane, gm, Transform3D.IDENTITY)

	# Dirt patch with a small puddle where the hero stands.
	var patch := PlaneMesh.new()
	patch.size = Vector2(DIRT_RADIUS * 2.0, DIRT_RADIUS * 2.0)
	var sh := Shader.new()
	sh.code = DIRT_SHADER
	var dm := ShaderMaterial.new()
	dm.shader = sh
	dm.set_shader_parameter("noise_tex", MK.noise_texture([Color.BLACK, Color.WHITE], [0.0, 1.0], 0.02, 256, 11))
	MK.add(self, patch, dm, Transform3D(Basis.IDENTITY, Vector3(0, 0.012, 0)), false)

	# Concrete apron in front of the outpost.
	MK.box(self, Vector3(16, 0.1, 10), Vector3(-11.3, 0.03, -28.6), MK.mat(Color(0.52, 0.52, 0.5), 0.95), Vector3(0, 24, 0))


## Conical peak (exponential falloff) so summits look rocky instead of rounded.
func _peak(x: float, z: float, cx: float, cz: float, amp: float, radius: float) -> float:
	var d := sqrt((x - cx) * (x - cx) + (z - cz) * (z - cz))
	return amp * exp(-d / radius)


func _height(x: float, z: float) -> float:
	var h := 0.0
	h += _peak(x, z, 66.0, -235.0, 34.0, 24.0)
	h += _peak(x, z, 30.0, -265.0, 16.0, 30.0)
	h += _peak(x, z, 10.0, -320.0, 26.0, 45.0)
	h += _peak(x, z, 140.0, -205.0, 20.0, 30.0)
	h += _peak(x, z, -110.0, -250.0, 20.0, 45.0)
	h += _peak(x, z, -220.0, -170.0, 14.0, 40.0)
	h += _peak(x, z, 230.0, -290.0, 30.0, 50.0)
	h += _peak(x, z, -60.0, -150.0, 7.0, 30.0)
	var ridge := 1.0 - absf(_terrain_noise.get_noise_2d(x, z))
	h *= 0.72 + 0.45 * ridge
	h += (_terrain_noise.get_noise_2d(x * 2.5 + 300.0, z * 2.5) * 0.5 + 0.5) * 8.0
	var e := clampf((-80.0 - z) / 55.0, 0.0, 1.0)
	e = e * e * (3.0 - 2.0 * e)
	return h * e - 1.0 * (1.0 - e)


func _build_terrain() -> void:
	var nx := 150
	var nz := 70
	var x0 := -480.0
	var x1 := 480.0
	var z0 := -500.0
	var z1 := -70.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var eps := 2.0
	for j in nz + 1:
		for i in nx + 1:
			var x := lerpf(x0, x1, float(i) / nx)
			var z := lerpf(z0, z1, float(j) / nz)
			var y := _height(x, z)
			var n := Vector3(_height(x - eps, z) - _height(x + eps, z), 2.0 * eps, _height(x, z - eps) - _height(x, z + eps)).normalized()
			var slope := 1.0 - n.y
			var c := Color(0.27, 0.38, 0.17)
			c = c.lerp(Color(0.17, 0.27, 0.14), clampf(y / 10.0, 0.0, 1.0))
			c = c.lerp(Color(0.44, 0.45, 0.45), clampf((y - 12.0) / 14.0 + slope * 1.8, 0.0, 1.0))
			c = c.lerp(Color(0.64, 0.66, 0.68), clampf((y - 32.0) / 8.0, 0.0, 1.0))
			st.set_color(c)
			st.set_normal(n)
			st.add_vertex(Vector3(x, y, z))
	# Clockwise winding seen from above = front face in Godot.
	for j in nz:
		for i in nx:
			var a := j * (nx + 1) + i
			var b := a + 1
			var c2 := a + (nx + 1)
			var d := c2 + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(d)
			st.add_index(a)
			st.add_index(d)
			st.add_index(c2)
	var tm := StandardMaterial3D.new()
	tm.vertex_color_use_as_albedo = true
	tm.vertex_color_is_srgb = true
	tm.roughness = 1.0
	var mi := MK.add(self, st.commit(), tm, Transform3D.IDENTITY)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Radio mast on the main peak.
	var top := Vector3(66.0, _height(66.0, -235.0) - 1.0, -235.0)
	_build_mast(top, 16.0)


func _build_mast(base: Vector3, height: float) -> void:
	var steel := MK.mat(Color(0.55, 0.55, 0.57), 0.5, 0.6)
	var w0 := 3.2
	var w1 := 0.5
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for k in 4:
		var c: Vector2 = corners[k]
		var cn: Vector2 = corners[(k + 1) % 4]
		var a := base + Vector3(c.x * w0, 0, c.y * w0)
		var b := base + Vector3(c.x * w1, height, c.y * w1)
		MK.tube(self, a, b, 0.22, steel, 6)
		for s in 5:
			var f0 := float(s) / 5.0
			var f1 := float(s + 1) / 5.0
			var p0 := base + Vector3(c.x * lerpf(w0, w1, f0), height * f0, c.y * lerpf(w0, w1, f0))
			var p1 := base + Vector3(cn.x * lerpf(w0, w1, f1), height * f1, cn.y * lerpf(w0, w1, f1))
			MK.tube(self, p0, p1, 0.1, steel, 5)
	MK.tube(self, base + Vector3(0, height, 0), base + Vector3(0, height + 5.0, 0), 0.15, steel, 6)
	MK.cylinder(self, 1.2, 1.2, 1.4, base + Vector3(0, height * 0.72, 0), MK.mat(Color(0.85, 0.85, 0.82), 0.6), Vector3(90, 30, 0))
	_beacon = MK.sphere(self, 0.6, base + Vector3(0, height + 5.3, 0), MK.emissive(Color(1.0, 0.15, 0.1), 6.0), Vector3.ONE, Vector3.ZERO, 10)


# --- Outpost --------------------------------------------------------------------

func _build_outpost() -> void:
	var o := Node3D.new()
	o.name = "Outpost"
	o.position = Vector3(-11.0, 0, -30.0)
	o.rotation_degrees = Vector3(0, 24, 0)
	add_child(o)
	var concrete := MK.mat(Color(0.75, 0.74, 0.71), 0.95)
	var concrete_dark := MK.mat(Color(0.6, 0.6, 0.58), 0.95)
	var window := MK.mat(Color(0.1, 0.13, 0.16), 0.08, 0.6)
	var door := MK.mat(Color(0.3, 0.34, 0.3), 0.6, 0.3)
	var rail := MK.mat(Color(0.42, 0.44, 0.43), 0.5, 0.6)

	# Ground floor.
	MK.box(o, Vector3(7.0, 3.2, 5.6), Vector3(0, 1.6, 0), concrete)
	MK.box(o, Vector3(7.25, 0.26, 5.85), Vector3(0, 3.25, 0), concrete_dark)
	for x: float in [-2.3, 2.3]:
		MK.box(o, Vector3(1.2, 0.95, 0.06), Vector3(x, 1.95, 2.81), window)
		MK.box(o, Vector3(1.32, 0.1, 0.16), Vector3(x, 1.43, 2.84), concrete_dark)
	for z: float in [-1.3, 1.3]:
		MK.box(o, Vector3(0.06, 0.95, 1.2), Vector3(3.51, 1.95, z), window)
	MK.box(o, Vector3(1.2, 2.25, 0.08), Vector3(0.1, 1.12, 2.82), door)
	MK.box(o, Vector3(1.6, 0.12, 0.8), Vector3(0.1, 2.4, 3.1), concrete_dark)

	# First floor.
	MK.box(o, Vector3(5.0, 2.6, 4.3), Vector3(-0.6, 4.65, -0.4), concrete)
	MK.box(o, Vector3(5.25, 0.22, 4.55), Vector3(-0.6, 6.05, -0.4), concrete_dark)
	for x: float in [-2.1, 0.5]:
		MK.box(o, Vector3(1.4, 0.9, 0.06), Vector3(x, 4.75, 1.76), window)
	MK.box(o, Vector3(0.06, 0.9, 2.0), Vector3(1.91, 4.75, -0.4), window)

	# Glass control cabin with a wide roof.
	MK.box(o, Vector3(3.4, 1.7, 3.4), Vector3(-0.9, 7.0, -0.6), window)
	for cx in [-1, 1]:
		for cz in [-1, 1]:
			var ix: int = cx
			var iz: int = cz
			MK.box(o, Vector3(0.16, 1.7, 0.16), Vector3(-0.9 + ix * 1.7, 7.0, -0.6 + iz * 1.7), concrete)
	MK.box(o, Vector3(4.6, 0.32, 4.6), Vector3(-0.9, 8.0, -0.6), concrete_dark)
	MK.tube(o, Vector3(-1.8, 8.1, -1.4), Vector3(-1.8, 11.0, -1.4), 0.05, rail, 6)
	MK.tube(o, Vector3(0.2, 8.1, -1.6), Vector3(0.2, 9.6, -1.6), 0.04, rail, 6)

	# Railing around the ground-floor roof terrace.
	var y0 := 3.38
	for i in 8:
		var px := -3.5 + i * 1.0
		MK.tube(o, Vector3(px, y0, 2.85), Vector3(px, y0 + 0.95, 2.85), 0.03, rail, 6)
	MK.tube(o, Vector3(-3.5, y0 + 0.95, 2.85), Vector3(3.5, y0 + 0.95, 2.85), 0.035, rail, 6)
	MK.tube(o, Vector3(-3.5, y0 + 0.5, 2.85), Vector3(3.5, y0 + 0.5, 2.85), 0.025, rail, 6)
	MK.tube(o, Vector3(3.55, y0 + 0.95, 2.85), Vector3(3.55, y0 + 0.95, -2.8), 0.035, rail, 6)
	for i in 6:
		var pz := 2.85 - i * 1.1
		MK.tube(o, Vector3(3.55, y0, pz), Vector3(3.55, y0 + 0.95, pz), 0.03, rail, 6)

	# Satellite dish on the terrace.
	var white := MK.mat(Color(0.92, 0.92, 0.9), 0.45)
	MK.tube(o, Vector3(2.4, y0, 0.9), Vector3(2.4, y0 + 1.1, 0.9), 0.07, rail, 8)
	MK.cylinder(o, 0.95, 0.12, 0.35, Vector3(2.4, y0 + 1.5, 0.95), white, Vector3(-38, 40, 0), Vector3.ONE, 28)
	MK.tube(o, Vector3(2.4, y0 + 1.45, 0.95), Vector3(2.75, y0 + 2.0, 1.45), 0.025, rail, 6)

	# Roof clutter: AC units and a water tank.
	MK.box(o, Vector3(0.9, 0.6, 0.6), Vector3(-2.6, y0 + 0.3, 1.9), MK.mat(Color(0.8, 0.8, 0.78), 0.6))
	MK.cylinder(o, 0.55, 0.55, 1.1, Vector3(1.2, 6.75, -1.6), MK.mat(Color(0.25, 0.3, 0.28), 0.6))

	# Sandbag wall beside the door.
	var sand := MK.mat(Color(0.58, 0.52, 0.39), 1.0)
	for row in 3:
		for k in 5:
			var off := 0.25 if row % 2 == 1 else 0.0
			var p := Vector3(1.6 + k * 0.5 + off, 0.15 + row * 0.24, 3.8)
			MK.capsule(o, p - Vector3(0.18, 0, 0), p + Vector3(0.18, 0, 0), 0.13, sand, Vector3(1.0, 1.0, 0.75))


func _build_fences() -> void:
	_fence_line(Vector3(-15.5, 0, -10.5), Vector3(-6.5, 0, -8.6))
	_fence_line(Vector3(-6.5, 0, -8.6), Vector3(-2.2, 0, -10.8))
	_fence_line(Vector3(5.0, 0, -15.5), Vector3(16.0, 0, -13.0))


func _fence_line(a: Vector3, b: Vector3) -> void:
	var post_mat := MK.mat(Color(0.5, 0.52, 0.52), 0.45, 0.7)
	var length := a.distance_to(b)
	var posts := maxi(int(ceil(length / 2.5)), 1)
	for i in posts + 1:
		var p := a.lerp(b, float(i) / posts)
		MK.tube(self, p, p + Vector3(0, 2.3, 0), 0.04, post_mat, 8)
	MK.tube(self, a + Vector3(0, 2.25, 0), b + Vector3(0, 2.25, 0), 0.03, post_mat, 6)
	MK.tube(self, a + Vector3(0, 0.15, 0), b + Vector3(0, 0.15, 0), 0.025, post_mat, 6)
	var quad := QuadMesh.new()
	quad.size = Vector2(length, 2.1)
	var sh := Shader.new()
	sh.code = FENCE_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("panel_size", Vector2(length, 2.1))
	var d := b - a
	var along := Basis(Vector3.UP, atan2(-d.z, d.x))
	MK.add(self, quad, m, Transform3D(along, (a + b) * 0.5 + Vector3(0, 1.2, 0)))


# --- Buggy ------------------------------------------------------------------------

func _build_buggy() -> void:
	var v := Node3D.new()
	v.name = "Buggy"
	v.position = BUGGY_POS
	v.rotation_degrees = Vector3(0, 38, 0)
	add_child(v)
	var red := MK.mat(Color(0.5, 0.05, 0.06), 0.35, 0.45)
	red.clearcoat_enabled = true
	red.clearcoat = 0.6
	var dark := MK.mat(Color(0.06, 0.06, 0.07), 0.5, 0.4)
	var tire := MK.mat(Color(0.05, 0.05, 0.05), 0.95)
	var rim_m := MK.mat(Color(0.55, 0.55, 0.58), 0.3, 0.85)
	var seat := MK.mat(Color(0.12, 0.1, 0.09), 0.8)
	var lamp := MK.emissive(Color(1.0, 0.92, 0.75), 0.8)

	var wheels := [Vector3(-0.84, 0.45, 1.15), Vector3(0.84, 0.45, 1.15), Vector3(-0.88, 0.5, -1.05), Vector3(0.88, 0.5, -1.05)]
	for i in 4:
		var w: Vector3 = wheels[i]
		var r := 0.45 if i < 2 else 0.5
		MK.cylinder(v, r, r, 0.36, w, tire, Vector3(0, 0, 90), Vector3.ONE, 22)
		MK.cylinder(v, r * 0.55, r * 0.55, 0.38, w, rim_m, Vector3(0, 0, 90), Vector3.ONE, 8)
		MK.cylinder(v, 0.09, 0.09, 0.4, w, dark, Vector3(0, 0, 90), Vector3.ONE, 8)
		for k in 8:
			var ang := TAU * k / 8.0
			var tread := w + Vector3(0, cos(ang) * r, sin(ang) * r)
			MK.box(v, Vector3(0.37, 0.08, 0.1), tread, tire, Vector3(rad_to_deg(ang), 0, 0))
		# Coil-over shock in red.
		var sx := signf(w.x)
		MK.tube(v, Vector3(sx * 0.42, 1.0, w.z * 0.85), w + Vector3(-sx * 0.2, 0.12, 0), 0.07, red, 10)
		MK.tube(v, Vector3(sx * 0.3, 0.55, w.z * 0.9), w + Vector3(-sx * 0.15, 0.0, 0), 0.035, dark, 6)

	MK.box(v, Vector3(1.3, 0.1, 2.7), Vector3(0, 0.5, 0), dark)
	MK.box(v, Vector3(0.24, 0.32, 1.3), Vector3(-0.62, 0.7, -0.1), red)
	MK.box(v, Vector3(0.24, 0.32, 1.3), Vector3(0.62, 0.7, -0.1), red)
	MK.box(v, Vector3(1.0, 0.26, 0.75), Vector3(0, 0.75, 1.35), red, Vector3(-14, 0, 0))
	MK.box(v, Vector3(0.95, 0.6, 0.75), Vector3(0, 0.88, -1.2), dark)
	MK.box(v, Vector3(0.7, 0.18, 0.55), Vector3(0, 1.24, -1.2), red)
	MK.tube(v, Vector3(0.3, 0.75, -1.55), Vector3(0.35, 1.05, -1.9), 0.05, rim_m, 8)
	MK.tube(v, Vector3(-0.3, 0.75, -1.55), Vector3(-0.35, 1.05, -1.9), 0.05, rim_m, 8)
	for sx: float in [-0.3, 0.3]:
		MK.box(v, Vector3(0.46, 0.12, 0.5), Vector3(sx, 0.64, -0.1), seat)
		MK.box(v, Vector3(0.46, 0.66, 0.12), Vector3(sx, 0.98, -0.42), seat, Vector3(-12, 0, 0))
	MK.torus(v, 0.13, 0.16, Vector3(-0.3, 1.05, 0.32), dark, Vector3(-55, 0, 0))

	# Roll cage.
	var cage := [
		[Vector3(-0.62, 0.55, -0.55), Vector3(-0.56, 1.62, -0.5)],
		[Vector3(0.62, 0.55, -0.55), Vector3(0.56, 1.62, -0.5)],
		[Vector3(-0.56, 1.62, -0.5), Vector3(0.56, 1.62, -0.5)],
		[Vector3(-0.62, 0.6, 0.78), Vector3(-0.5, 1.52, 0.25)],
		[Vector3(0.62, 0.6, 0.78), Vector3(0.5, 1.52, 0.25)],
		[Vector3(-0.5, 1.52, 0.25), Vector3(0.5, 1.52, 0.25)],
		[Vector3(-0.56, 1.62, -0.5), Vector3(-0.5, 1.52, 0.25)],
		[Vector3(0.56, 1.62, -0.5), Vector3(0.5, 1.52, 0.25)],
		[Vector3(-0.56, 1.62, -0.5), Vector3(-0.5, 0.95, -1.62)],
		[Vector3(0.56, 1.62, -0.5), Vector3(0.5, 0.95, -1.62)],
		[Vector3(-0.66, 0.88, 0.78), Vector3(-0.66, 0.88, -0.55)],
		[Vector3(0.66, 0.88, 0.78), Vector3(0.66, 0.88, -0.55)],
		[Vector3(-0.62, 0.6, 0.78), Vector3(-0.66, 0.55, 1.72)],
		[Vector3(0.62, 0.6, 0.78), Vector3(0.66, 0.55, 1.72)],
		[Vector3(-0.66, 0.55, 1.72), Vector3(0.66, 0.55, 1.72)],
		[Vector3(-0.5, 0.95, 1.72), Vector3(0.5, 0.95, 1.72)],
	]
	for seg in cage:
		var pa: Vector3 = seg[0]
		var pb: Vector3 = seg[1]
		MK.tube(v, pa, pb, 0.04, dark, 8)
	MK.box(v, Vector3(0.95, 0.08, 0.12), Vector3(0, 1.58, 0.22), dark)
	for sx: float in [-0.32, -0.11, 0.11, 0.32]:
		MK.box(v, Vector3(0.16, 0.06, 0.03), Vector3(sx, 1.58, 0.29), lamp)
	for sx: float in [-0.36, 0.36]:
		MK.cylinder(v, 0.075, 0.075, 0.06, Vector3(sx, 0.95, 1.73), lamp, Vector3(90, 0, 0))
		MK.cylinder(v, 0.09, 0.09, 0.05, Vector3(sx, 0.95, 1.7), dark, Vector3(90, 0, 0))
	# Spare wheel on the back.
	MK.cylinder(v, 0.38, 0.38, 0.22, Vector3(0, 1.25, -1.72), tire, Vector3(90, 0, 0), Vector3.ONE, 20)
	MK.cylinder(v, 0.2, 0.2, 0.24, Vector3(0, 1.25, -1.72), rim_m, Vector3(90, 0, 0), Vector3.ONE, 8)


# --- Crashed transport plane -------------------------------------------------------

func _build_wreck() -> void:
	var p := Node3D.new()
	p.name = "Wreck"
	p.position = Vector3(11.0, 0.0, -27.0)
	p.rotation_degrees = Vector3(0, -14, 5)
	add_child(p)
	var hull := MK.mat(Color(0.46, 0.49, 0.46), 0.7, 0.35)
	var hull_dark := MK.mat(Color(0.3, 0.32, 0.3), 0.8, 0.3)
	var burnt := MK.mat(Color(0.08, 0.08, 0.08), 1.0)
	var glass := MK.mat(Color(0.08, 0.1, 0.12), 0.1, 0.5)

	MK.cylinder(p, 1.7, 1.7, 15.0, Vector3(0, 1.45, 0), hull, Vector3(0, 0, 90), Vector3.ONE, 24)
	MK.sphere(p, 1.7, Vector3(-7.5, 1.45, 0), hull, Vector3(1.5, 1.0, 1.0))
	MK.cylinder(p, 0.45, 1.7, 5.5, Vector3(10.2, 1.95, 0), hull, Vector3(0, 0, -84), Vector3.ONE, 24)
	MK.box(p, Vector3(3.4, 3.8, 0.28), Vector3(11.8, 4.4, 0), hull, Vector3(0, 0, -22))
	MK.box(p, Vector3(2.6, 0.2, 7.8), Vector3(12.2, 2.4, 0), hull)
	MK.box(p, Vector3(1.4, 0.5, 2.6), Vector3(-8.8, 2.35, 0), glass, Vector3(0, 0, 18))
	# Wings: one intact, one snapped and dug into the ground.
	MK.box(p, Vector3(4.0, 0.32, 11.5), Vector3(-0.8, 2.5, -6.6), hull, Vector3(6, 0, 0))
	MK.box(p, Vector3(4.0, 0.32, 7.5), Vector3(-0.8, 1.3, 5.2), hull, Vector3(-14, 0, 2))
	MK.box(p, Vector3(3.4, 0.3, 4.0), Vector3(-0.4, 0.4, 10.6), hull_dark, Vector3(-28, 12, 4))
	for z: float in [-4.2, -8.4, 4.0]:
		MK.cylinder(p, 0.65, 0.7, 3.0, Vector3(-1.6, 1.4 if z < 0.0 else 0.75, z), hull_dark, Vector3(0, 0, 90), Vector3.ONE, 16)
	# Burn marks and missing panels.
	MK.box(p, Vector3(3.0, 1.6, 0.1), Vector3(2.0, 1.6, 1.66), burnt)
	MK.box(p, Vector3(1.6, 1.2, 0.1), Vector3(-3.5, 2.0, 1.66), burnt)
	MK.sphere(p, 1.0, Vector3(6.0, 0.2, 2.2), burnt, Vector3(2.5, 0.3, 1.2))


# --- Props ------------------------------------------------------------------------

func _build_props() -> void:
	var wood := MK.mat(Color(0.47, 0.35, 0.21), 0.9)
	var wood_dark := MK.mat(Color(0.32, 0.23, 0.14), 0.9)
	# Wooden ammo crates (imported FBX model). [position, yaw, longest side in metres]
	var crate_mat := StandardMaterial3D.new()
	crate_mat.albedo_texture = MK.noise_texture([Color(0.3, 0.2, 0.11), Color(0.5, 0.36, 0.2), Color(0.42, 0.3, 0.17)], [0.0, 0.55, 1.0], 0.06, 256, 23)
	crate_mat.uv1_triplanar = true
	crate_mat.uv1_scale = Vector3(1.5, 6.0, 1.5)
	crate_mat.roughness = 0.85
	var crates := [
		[Vector3(-5.4, 0, -12.3), 15.0, 1.3],
		[Vector3(-4.2, 0, -12.9), -8.0, 1.2],
		[Vector3(2.9, 0, -2.7), 68.0, 1.05],
		[Vector3(6.8, 0, -9.5), 25.0, 1.3],
	]
	var stack_height := -1.0
	for i in crates.size():
		var c: Array = crates[i]
		var pos: Vector3 = c[0]
		var yaw: float = c[1]
		var s: float = c[2]
		var h := _place_model(CRATE_MODEL, pos, yaw, s, crate_mat)
		if h < 0.0:
			# Model missing: fall back to a simple box crate.
			MK.box(self, Vector3(s * 0.5, s * 0.45, s), pos + Vector3(0, s * 0.225, 0), wood, Vector3(0, yaw, 0))
			MK.box(self, Vector3(s * 0.52, s * 0.06, s * 1.02), pos + Vector3(0, s * 0.35, 0), wood_dark, Vector3(0, yaw, 0))
			h = s * 0.45
		if i == 0:
			stack_height = h
	# One more crate stacked on the first.
	if stack_height > 0.0:
		if _place_model(CRATE_MODEL, Vector3(-5.35, stack_height, -12.25), 40.0, 1.1, crate_mat) < 0.0:
			MK.box(self, Vector3(0.55, 0.5, 1.1), Vector3(-5.35, stack_height + 0.25, -12.25), wood, Vector3(0, 40, 0))

	var barrels := [
		[Vector3(-2.1, 0.45, -9.2), Color(0.25, 0.33, 0.22)],
		[Vector3(-1.45, 0.45, -9.6), Color(0.15, 0.3, 0.55)],
		[Vector3(7.6, 0.45, -10.4), Color(0.6, 0.15, 0.1)],
	]
	for b in barrels:
		var pos: Vector3 = b[0]
		var col: Color = b[1]
		MK.cylinder(self, 0.3, 0.3, 0.9, pos, MK.mat(col, 0.55, 0.4), Vector3.ZERO, Vector3.ONE, 16)
		MK.torus(self, 0.29, 0.32, pos + Vector3(0, 0.2, 0), MK.mat(col.darkened(0.3), 0.5, 0.5))

	# Scattered rocks.
	var rock := MK.mat(Color(0.48, 0.47, 0.45), 0.95)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 22:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(4.5, 30.0)
		var pos := Vector3(cos(ang) * dist, 0.0, -absf(sin(ang)) * dist - 2.0)
		var s := rng.randf_range(0.25, 0.9)
		MK.sphere(self, s, pos, rock, Vector3(1.3, 0.6, 1.0), Vector3(0, rng.randf() * 360.0, 0), 7)


## Instances an imported model (FBX/GLB), scales it so its longest side is `longest` metres,
## sits it on the ground at `pos` and returns its final height (or -1 if it could not be loaded).
func _place_model(path: String, pos: Vector3, yaw_deg: float, longest: float, mat_override: Material) -> float:
	if not ResourceLoader.exists(path):
		return -1.0
	var scene := load(path) as PackedScene
	if scene == null:
		return -1.0
	var inst := scene.instantiate() as Node3D
	if inst == null:
		return -1.0
	var holder := Node3D.new()
	holder.name = path.get_file().get_basename()
	add_child(holder)
	holder.position = pos
	holder.rotation_degrees = Vector3(0, yaw_deg, 0)
	holder.add_child(inst)
	var box := AABB()
	var found := false
	var to_holder := holder.global_transform.affine_inverse()
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var part: AABB = to_holder * mi.global_transform * mi.get_aabb()
		box = box.merge(part) if found else part
		found = true
		if mat_override:
			mi.material_override = mat_override
	if not found or box.get_longest_axis_size() <= 0.0:
		holder.queue_free()
		return -1.0
	var k := longest / box.get_longest_axis_size()
	var centre := box.get_center()
	var offset := -Vector3(centre.x, box.position.y, centre.z) * k
	inst.transform = Transform3D(Basis.from_scale(Vector3(k, k, k)), offset) * inst.transform
	return box.size.y * k


# --- Trees ------------------------------------------------------------------------

func _build_trees() -> void:
	var points: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var clusters := [
		[Vector3(-24, 0, -40), 9.0, 18],
		[Vector3(-30, 0, -24), 7.0, 12],
		[Vector3(-4, 0, -44), 8.0, 10],
		[Vector3(15, 0, -36), 6.0, 10],
		[Vector3(24, 0, -46), 10.0, 16],
		[Vector3(30, 0, -22), 7.0, 10],
	]
	for cl in clusters:
		var center: Vector3 = cl[0]
		var radius: float = cl[1]
		var count: int = cl[2]
		for i in count:
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * radius
			points.append(center + Vector3(cos(a) * r, 0, sin(a) * r))
	# Distant tree line + trees on the lower slopes.
	for i in 120:
		var x := rng.randf_range(-160.0, 160.0)
		var z := rng.randf_range(-70.0, -45.0)
		points.append(Vector3(x, 0, z))
	for i in 220:
		var x := rng.randf_range(-300.0, 300.0)
		var z := rng.randf_range(-170.0, -85.0)
		var y := _height(x, z)
		if y > 0.5 and y < 16.0:
			points.append(Vector3(x, y - 0.3, z))

	# One combined foliage mesh (three stacked cones) + trunk mesh.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tiers := [[1.7, 2.6, 2.2], [1.3, 2.2, 3.5], [0.9, 1.9, 4.7]]
	for tier in tiers:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = tier[0]
		cone.height = tier[1]
		cone.radial_segments = 8
		cone.rings = 1
		var ty: float = tier[2]
		st.append_from(cone, 0, Transform3D(Basis.IDENTITY, Vector3(0, ty, 0)))
	var foliage_mesh := st.commit()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.14
	trunk_mesh.bottom_radius = 0.22
	trunk_mesh.height = 2.4
	trunk_mesh.radial_segments = 6

	var foliage_mm := MultiMesh.new()
	foliage_mm.transform_format = MultiMesh.TRANSFORM_3D
	foliage_mm.use_colors = true
	foliage_mm.mesh = foliage_mesh
	foliage_mm.instance_count = points.size()
	var trunk_mm := MultiMesh.new()
	trunk_mm.transform_format = MultiMesh.TRANSFORM_3D
	trunk_mm.mesh = trunk_mesh
	trunk_mm.instance_count = points.size()
	for i in points.size():
		var s := rng.randf_range(0.7, 1.25)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.25), s))
		var p: Vector3 = points[i]
		foliage_mm.set_instance_transform(i, Transform3D(b, p))
		trunk_mm.set_instance_transform(i, Transform3D(b, p + Vector3(0, 1.2 * s, 0)))
		var g := rng.randf_range(0.8, 1.15)
		foliage_mm.set_instance_color(i, Color(0.17 * g, 0.31 * g, 0.16 * g))
	var foliage_mat := StandardMaterial3D.new()
	foliage_mat.vertex_color_use_as_albedo = true
	foliage_mat.vertex_color_is_srgb = true
	foliage_mat.roughness = 0.9
	var fmi := MultiMeshInstance3D.new()
	fmi.multimesh = foliage_mm
	fmi.material_override = foliage_mat
	add_child(fmi)
	var tmi := MultiMeshInstance3D.new()
	tmi.multimesh = trunk_mm
	tmi.material_override = MK.mat(Color(0.3, 0.21, 0.13), 0.9)
	add_child(tmi)


# --- Grass ------------------------------------------------------------------------

## One grass tuft: several thin, curved blades fanned around the origin.
func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for blade in 6:
		var yaw := rng.randf() * TAU
		var lean := rng.randf_range(0.05, 0.3)
		var height := rng.randf_range(0.65, 1.0)
		var width := rng.randf_range(0.014, 0.022)
		var root := Vector3(rng.randf_range(-0.05, 0.05), 0.0, rng.randf_range(-0.05, 0.05))
		var b := Basis(Vector3.UP, yaw)
		var hs := [0.0, 0.5, 1.0]
		var ws := [width, width * 0.7, 0.0]
		for i in 2:
			var h0: float = hs[i]
			var h1: float = hs[i + 1]
			var w0: float = ws[i]
			var w1: float = ws[i + 1]
			var a := root + b * Vector3(-w0, h0 * height, h0 * h0 * lean)
			var c := root + b * Vector3(w0, h0 * height, h0 * h0 * lean)
			var d := root + b * Vector3(-w1, h1 * height, h1 * h1 * lean)
			var e := root + b * Vector3(w1, h1 * height, h1 * h1 * lean)
			_blade_vertex(st, a, h0)
			_blade_vertex(st, d, h1)
			_blade_vertex(st, c, h0)
			if w1 > 0.0:
				_blade_vertex(st, c, h0)
				_blade_vertex(st, d, h1)
				_blade_vertex(st, e, h1)
	return st.commit()


func _blade_vertex(st: SurfaceTool, v: Vector3, h: float) -> void:
	st.set_normal(Vector3(0, 1, 0.25).normalized())
	st.set_uv(Vector2(0.5, h))
	st.add_vertex(v)


func _build_grass() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var clump := FastNoiseLite.new()
	clump.frequency = 0.25
	clump.seed = 3
	var outpost := Vector3(-11.0, 0, -30.0)
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var target := 14000
	var tries := 0
	while xforms.size() < target and tries < target * 4:
		tries += 1
		var x := rng.randf_range(-16.0, 16.0)
		var z := rng.randf_range(-26.0, 1.2)
		var r := Vector2(x, z).length()
		if r < DIRT_RADIUS * 0.8:
			continue
		if r < DIRT_RADIUS * 1.15 and rng.randf() < 0.6:
			continue
		if Vector2(x - outpost.x, z - outpost.z).length() < 7.5:
			continue
		if clump.get_noise_2d(x, z) < -0.25 and rng.randf() < 0.7:
			continue
		var h := rng.randf_range(0.2, 0.42)
		var w := rng.randf_range(0.9, 1.3)
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		xforms.append(Transform3D(b.scaled(Vector3(w, h, w)), Vector3(x, 0.0, z)))
		var g := rng.randf_range(0.8, 1.2)
		colors.append(Color(g * rng.randf_range(0.9, 1.1), g, g * 0.9))

	_grass_mm = MultiMesh.new()
	_grass_mm.transform_format = MultiMesh.TRANSFORM_3D
	_grass_mm.use_colors = true
	_grass_mm.mesh = _tuft_mesh()
	_grass_mm.instance_count = xforms.size()
	for i in xforms.size():
		_grass_mm.set_instance_transform(i, xforms[i])
		_grass_mm.set_instance_color(i, colors[i])
	_grass_total = xforms.size()
	var sh := Shader.new()
	sh.code = GRASS_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Grass"
	mmi.multimesh = _grass_mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


# --- Hero -----------------------------------------------------------------------

func _build_character() -> void:
	character_pivot = Node3D.new()
	character_pivot.name = "CharacterPivot"
	add_child(character_pivot)
	character = CharacterModel.new()
	character.name = "Hero"
	character_pivot.add_child(character)
