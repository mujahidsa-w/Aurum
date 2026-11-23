extends Control
## Studio intro shown at launch: animated "Midnight Sand Studios" emblem (crescent moon over
## dunes), a light sweep across the name and the developer credit. Tap / click / any key to
## skip once the logo is in. Then the startup loader takes over.

const Sfx := preload("res://scripts/game/sfx.gd")
const Router := preload("res://scripts/scene_router.gd")

const STUDIO := "MIDNIGHT SAND"
const STUDIO_SUB := "STUDIOS"
const DEVELOPER := "Developed by Mujahid"
const NEXT_SCENE := "res://scenes/startup.tscn"
const BG := Color(0.02, 0.025, 0.035)
const GOLD := Color(1.0, 0.78, 0.22)

var _emblem: Emblem
var _name: Label
var _sub: Label
var _dev: Label
var _line: ColorRect
var _sweep: ShaderMaterial
var _t := 0.0
var _leaving := false
var _audio: AudioStreamPlayer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_emblem = Emblem.new()
	_emblem.custom_minimum_size = Vector2(0, 300)
	_emblem.bg = BG
	col.add_child(_emblem)
	_name = Router._label(STUDIO, 92, GOLD, 18)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_name)
	_sweep = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform float sweep = -1.0;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV) * COLOR;\n\tfloat d = abs((UV.x - UV.y * 0.25) - sweep);\n\tc.rgb += vec3(1.0, 0.95, 0.8) * smoothstep(0.09, 0.0, d) * 0.9;\n\tCOLOR = c;\n}\n"
	_sweep.shader = sh
	_name.material = _sweep
	_sub = Router._label(STUDIO_SUB, 34, Color(1, 1, 1, 0.85), 30)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_sub)
	var line_holder := CenterContainer.new()
	line_holder.custom_minimum_size = Vector2(0, 40)
	col.add_child(line_holder)
	_line = ColorRect.new()
	_line.color = Color(GOLD, 0.6)
	_line.custom_minimum_size = Vector2(0, 2)
	line_holder.add_child(_line)
	_dev = Router._label(DEVELOPER, 32, Color(1, 1, 1, 0.75), 3)
	_dev.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_dev)
	for c in [_name, _sub, _dev]:
		var item := c as CanvasItem
		item.modulate.a = 0.0
	_audio = AudioStreamPlayer.new()
	_audio.stream = Sfx.intro_chime()
	_audio.volume_db = -4.0
	add_child(_audio)
	_audio.play.call_deferred()
	# Warm up the next screen while the intro plays.
	ResourceLoader.load_threaded_request(NEXT_SCENE)


func _process(delta: float) -> void:
	_t += delta
	_emblem.progress = clampf(_t / 1.6, 0.0, 1.0)
	_emblem.glow = clampf((_t - 1.4) / 0.6, 0.0, 1.0)
	_emblem.queue_redraw()
	_name.modulate.a = clampf((_t - 1.0) / 0.7, 0.0, 1.0)
	_sub.modulate.a = clampf((_t - 1.5) / 0.6, 0.0, 1.0)
	_line.custom_minimum_size.x = lerpf(0.0, 520.0, ease(clampf((_t - 1.7) / 0.8, 0.0, 1.0), 0.3))
	_dev.modulate.a = clampf((_t - 2.2) / 0.7, 0.0, 1.0)
	_sweep.set_shader_parameter("sweep", lerpf(-0.3, 1.4, clampf((_t - 2.0) / 1.1, 0.0, 1.0)))
	if _t > 4.9:
		_leave()


func _input(event: InputEvent) -> void:
	if _t < 1.6:
		return
	if (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) \
			or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
			or (event is InputEventKey and (event as InputEventKey).pressed):
		_leave()


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	tw.tween_callback(_open_next)


func _open_next() -> void:
	var scene: PackedScene = null
	if ResourceLoader.load_threaded_get_status(NEXT_SCENE) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		scene = ResourceLoader.load_threaded_get(NEXT_SCENE) as PackedScene
	if scene:
		get_tree().change_scene_to_packed(scene)
	else:
		get_tree().change_scene_to_file(NEXT_SCENE)


## The emblem: a crescent moon drawn in as an arc, a small star and two dune ridges.
class Emblem extends Control:
	var progress := 0.0
	var glow := 0.0
	var bg := Color.BLACK

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.5)
		var r := minf(size.y * 0.36, 110.0)
		var gold := Color(1.0, 0.78, 0.22)
		var p := ease(progress, 0.4)
		# Soft halo.
		if glow > 0.0:
			for i in 6:
				draw_circle(c + Vector2(0, -r * 0.1), r * (1.25 + i * 0.12), Color(1.0, 0.75, 0.2, 0.025 * glow))
		# Crescent: a filled disc cut by a background-coloured disc, revealed by the arc.
		var moon := c + Vector2(-r * 0.15, -r * 0.18)
		if p > 0.0:
			draw_circle(moon, r * 0.62, Color(gold, p))
			draw_circle(moon + Vector2(r * 0.26, -r * 0.14), r * 0.54, bg)
			draw_arc(moon, r * 0.62, PI * 0.35, PI * 0.35 + TAU * 0.72 * p, 64, gold, 3.0, true)
		# Star.
		if p > 0.6:
			var a := (p - 0.6) / 0.4
			var s := moon + Vector2(r * 0.62, -r * 0.42)
			var k := r * 0.11 * a
			draw_colored_polygon(PackedVector2Array([s + Vector2(0, -k * 1.6), s + Vector2(k * 0.35, -k * 0.35), s + Vector2(k * 1.6, 0), s + Vector2(k * 0.35, k * 0.35), s + Vector2(0, k * 1.6), s + Vector2(-k * 0.35, k * 0.35), s + Vector2(-k * 1.6, 0), s + Vector2(-k * 0.35, -k * 0.35)]), Color(1, 0.93, 0.7, a))
		# Dunes: two ridges drawn left to right.
		_dune(c + Vector2(0, r * 0.62), r * 2.4, r * 0.34, Color(gold, 0.55), p)
		_dune(c + Vector2(r * 0.4, r * 0.8), r * 2.0, r * 0.26, Color(gold, 0.9), clampf(p * 1.3 - 0.3, 0.0, 1.0))

	func _dune(base: Vector2, width: float, height: float, color: Color, amount: float) -> void:
		if amount <= 0.0:
			return
		var pts := PackedVector2Array()
		var n := 40
		var x0 := base.x - width * 0.5
		var last := int(n * amount)
		for i in last + 1:
			var t := float(i) / n
			var x := x0 + width * t
			var y := base.y - sin(t * PI) * height * (0.75 + 0.25 * sin(t * PI * 2.0 + 0.6))
			pts.append(Vector2(x, y))
		if pts.size() >= 2:
			draw_polyline(pts, color, 4.0, true)
