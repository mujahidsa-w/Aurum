extends Control
## In-match HUD: loading screen, minimap of the real island with the zone, compass, health,
## weapon/ammo, crosshair + hit markers, scope overlay, kill feed, end screen and full
## multi-touch controls on phones (joystick, look area, buttons).

const Icons := preload("res://scripts/ui_icons.gd")
const MapData := preload("res://maps/vis/vis_map.gd")

const GOLD := Color(1.0, 0.78, 0.1)

const EXTRA_ICONS := {
	"target": "<circle cx='32' cy='32' r='16' fill='none' stroke='#FFFFFF' stroke-width='5'/><path d='M32 4 V18 M32 46 V60 M4 32 H18 M46 32 H60' stroke='#FFFFFF' stroke-width='5' stroke-linecap='round'/>",
	"scope": "<circle cx='32' cy='32' r='22' fill='none' stroke='#FFFFFF' stroke-width='5'/><circle cx='32' cy='32' r='4' fill='#FFFFFF'/>",
	"reload": "<path d='M50 22 A20 20 0 1 0 52 38' fill='none' stroke='#FFFFFF' stroke-width='6' stroke-linecap='round'/><path d='M40 18 H54 V4' fill='none' stroke='#FFFFFF' stroke-width='6' stroke-linecap='round' stroke-linejoin='round'/>",
	"jump": "<path d='M14 40 L32 20 L50 40' fill='none' stroke='#FFFFFF' stroke-width='7' stroke-linecap='round' stroke-linejoin='round'/>",
	"crouch": "<circle cx='36' cy='12' r='6' fill='#FFFFFF'/><path d='M34 20 L26 34 L38 40 L36 56 M26 34 L18 46 M30 26 L44 30' fill='none' stroke='#FFFFFF' stroke-width='6' stroke-linecap='round' stroke-linejoin='round'/>",
	"prone": "<circle cx='50' cy='34' r='6' fill='#FFFFFF'/><path d='M8 46 H42 M20 46 L30 38 H44 M44 38 L54 44' fill='none' stroke='#FFFFFF' stroke-width='6' stroke-linecap='round' stroke-linejoin='round'/>",
	"grab": "<path d='M18 34 V20 M26 32 V14 M34 32 V14 M42 34 V20 M16 34 C16 50 24 56 32 56 C42 56 48 48 48 36 V28' fill='none' stroke='#FFFFFF' stroke-width='5' stroke-linecap='round'/>",
	"swap": "<path d='M12 22 H50 L40 12 M52 42 H14 L24 52' fill='none' stroke='#FFFFFF' stroke-width='6' stroke-linecap='round' stroke-linejoin='round'/>",
	"medkit": "<rect x='10' y='16' width='44' height='34' rx='5' fill='none' stroke='#FFFFFF' stroke-width='5'/><path d='M32 22 V44 M21 33 H43' stroke='#FF5555' stroke-width='7' stroke-linecap='round'/>",
	"mode": "<circle cx='20' cy='32' r='6' fill='#FFFFFF'/><circle cx='32' cy='32' r='6' fill='#FFFFFF'/><circle cx='44' cy='32' r='6' fill='#FFFFFF' opacity='0.5'/>",
	"sprint": "<path d='M14 46 L28 32 L20 24 M34 16 L44 26 L54 22 M28 32 L38 40 L36 54' fill='none' stroke='#FFFFFF' stroke-width='6' stroke-linecap='round' stroke-linejoin='round'/><circle cx='40' cy='10' r='5' fill='#FFFFFF'/>",
}

const STANCE_ICONS := {
	"stand": "<circle cx='32' cy='9' r='6' fill='#FFFFFF'/><path d='M32 17 V38 M32 38 L25 58 M32 38 L39 58 M32 22 L22 34 M32 22 L42 30' fill='none' stroke='#FFFFFF' stroke-width='5' stroke-linecap='round' stroke-linejoin='round'/>",
	"crouch": "<circle cx='34' cy='20' r='6' fill='#FFFFFF'/><path d='M32 28 L28 42 L40 46 L38 58 M28 42 L20 58 M31 31 L44 36' fill='none' stroke='#FFFFFF' stroke-width='5' stroke-linecap='round' stroke-linejoin='round'/>",
	"prone": "<circle cx='52' cy='42' r='6' fill='#FFFFFF'/><path d='M6 52 H44 M18 52 L28 46 H46 M46 46 L56 50' fill='none' stroke='#FFFFFF' stroke-width='5' stroke-linecap='round' stroke-linejoin='round'/>",
}

var player: Node
var battle: Node
## Training hides the minimap and shows an objective banner.
var show_map := true
var _objective: PanelContainer
var _objective_title: Label
var _objective_text: Label

var move_vec := Vector2.ZERO
var fire_held := false
var sprint_lock := false

var _touch := false
var _look_acc := Vector2.ZERO
var _joy_finger := -1
var _look_finger := -1
var _joy_origin := Vector2.ZERO
var _buttons: Array[TouchScreenButton] = []
var _button_radius := {}

var _font: Font
var _loading: Control
var _loading_bar: ProgressBar
var _loading_label: Label
var _top_left: Label
var _compass: Label
var _zone_label: Label
var _health_bar: ProgressBar
var _stance_icon: TextureRect
var _stance_textures := {}
var _health_label: Label
var _med_label: Label
var _weapon_label: Label
var _ammo_label: Label
var _mode_label: Label
var _slot2_label: Label
var _prompt: Label
var _chute_label: Label
var _feed: VBoxContainer
var _damage: ColorRect
var _scope: ColorRect
var _map: Control
var _cross: Control
var _joy: Control
var _menu: Control
var _end: Control
var _hint: Label


class MapView extends Control:
	var hud: Node
	var tex: Texture2D

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r.grow(3), Color(0, 0, 0, 0.55))
		if tex:
			draw_texture_rect(tex, r, false)
		var b: Node = hud.get("battle")
		var p: Node = hud.get("player")
		if b == null or p == null:
			return
		var world: Variant = b.get("world")
		var zone: Variant = b.get("zone")
		if world == null:
			return
		var origin: Vector2 = world.get("origin")
		var wsize: Vector2 = world.call("size")
		var to_map := func(wx: float, wz: float) -> Vector2:
			return Vector2((wx - origin.x) / wsize.x * size.x, (wz - origin.y) / wsize.y * size.y)
		if zone != null:
			var c: Vector2 = zone.get("center")
			var nc: Vector2 = zone.get("next_center")
			var k := size.x / wsize.x
			draw_arc(to_map.call(c.x, c.y), float(zone.get("radius")) * k, 0.0, TAU, 72, Color(0.3, 0.6, 1.0), 2.0)
			draw_arc(to_map.call(nc.x, nc.y), float(zone.get("next_radius")) * k, 0.0, TAU, 72, Color(1, 1, 1, 0.9), 1.5)
		var pp: Vector3 = (p as Node3D).global_position
		var at: Vector2 = to_map.call(pp.x, pp.z)
		var heading := deg_to_rad(float(p.call("heading_degrees")))
		var pts := PackedVector2Array([Vector2(0, -9), Vector2(6, 7), Vector2(0, 3), Vector2(-6, 7)])
		for i in pts.size():
			pts[i] = at + pts[i].rotated(heading)
		draw_colored_polygon(pts, GOLD)


class Crosshair extends Control:
	var gap := 8.0
	var hit_t := 0.0
	var hit_color := Color.WHITE
	var visible_lines := true

	func _draw() -> void:
		var c := size * 0.5
		if visible_lines:
			var col := Color(1, 1, 1, 0.9)
			for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(c + d * gap, c + d * (gap + 10.0), Color(0, 0, 0, 0.5), 4.0)
				draw_line(c + d * gap, c + d * (gap + 10.0), col, 2.0)
			draw_circle(c, 1.6, col)
		if hit_t > 0.0:
			for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				draw_line(c + d * 7.0, c + d * 15.0, hit_color, 3.0)


class Joystick extends Control:
	var knob := Vector2.ZERO
	var active := false

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, 95.0, Color(0, 0, 0, 0.22))
		draw_arc(c, 95.0, 0.0, TAU, 48, Color(1, 1, 1, 0.45), 3.0)
		draw_circle(c + knob * 70.0, 42.0, Color(1, 1, 1, 0.55 if active else 0.35))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch = DisplayServer.is_touchscreen_available()
	_font = load("res://fonts/BarlowCondensed-SemiBold.ttf") if ResourceLoader.exists("res://fonts/BarlowCondensed-SemiBold.ttf") else ThemeDB.fallback_font
	var th := Theme.new()
	th.default_font = _font
	th.default_font_size = 28
	theme = th
	_build()


func _label(text: String, font_size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _anchor(c: Control, ax: float, ay: float, x: float, y: float, w: float, h: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x + w
	c.offset_bottom = y + h
	add_child(c)


func _bar(color: Color) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.max_value = 100.0
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(3)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	return pb


func _build() -> void:
	_damage = ColorRect.new()
	_damage.color = Color(0.7, 0.0, 0.0, 0.0)
	_damage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_damage)
	_damage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_scope = ColorRect.new()
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform float aspect = 1.777;\nvoid fragment() {\n\tvec2 p = (UV - 0.5) * vec2(aspect, 1.0) * 2.0;\n\tfloat r = length(p);\n\tfloat ring = smoothstep(0.9, 0.93, r);\n\tfloat line = (step(abs(p.x), 0.003) + step(abs(p.y), 0.003)) * step(r, 0.9) * step(0.06, r);\n\tCOLOR = vec4(0.0, 0.0, 0.0, max(ring, line * 0.85));\n}\n"
	var sm := ShaderMaterial.new()
	sm.shader = sh
	_scope.material = sm
	_scope.visible = false
	add_child(_scope)
	_scope.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_cross = Crosshair.new()
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cross)
	_cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_top_left = _label("", 30)
	_anchor(_top_left, 0, 0, 24, 16, 520, 40)
	_zone_label = _label("", 26, Color(0.75, 0.88, 1.0))
	_anchor(_zone_label, 0, 0, 24, 54, 520, 36)

	_compass = _label("N", 34)
	_compass.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(_compass, 0.5, 0, -200, 12, 400, 44)

	var map := MapView.new()
	map.hud = self
	if ResourceLoader.exists(MapData.MINIMAP):
		map.tex = load(MapData.MINIMAP)
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(map, 1, 0, -420, 20, 396, 201)
	_map = map

	_feed = VBoxContainer.new()
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_anchor(_feed, 1, 0, -620, 232, 596, 220)

	_health_bar = _bar(Color(0.92, 0.92, 0.9))
	_anchor(_health_bar, 0.5, 1, -260, -64, 520, 18)
	_health_label = _label("100", 24)
	_anchor(_health_label, 0.5, 1, 270, -74, 80, 34)
	# Posture indicator (standing / crouching / prone) left of the health bar.
	for k in ["stand", "crouch", "prone"]:
		var body: String = STANCE_ICONS[k]
		_stance_textures[k] = Icons.svg_texture(Icons.HEAD + body + Icons.TAIL, 1.0)
	_stance_icon = TextureRect.new()
	_stance_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stance_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_stance_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_stance_icon.modulate = Color(1, 1, 1, 0.85)
	_anchor(_stance_icon, 0.5, 1, -340, -96, 64, 64)
	_med_label = _label("", 24, Color(1.0, 0.6, 0.6))
	_anchor(_med_label, 0.5, 1, -260, -104, 520, 34)

	var wx := -470.0 if not _touch else -260.0
	var wy := -150.0 if not _touch else 20.0
	var way := 1.0 if not _touch else 0.0
	_weapon_label = _label("", 34, GOLD)
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor(_weapon_label, 1, way, wx if not _touch else -680.0, wy if not _touch else 228.0, 440, 44)
	_ammo_label = _label("", 52)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor(_ammo_label, 1, way, wx if not _touch else -680.0, (wy + 40.0) if not _touch else 266.0, 440, 64)
	_mode_label = _label("", 24, Color(1, 1, 1, 0.75))
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor(_mode_label, 1, way, wx if not _touch else -680.0, (wy + 104.0) if not _touch else 330.0, 440, 34)
	_slot2_label = _label("", 22, Color(1, 1, 1, 0.55))
	_slot2_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anchor(_slot2_label, 1, way, wx if not _touch else -680.0, (wy - 30.0) if not _touch else 196.0, 440, 30)

	_objective = PanelContainer.new()
	var osb := StyleBoxFlat.new()
	osb.bg_color = Color(0.03, 0.04, 0.06, 0.82)
	osb.border_color = Color(1.0, 0.78, 0.1, 0.6)
	osb.set_border_width_all(2)
	osb.set_corner_radius_all(10)
	osb.content_margin_left = 26
	osb.content_margin_right = 26
	osb.content_margin_top = 10
	osb.content_margin_bottom = 12
	_objective.add_theme_stylebox_override("panel", osb)
	_objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ovb := VBoxContainer.new()
	ovb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective.add_child(ovb)
	_objective_title = _label("", 34, GOLD)
	_objective_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ovb.add_child(_objective_title)
	_objective_text = _label("", 26)
	_objective_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ovb.add_child(_objective_text)
	_anchor(_objective, 0.5, 0, -430, 70, 860, 110)
	_objective.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_objective.visible = false

	_prompt = _label("", 30)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(_prompt, 0.5, 0.5, -400, 90, 800, 44)
	_chute_label = _label("", 30)
	_chute_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(_chute_label, 0.5, 0.5, -400, -150, 800, 80)

	if not _touch:
		_hint = _label("WASD move  ·  Shift sprint  ·  C crouch  ·  Z prone  ·  Alt walk  ·  Space jump / parachute  ·  RMB aim  ·  R reload  ·  F pick up  ·  Q swap  ·  B fire mode  ·  H heal  ·  Esc menu", 20, Color(1, 1, 1, 0.55))
		_anchor(_hint, 0, 1, 24, -36, 1600, 30)
	else:
		_build_touch()
	# The global loading screen covers the match while it builds; standalone runs get their own.
	if not SceneRouter.is_loading():
		_build_loading()


# --- Touch controls -------------------------------------------------------------------------

func _icon_tex(icon_name: String, px: int) -> Texture2D:
	var body: String = EXTRA_ICONS.get(icon_name, Icons.ICONS.get(icon_name, ""))
	var svg := Icons.HEAD + "<circle cx='32' cy='32' r='30' fill='#000000' fill-opacity='0.38' stroke='#FFFFFF' stroke-opacity='0.7' stroke-width='2'/><g transform='translate(14 14) scale(0.5625)'>" + body + "</g>" + Icons.TAIL
	return Icons.svg_texture(svg, float(px) / 64.0)


func _touch_button(icon_name: String, center: Vector2, radius: float, on_press: Callable, on_release: Callable = Callable()) -> void:
	var b := TouchScreenButton.new()
	b.texture_normal = _icon_tex(icon_name, int(radius * 2.0))
	b.position = center - Vector2(radius, radius)
	var shape := CircleShape2D.new()
	shape.radius = radius
	b.shape = shape
	b.shape_centered = true
	b.pressed.connect(on_press)
	if on_release.is_valid():
		b.released.connect(on_release)
	add_child(b)
	_buttons.append(b)
	_button_radius[b] = radius


func _build_touch() -> void:
	_joy = Joystick.new()
	_joy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(_joy, 0, 1, 90, -330, 220, 220)
	_layout_touch_buttons()
	get_viewport().size_changed.connect(_layout_touch_buttons)


func _layout_touch_buttons() -> void:
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	_button_radius.clear()
	var s := get_viewport_rect().size
	var r := s.x
	var bottom := s.y
	_touch_button("target", Vector2(r - 170, bottom - 210), 88.0, _fire_down, _fire_up)
	_touch_button("target", Vector2(170, bottom - 470), 58.0, _fire_down, _fire_up)
	_touch_button("scope", Vector2(r - 330, bottom - 330), 56.0, _toggle_aim)
	_touch_button("reload", Vector2(r - 120, bottom - 410), 50.0, _call_player.bind("start_reload"))
	_touch_button("jump", Vector2(r - 330, bottom - 130), 52.0, _call_player.bind("jump_or_open_chute"))
	_touch_button("crouch", Vector2(r - 460, bottom - 90), 46.0, _toggle_crouch)
	_touch_button("prone", Vector2(r - 580, bottom - 70), 44.0, _call_player.bind("toggle_prone"))
	_touch_button("grab", Vector2(s.x * 0.5 + 160, s.y * 0.5 + 110), 46.0, _call_player.bind("interact"))
	_touch_button("swap", Vector2(r - 120, bottom - 530), 44.0, _call_player.bind("switch_slot"))
	_touch_button("mode", Vector2(r - 240, bottom - 520), 40.0, _call_player.bind("cycle_fire_mode"))
	_touch_button("medkit", Vector2(s.x * 0.5 + 330, bottom - 90), 44.0, _call_player.bind("start_heal"))
	_touch_button("sprint", Vector2(110, bottom - 590), 44.0, _toggle_sprint)


func _fire_down() -> void:
	fire_held = true


func _fire_up() -> void:
	fire_held = false


func _toggle_aim() -> void:
	if player:
		player.set("aiming", not bool(player.get("aiming")))


func _toggle_crouch() -> void:
	if player and player.has_method("toggle_crouch"):
		player.call("toggle_crouch")


func _toggle_sprint() -> void:
	sprint_lock = not sprint_lock


func _call_player(method: String) -> void:
	if player and bool(player.get("alive")):
		player.call(method)


func _over_button(pos: Vector2) -> bool:
	for b in _buttons:
		var rad: float = _button_radius[b]
		if pos.distance_to(b.position + Vector2(rad, rad)) <= rad:
			return true
	return false


func consume_look() -> Vector2:
	var v := _look_acc
	_look_acc = Vector2.ZERO
	return v


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _touch:
		_toggle_menu()
		return
	if not _touch:
		return
	var st := event as InputEventScreenTouch
	if st:
		if st.pressed:
			if _over_button(st.position):
				return
			if st.position.x < get_viewport_rect().size.x * 0.4 and _joy_finger == -1:
				_joy_finger = st.index
				_joy_origin = st.position
				var jp := _joy as Joystick
				jp.active = true
			elif _look_finger == -1:
				_look_finger = st.index
		else:
			if st.index == _joy_finger:
				_joy_finger = -1
				move_vec = Vector2.ZERO
				var jr := _joy as Joystick
				jr.knob = Vector2.ZERO
				jr.active = false
				_joy.queue_redraw()
			if st.index == _look_finger:
				_look_finger = -1
		return
	var sd := event as InputEventScreenDrag
	if sd:
		if sd.index == _joy_finger:
			move_vec = ((sd.position - _joy_origin) / 80.0).limit_length(1.0)
			var jd := _joy as Joystick
			jd.knob = move_vec
			_joy.queue_redraw()
		elif sd.index == _look_finger:
			_look_acc += sd.relative


# --- Menus ---------------------------------------------------------------------------------

func _panel(title: String, sub: String) -> Control:
	var root := ColorRect.new()
	root.color = Color(0, 0, 0, 0.72)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	root.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var t := _label(title, 96, GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var s := _label(sub, 34)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(s)
	return root


func _menu_button(parent: Control, text: String, action: Callable) -> void:
	var holder := CenterContainer.new()
	parent.get_child(0).add_child(holder)
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(380, 72)
	b.add_theme_font_size_override("font_size", 34)
	var sb := StyleBoxFlat.new()
	sb.bg_color = GOLD
	sb.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08))
	b.add_theme_color_override("font_hover_color", Color(0.08, 0.08, 0.08))
	b.pressed.connect(action)
	holder.add_child(b)


func _toggle_menu() -> void:
	if _end:
		return
	if _menu:
		_menu.queue_free()
		_menu = null
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu = _panel("PAUSED", "The match keeps running")
	_menu_button(_menu, "RESUME", _toggle_menu)
	_menu_button(_menu, "LEAVE MATCH", _leave)


func _leave() -> void:
	if battle:
		battle.call("return_to_lobby")


func show_end(title: String, sub: String, allow_continue: bool = false) -> void:
	if _end:
		return
	if _menu:
		_menu.queue_free()
		_menu = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	fire_held = false
	_end = _panel(title, sub)
	_menu_button(_end, "BACK TO LOBBY", _leave)
	if allow_continue:
		_menu_button(_end, "KEEP PRACTICING", _keep_playing)


func _keep_playing() -> void:
	if _end:
		_end.queue_free()
		_end = null
	if not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Loading ----------------------------------------------------------------------------

func _build_loading() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.06)
	_loading = bg
	_loading.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_loading)
	_loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	_loading.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var t := _label("VIS ISLAND", 90, GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var s := _label("Croatia  ·  real terrain, streets and buildings  ·  43.04°N 16.15°E", 30, Color(1, 1, 1, 0.7))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(s)
	var holder := CenterContainer.new()
	box.add_child(holder)
	_loading_bar = _bar(GOLD)
	_loading_bar.custom_minimum_size = Vector2(700, 14)
	_loading_bar.max_value = 1.0
	_loading_bar.step = 0.001
	holder.add_child(_loading_bar)
	_loading_label = _label("Loading...", 28, Color(1, 1, 1, 0.7))
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_loading_label)
	var attribution := _label("Map data © OpenStreetMap contributors (ODbL)  ·  Elevation: AWS Terrain Tiles / SRTM", 22, Color(1, 1, 1, 0.45))
	attribution.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(attribution)


func set_loading(progress: float, text: String) -> void:
	if _loading == null:
		SceneRouter.report(progress, text)
		return
	_loading_bar.value = progress
	_loading_label.text = text + "..."


func hide_loading() -> void:
	if _loading == null:
		SceneRouter.finish()
		return
	var tw := create_tween()
	tw.tween_property(_loading, "modulate:a", 0.0, 0.6)
	tw.tween_callback(_loading.queue_free)


# --- Live updates -----------------------------------------------------------------------

func set_objective(title: String, text: String) -> void:
	_objective.visible = title != ""
	_objective_title.text = title
	_objective_text.text = text


func add_feed(text: String, color: Color = Color.WHITE) -> void:
	var l := _label(text, 24, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feed.add_child(l)
	if _feed.get_child_count() > 6:
		_feed.get_child(0).queue_free()
	get_tree().create_timer(6.0).timeout.connect(l.queue_free)


func flash_hit(headshot: bool, killed: bool) -> void:
	var c := _cross as Crosshair
	c.hit_t = 0.18
	c.hit_color = Color(1.0, 0.25, 0.2) if killed else (Color(1.0, 0.85, 0.2) if headshot else Color.WHITE)


func flash_damage(amount: float) -> void:
	_damage.color.a = clampf(_damage.color.a + amount / 70.0, 0.0, 0.55)


func _process(delta: float) -> void:
	_damage.color.a = move_toward(_damage.color.a, 0.0, delta * 0.8)
	var c := _cross as Crosshair
	if c.hit_t > 0.0:
		c.hit_t -= delta
	if player == null or battle == null:
		c.queue_redraw()
		return
	var p := player
	var zoom := float(p.call("current_zoom"))
	_scope.visible = zoom >= 3.0
	if _scope.visible:
		var vs := get_viewport_rect().size
		(_scope.material as ShaderMaterial).set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
	c.visible_lines = zoom < 3.0
	c.gap = 6.0 + float(p.call("spread_multiplier")) * 16.0
	c.queue_redraw()
	_map.visible = show_map
	if show_map:
		_map.queue_redraw()
	var st := int(p.get("stance")) if p.get("stance") != null else 0
	_stance_icon.texture = _stance_textures[["stand", "crouch", "prone"][clampi(st, 0, 2)]]
	var hp := float(p.get("health"))
	_health_bar.value = hp
	_health_label.text = str(int(ceil(hp)))
	var fill := _health_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill:
		fill.bg_color = Color(0.92, 0.92, 0.9) if hp > 30.0 else Color(0.95, 0.25, 0.2)
	var med := int(p.get("medkits"))
	var heal_p := float(p.call("healing_progress"))
	_med_label.text = ("Healing...  %d%%" % int(heal_p * 100.0)) if heal_p > 0.0 else ("First aid kits: %d" % med if med > 0 else "")
	_top_left.text = "Alive  %d      Kills  %d" % [int(battle.call("alive_count")), int(p.get("kills"))]
	var zone: Variant = battle.get("zone")
	if zone != null:
		var inside: bool = zone.call("is_inside", (p as Node3D).global_position)
		_zone_label.text = str(zone.call("status_text")) + ("" if inside else "    OUTSIDE THE ZONE!")
		_zone_label.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0) if inside else Color(1.0, 0.45, 0.4))
	var hd := float(p.call("heading_degrees"))
	var dirs := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	_compass.text = "%s  %03d°" % [dirs[int(round(hd / 45.0)) % 8], int(hd)]
	if bool(p.call("has_weapon")):
		var w: Dictionary = p.call("weapon")
		_weapon_label.text = str(w["name"]) + "  ·  " + str(w["ammo"])
		var reloading: bool = p.call("is_reloading")
		_ammo_label.text = "RELOADING" if reloading else "%d / %d" % [int(p.call("rounds_in_mag")), int(p.call("reserve_for_current"))]
		_mode_label.text = str(p.call("fire_mode_name"))
	else:
		_weapon_label.text = "Unarmed"
		_ammo_label.text = ""
		_mode_label.text = "Find a weapon"
	var ws: Array = p.get("weapons")
	var slot := int(p.get("slot"))
	_slot2_label.text = ("Other: " + str(WeaponDBName.name_of(str(ws[1 - slot])))) if ws.size() > 1 else ""
	var near := str(p.call("nearest_pickup_text"))
	_prompt.text = ("" if near == "" else ("[F]  Pick up  " if not _touch else "Pick up  ") + near)
	var state := int(p.get("state"))
	if state != 2:
		var alt := int(float(p.call("altitude")))
		_chute_label.text = "Altitude  %d m\n%s" % [alt, "Press SPACE to open the parachute" if state == 0 and not _touch else ""]
	else:
		_chute_label.text = ""


class WeaponDBName:
	const DB := preload("res://scripts/game/weapon_db.gd")

	static func name_of(id: String) -> String:
		return str(DB.get_weapon(id)["name"])
