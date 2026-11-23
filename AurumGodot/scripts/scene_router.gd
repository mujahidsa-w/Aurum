extends CanvasLayer
## Autoload "SceneRouter": every move between places (sign-in -> training -> lobby -> match
## -> lobby) goes through here and shows a full-screen loading screen with real progress.
## The scene is loaded on a background thread; a scene that needs more time to build itself
## (the battleground generates the island) keeps the screen up with report() and finish().
## Panels inside the lobby never use it.

const GOLD := Color(1.0, 0.78, 0.1)
const TIPS := [
	"Prone is the hardest posture to spot and hit - and the steadiest for long shots.",
	"Sprinting is loud. Walk (ALT / light joystick) when enemies are close.",
	"Jumping from a sprint carries your momentum further.",
	"Bullets drop and take time to arrive: lead moving targets at long range.",
	"Headshots deal more than double damage.",
	"Crouching reduces recoil and makes you a smaller target.",
	"The blue zone shrinks over time - plan your rotation early.",
	"Pick up spare ammo for the calibre your weapon uses.",
	"Add friends by their player ID from the Friends panel in the lobby.",
]

## Resources loaded by the startup screen, kept alive so later scenes open instantly.
var preloaded := {}

var _root: Control
var _title: Label
var _subtitle: Label
var _tip: Label
var _status: Label
var _percent: Label
var _bar: ProgressBar
var _spinner: Control

var _path := ""
var _loading := false
var _waiting_scene := false
var _shown_at := 0
var _shown := 0.0
var _target := 0.0
var _finishing := false


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false


func is_loading() -> bool:
	return _loading


## Loads `path` behind a loading screen. With `wait_for_scene` the screen stays until the
## new scene calls finish() (it can report its own progress with report()).
func go(path: String, title: String = "", subtitle: String = "", wait_for_scene: bool = false) -> void:
	if _loading:
		return
	_path = path
	_loading = true
	_waiting_scene = wait_for_scene
	_finishing = false
	_shown = 0.0
	_target = 0.0
	_shown_at = Time.get_ticks_msec()
	_title.text = title
	_subtitle.text = subtitle
	_tip.text = "TIP  ·  " + str(TIPS[randi() % TIPS.size()])
	_status.text = "Loading"
	_bar.value = 0.0
	_root.visible = true
	_root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.25)
	tw.tween_callback(_start_load)


func _start_load() -> void:
	var err := ResourceLoader.load_threaded_request(_path, "PackedScene", true)
	if err != OK:
		# Fall back to a normal load.
		get_tree().change_scene_to_file(_path)
		_after_change()


## Progress reported by the scene that is building itself (0..1).
func report(progress: float, text: String) -> void:
	if not _loading:
		return
	_target = maxf(_target, 0.55 + clampf(progress, 0.0, 1.0) * 0.45)
	_status.text = text


func finish() -> void:
	if not _loading or _finishing:
		return
	_finishing = true
	_target = 1.0
	_status.text = "Ready"
	# Keep the screen for a moment so it never flashes.
	var wait := maxf(0.0, 0.9 - (Time.get_ticks_msec() - _shown_at) / 1000.0)
	var tw := create_tween()
	tw.tween_interval(wait + 0.25)
	tw.tween_property(_root, "modulate:a", 0.0, 0.45)
	tw.tween_callback(_hide)


func _hide() -> void:
	_root.visible = false
	_loading = false
	_finishing = false


func _process(delta: float) -> void:
	if not _loading:
		return
	_spinner.rotation += delta * 4.0
	if _path != "" and not _finishing:
		var progress := []
		var status := ResourceLoader.load_threaded_get_status(_path, progress)
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				if progress.size() > 0:
					_target = maxf(_target, float(progress[0]) * 0.55)
			ResourceLoader.THREAD_LOAD_LOADED:
				var scene := ResourceLoader.load_threaded_get(_path) as PackedScene
				_path = ""
				_target = 0.55
				if scene:
					get_tree().change_scene_to_packed(scene)
				_after_change.call_deferred()
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				var p := _path
				_path = ""
				get_tree().change_scene_to_file(p)
				_after_change.call_deferred()
	_shown = move_toward(_shown, _target, delta * 1.6)
	_bar.value = _shown
	_percent.text = "%d%%" % int(round(_shown * 100.0))


func _after_change() -> void:
	if not _waiting_scene:
		await get_tree().process_frame
		await get_tree().process_frame
		finish()


# --- UI ----------------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := TextureRect.new()
	bg.texture = background_texture()
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	_root.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var brand := _label("AURUM", 46, GOLD, 22)
	_root.add_child(brand)
	brand.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	brand.position = Vector2(60, 44)
	_title = _label("", 110, Color(1, 1, 1), 14)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_title)
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_title.anchor_left = 0.0
	_title.anchor_right = 1.0
	_title.offset_left = 0
	_title.offset_right = 0
	_title.offset_top = -120
	_title.offset_bottom = 20
	_subtitle = _label("", 30, Color(1, 1, 1, 0.65), 4)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_subtitle)
	_subtitle.anchor_left = 0.0
	_subtitle.anchor_right = 1.0
	_subtitle.anchor_top = 0.5
	_subtitle.anchor_bottom = 0.5
	_subtitle.offset_top = 30
	_subtitle.offset_bottom = 80
	_tip = _label("", 26, Color(1, 1, 1, 0.75))
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_tip)
	_tip.anchor_left = 0.1
	_tip.anchor_right = 0.9
	_tip.anchor_top = 1.0
	_tip.anchor_bottom = 1.0
	_tip.offset_top = -230
	_tip.offset_bottom = -160
	_bar = make_bar()
	_root.add_child(_bar)
	_bar.anchor_left = 0.06
	_bar.anchor_right = 0.94
	_bar.anchor_top = 1.0
	_bar.anchor_bottom = 1.0
	_bar.offset_top = -92
	_bar.offset_bottom = -84
	_status = _label("", 26, Color(1, 1, 1, 0.8))
	_root.add_child(_status)
	_status.anchor_left = 0.06
	_status.anchor_right = 0.6
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.offset_top = -140
	_status.offset_bottom = -100
	_percent = _label("0%", 30, GOLD)
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_percent)
	_percent.anchor_left = 0.6
	_percent.anchor_right = 0.94
	_percent.anchor_top = 1.0
	_percent.anchor_bottom = 1.0
	_percent.offset_top = -142
	_percent.offset_bottom = -100
	_spinner = Spinner.new()
	_root.add_child(_spinner)
	_spinner.anchor_left = 1.0
	_spinner.anchor_right = 1.0
	_spinner.offset_left = -110
	_spinner.offset_right = -60
	_spinner.offset_top = 50
	_spinner.offset_bottom = 100
	_spinner.pivot_offset = Vector2(25, 25)


## Thin gold progress bar used by every loading screen.
static func make_bar() -> ProgressBar:
	var pb := ProgressBar.new()
	pb.max_value = 1.0
	pb.step = 0.0001
	pb.show_percentage = false
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color(1, 1, 1, 0.12)
	bgs.set_corner_radius_all(4)
	var fg := StyleBoxFlat.new()
	fg.bg_color = GOLD
	fg.set_corner_radius_all(4)
	fg.shadow_color = Color(1.0, 0.7, 0.1, 0.55)
	fg.shadow_size = 8
	pb.add_theme_stylebox_override("background", bgs)
	pb.add_theme_stylebox_override("fill", fg)
	return pb


## Dark radial backdrop shared by the loading screens.
static func background_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.09, 0.11, 0.15))
	g.set_color(1, Color(0.01, 0.012, 0.02))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.42)
	tex.fill_to = Vector2(1.15, 1.1)
	tex.width = 512
	tex.height = 288
	return tex


## Label with optional letter spacing.
static func _label(text: String, size: int, color: Color, spacing: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if spacing != 0:
		var fv := FontVariation.new()
		fv.base_font = ThemeDB.fallback_font
		fv.spacing_glyph = spacing
		l.add_theme_font_override("font", fv)
	return l


class Spinner extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.45
		draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.12), 4.0, true)
		draw_arc(c, r, 0.0, TAU * 0.28, 24, Color(1.0, 0.78, 0.1), 4.0, true)
