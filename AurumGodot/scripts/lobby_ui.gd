extends Control
## Lobby HUD drawn over the 3D scene: player card, squad slots, event banner,
## currencies, pass / deals / events tiles, mode card, START button with matchmaking,
## world chat, bottom navigation and all pop-up panels.
## Layout is authored for a 1920x1080 canvas and anchored to the screen corners,
## so it adapts to wider phones and tablets.

const Icons := preload("res://scripts/ui_icons.gd")
const LobbyWorld := preload("res://scripts/lobby_world.gd")
const CharacterModel := preload("res://scripts/character_model.gd")
const CharacterDB := preload("res://scripts/game/character_db.gd")
const WeaponDB := preload("res://scripts/game/weapon_db.gd")

const BASE := Vector2(1920.0, 1080.0)
const GOLD := Color(1.0, 0.78, 0.1)
const PANEL := Color(0.07, 0.09, 0.13, 0.6)
const PANEL_STRONG := Color(0.06, 0.08, 0.11, 0.8)
const STRIP := Color(0.08, 0.12, 0.21, 0.82)
const TEXT_DIM := Color(1, 1, 1, 0.7)
const WORLD_BLUE := Color(0.4, 0.67, 1.0)
const CLEAR := Color(0, 0, 0, 0)

const BOT_CHAT := [
	["Rania", "anyone wanna play?"],
	["Omar", "need 2 more for squad ranked"],
	["Leo", "hot drop on Solara, who's in?"],
	["Mina", "looking for a duo partner"],
	["Yusuf", "GG last round, that was close"],
	["Kai", "clan recruiting, level 40+"],
	["Sara", "anyone finished the vehicle mission?"],
]

const CRATE_PRIZES := ["Desert Scarf", "Midnight Hoodie", "Gold Coin x50", "Tactical Gloves", "Neon Parachute", "Frost Rifle Charm", "Aviator Shades"]

enum Match { IDLE, SEARCHING, FOUND }

var world: LobbyWorld

var font_medium: Font
var font_bold: Font
var font_heavy: Font

var _gold_label: Label
var _credits_label: Label
var _friends_label: Label
var _friends_body: Control
var _friends_list: VBoxContainer
var _id_label: Label
var _mode_card: Button
var _mode_title: Label
var _mode_sub: Label
var _start_label: Label
var _start_play: TextureRect
var _region_label: Label
var _quality_label: Label
var _clock_label: Label
var _signal_icon: TextureRect
var _chat_msg: Label
var _chat_list: VBoxContainer
var _missions_dot: Control
var _nav_items: Array[Control] = []
var _nav_caret_icon: TextureRect
var _nav_collapsed := false
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween
var _fps_label: Label
var _modal: Control
var _overlay: Control
var _crate_result: Label
var _slot_icons: Array[TextureRect] = []
var _slot_labels: Array[Label] = []
var _slot_buttons: Array[Button] = []

var _portrait_cam: Camera3D
var _portrait_tex: Texture2D
var _portrait_offset := Transform3D.IDENTITY
var _map_vp: SubViewport
var _map_timer := 0.0

var _clock_timer := 0.0
var _chat_timer := 0.0
var _chat_index := 0
var _chat_log: Array[String] = []

var _match_state := Match.IDLE
var _match_elapsed := 0.0
var _match_needed := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font_medium = _load_font("res://fonts/BarlowCondensed-Medium.ttf")
	font_bold = _load_font("res://fonts/BarlowCondensed-SemiBold.ttf")
	font_heavy = _load_font("res://fonts/BarlowCondensed-ExtraBold.ttf")
	var th := Theme.new()
	th.default_font = font_bold
	th.default_font_size = 28
	theme = th

	Online.friends_changed.connect(_on_online_changed)
	Online.requests_changed.connect(_on_online_changed)
	Online.invites_changed.connect(_on_online_changed)
	Online.status_changed.connect(_on_online_changed)
	_make_portrait()
	_build_shading()
	_build_profile()
	_build_squad()
	_build_event_banner()
	_build_find_teammates()
	_build_top_center()
	_build_currency()
	_build_right_panel()
	_build_mode_card()
	_build_start()
	_build_status()
	_build_chat()
	_build_nav()
	_build_fps()
	_build_toast()

	GameState.currency_changed.connect(_refresh_currency)
	GameState.mode_changed.connect(_refresh_mode)
	GameState.quality_changed.connect(_refresh_status)
	GameState.region_changed.connect(_refresh_status)
	GameState.missions_changed.connect(_refresh_missions_dot)
	GameState.squad_changed.connect(_refresh_squad)

	_refresh_currency()
	_refresh_mode()
	_refresh_status()
	_refresh_missions_dot()
	_refresh_squad()
	_update_clock()
	_post_chat("Rania", "anyone wanna play?")
	_chat_index = 1


func _process(delta: float) -> void:
	_update_portrait_camera()

	_map_timer += delta
	if _map_timer >= 1.0 and _map_vp:
		_map_timer = 0.0
		_map_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

	_clock_timer += delta
	if _clock_timer >= 1.0:
		_clock_timer = 0.0
		_update_clock()

	_chat_timer += delta
	if _chat_timer >= 7.0:
		_chat_timer = 0.0
		var line: Array = BOT_CHAT[_chat_index % BOT_CHAT.size()]
		_chat_index += 1
		_post_chat(str(line[0]), str(line[1]))

	if _fps_label.visible:
		_fps_label.text = "FPS %d" % Engine.get_frames_per_second()

	if _match_state == Match.SEARCHING:
		_match_elapsed += delta
		var secs := int(_match_elapsed)
		_mode_sub.text = "Matching...  %02d:%02d" % [secs / 60, secs % 60]
		if _match_elapsed >= _match_needed:
			_on_match_found()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _modal != null:
		_close_modal()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _modal != null:
		_close_modal()


# =============================================================================
# Small UI toolkit
# =============================================================================

func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f := load(path) as Font
		if f:
			return f
	return ThemeDB.fallback_font


## Positions `c` inside the 1920x1080 design canvas, anchored to (ax, ay).
func _place(c: Control, x: float, y: float, w: float, h: float, ax: float = 0.0, ay: float = 0.0) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = x - ax * BASE.x
	c.offset_right = x + w - ax * BASE.x
	c.offset_top = y - ay * BASE.y
	c.offset_bottom = y + h - ay * BASE.y


func _sb(bg: Color, radius: int = 0, border: Color = CLEAR, border_w: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	s.anti_aliasing = true
	return s


func _margins(s: StyleBox, h: float, v: float) -> StyleBox:
	s.content_margin_left = h
	s.content_margin_right = h
	s.content_margin_top = v
	s.content_margin_bottom = v
	return s


func _label(parent: Control, text: String, font_size: int, color: Color = Color.WHITE, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	parent.add_child(l)
	return l


func _outline(l: Label, px: int, color: Color = Color(0, 0, 0, 0.85)) -> void:
	l.add_theme_constant_override("outline_size", px)
	l.add_theme_color_override("font_outline_color", color)


func _icon(parent: Control, icon_name: String, px: int, tint: Color = Color.WHITE) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Icons.icon(icon_name, px * 2)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.custom_minimum_size = Vector2(px, px)
	t.size = Vector2(px, px)
	t.modulate = tint
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t


func _texture_rect(parent: Control, tex: Texture2D, stretch: TextureRect.StretchMode = TextureRect.STRETCH_SCALE) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = stretch
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t


func _fill(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _vgradient(top: Color, bottom: Color, horizontal: bool = false) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bottom)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(1, 0) if horizontal else Vector2(0, 1)
	return t


func _button(parent: Control, normal: StyleBox, hover: StyleBox = null, pressed: StyleBox = null) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var hv := hover if hover else normal
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", pressed if pressed else hv)
	b.add_theme_stylebox_override("hover_pressed", pressed if pressed else hv)
	b.add_theme_stylebox_override("disabled", normal)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	parent.add_child(b)
	b.button_down.connect(_press_anim.bind(b, true))
	b.button_up.connect(_press_anim.bind(b, false))
	return b


## Transparent clickable area that brightens on hover (for art tiles).
func _tile_button(parent: Control) -> Button:
	var b := _button(parent, _sb(CLEAR))
	b.mouse_entered.connect(_hover_tint.bind(b, true))
	b.mouse_exited.connect(_hover_tint.bind(b, false))
	return b


func _press_anim(c: Control, down: bool) -> void:
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE * (0.95 if down else 1.0), 0.08)


func _hover_tint(c: Control, on: bool) -> void:
	c.modulate = Color(1.12, 1.12, 1.12) if on else Color.WHITE


func _icon_button(parent: Control, icon_name: String, x: float, y: float, w: float, h: float, icon_px: int, ax: float, ay: float, bg: Color = CLEAR, radius: int = 4) -> Button:
	var b := _button(parent, _sb(bg, radius), _sb(Color(bg.r, bg.g, bg.b, bg.a + 0.12) if bg.a > 0.0 else Color(1, 1, 1, 0.08), radius))
	_place(b, x, y, w, h, ax, ay)
	var ic := _icon(b, icon_name, icon_px)
	ic.position = Vector2((w - icon_px) * 0.5, (h - icon_px) * 0.5)
	return b


# =============================================================================
# 3D previews (avatar portrait + map thumbnail) rendered from the lobby world
# =============================================================================

func _make_portrait() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(192, 192)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	_portrait_cam = Camera3D.new()
	_portrait_cam.fov = 24.0
	_portrait_cam.near = 0.05
	vp.add_child(_portrait_cam)
	_portrait_cam.current = true
	var head := 1.645
	var front := 0.95
	if world and world.character and world.character.has_method("apply_outfit"):
		head = float(world.character.get("head_height")) + 0.12
		front = -0.95 # realistic models face their local -Z
	_portrait_offset = Transform3D(Basis.IDENTITY, Vector3(0.0, head + 0.04, front)).looking_at(Vector3(0.0, head, 0.0), Vector3.UP)
	_portrait_tex = vp.get_texture()
	_update_portrait_camera()


func _update_portrait_camera() -> void:
	if world and world.character and _portrait_cam and _portrait_cam.is_inside_tree():
		_portrait_cam.global_transform = world.character.global_transform * _portrait_offset


func _make_map_preview() -> Texture2D:
	_map_vp = SubViewport.new()
	_map_vp.size = Vector2i(692, 348)
	_map_vp.msaa_3d = Viewport.MSAA_2X
	_map_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_map_vp)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.far = 1500.0
	cam.attributes = CameraAttributesPractical.new() # no depth-of-field blur on the thumbnail
	_map_vp.add_child(cam)
	cam.position = Vector3(18.0, 24.0, 16.0)
	cam.look_at(Vector3(-3.0, 0.0, -18.0), Vector3.UP)
	cam.current = true
	return _map_vp.get_texture()


# =============================================================================
# Layout
# =============================================================================

func _build_shading() -> void:
	var top := _texture_rect(self, _vgradient(Color(0, 0, 0, 0.42), Color(0, 0, 0, 0)))
	top.anchor_right = 1.0
	top.offset_bottom = 160.0
	var bottom := _texture_rect(self, _vgradient(Color(0, 0, 0, 0), Color(0, 0, 0, 0.55)))
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.anchor_right = 1.0
	bottom.offset_top = -200.0


func _build_profile() -> void:
	var avatar := _button(self, _sb(Color(0.08, 0.08, 0.09), 4, Color(0.86, 0.65, 0.12), 3), _sb(Color(0.12, 0.12, 0.13), 4, GOLD, 3))
	_place(avatar, 12, 10, 94, 94)
	avatar.pressed.connect(_open_profile)
	var portrait := _texture_rect(avatar, _portrait_tex)
	portrait.position = Vector2(4, 4)
	portrait.size = Vector2(86, 86)
	var tier := _label(avatar, "S1", 24, Color.WHITE, font_heavy)
	_outline(tier, 5)
	tier.position = Vector2(66, 62)

	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_theme_constant_override("separation", 8)
	add_child(name_row)
	_place(name_row, 116, 12, 330, 48)
	_label(name_row, GameState.player_name, 40, Color.WHITE, font_bold)
	var crown := _icon(name_row, "crown", 34)
	crown.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var lvl_row := HBoxContainer.new()
	lvl_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lvl_row.add_theme_constant_override("separation", 10)
	add_child(lvl_row)
	_place(lvl_row, 116, 60, 260, 36)
	_label(lvl_row, "Lv. %d" % GameState.level, 29, Color.WHITE, font_medium)
	var bar := _progress(lvl_row, GameState.xp_ratio, 128, 9)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_id_label = _label(self, "ID %s" % Online.player_id if Online.player_id != "" else "", 22, Color(1, 1, 1, 0.6), font_medium)
	_place(_id_label, 116, 94, 260, 26)


func _progress(parent: Control, ratio: float, width: float, height: float = 12.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.step = 0.001
	pb.value = ratio
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(width, height)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pb.add_theme_stylebox_override("background", _sb(Color(1, 1, 1, 0.18), 3))
	pb.add_theme_stylebox_override("fill", _sb(GOLD, 3))
	parent.add_child(pb)
	return pb


func _build_squad() -> void:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _sb(PANEL, 3))
	add_child(panel)
	_place(panel, 12, 110, 262, 102)
	var head := _icon(panel, "person", 20, Color(1, 1, 1, 0.85))
	head.position = Vector2(10, 8)
	_friends_label = _label(panel, "%d/%d" % [Online.friends_online_count(), Online.friends.size()], 25, Color(1, 1, 1, 0.9), font_medium)
	_friends_label.position = Vector2(34, 1)
	for i in 4:
		var slot := _button(panel, _sb(Color(1, 1, 1, 0.07), 3, Color(1, 1, 1, 0.18), 1), _sb(Color(1, 1, 1, 0.16), 3, Color(1, 1, 1, 0.4), 1))
		slot.position = Vector2(10 + i * 62, 38)
		slot.size = Vector2(56, 56)
		var tint := Color(1, 1, 1, 0.85)
		if i == 2:
			tint = Color(0.04, 0.05, 0.07, 0.9)
		var ic := _icon(slot, "plus" if i == 3 else "person", 34 if i < 3 else 30, tint)
		ic.position = Vector2(11, 11) if i < 3 else Vector2(13, 13)
		if i < 2:
			var add_badge := _icon(slot, "plus", 14, Color(1, 1, 1, 0.8))
			add_badge.position = Vector2(38, 38)
		if i < 3:
			var initial := _label(slot, "", 30, GOLD, font_heavy)
			initial.position = Vector2(0, 2)
			initial.size = Vector2(56, 52)
			initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			initial.visible = false
			_slot_icons.append(ic)
			_slot_labels.append(initial)
			_slot_buttons.append(slot)
		slot.pressed.connect(_on_squad_slot.bind(i))


func _build_event_banner() -> void:
	var b := _tile_button(self)
	_place(b, 12, 218, 262, 96)
	b.clip_contents = true
	var art := _texture_rect(b, Icons.svg_texture(Icons.EVENT_ART, 2.0))
	_fill(art)
	var title := _label(b, "GOLDEN GAMES", 32, Color(1.0, 0.86, 0.36), font_heavy)
	_outline(title, 6, Color(0.25, 0.12, 0.0, 0.9))
	title.position = Vector2(10, 52)
	var tag := Panel.new()
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_stylebox_override("panel", _sb(Color(0.9, 0.2, 0.15), 3))
	b.add_child(tag)
	tag.position = Vector2(8, 8)
	tag.size = Vector2(46, 24)
	var tag_l := _label(tag, "NEW", 20, Color.WHITE, font_heavy)
	tag_l.position = Vector2(8, -1)
	b.pressed.connect(_open_events)


func _build_find_teammates() -> void:
	var b := _button(self, _sb(PANEL_STRONG, 3), _sb(Color(0.12, 0.15, 0.2, 0.85), 3))
	_place(b, 12, 322, 262, 56)
	var ic := _icon(b, "flag", 36)
	ic.position = Vector2(12, 10)
	var l := _label(b, "Friends", 31, Color.WHITE, font_bold)
	l.position = Vector2(58, 7)
	b.pressed.connect(_open_find_teammates)


func _build_top_center() -> void:
	var cloud := _icon_button(self, "cloud", 512, 16, 68, 68, 42, 0.5, 0.0, Color(0.06, 0.08, 0.11, 0.65), 34)
	var ring := _sb(Color(0.06, 0.08, 0.11, 0.65), 34, Color(1, 1, 1, 0.3), 2)
	cloud.add_theme_stylebox_override("normal", ring)
	cloud.pressed.connect(_on_cloud)
	var notice := _icon_button(self, "notice", 812, 12, 70, 70, 54, 0.5, 0.0)
	notice.pressed.connect(_open_notices)
	# (The centre of the top bar is intentionally left free - no logo.)
	var bag := _icon_button(self, "bag", 1046, 12, 70, 70, 50, 0.5, 0.0)
	bag.pressed.connect(_open_shop.bind(false))


func _build_currency() -> void:
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 8)
	add_child(hb)
	_place(hb, 1300, 18, 608, 54, 1.0, 0.0)
	var coin := _icon(hb, "coin", 42)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gold_label = _label(hb, "0", 40, Color.WHITE, font_bold)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(18, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(gap)
	var gem := _icon(hb, "gem", 42)
	gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_credits_label = _label(hb, "0", 40, Color.WHITE, font_bold)
	var plus := _button(hb, _sb(CLEAR), _sb(Color(1, 1, 1, 0.1), 4))
	plus.custom_minimum_size = Vector2(50, 50)
	var plus_icon := _icon(plus, "plus", 30)
	plus_icon.position = Vector2(10, 10)
	plus.pressed.connect(_open_shop.bind(false))


func _build_right_panel() -> void:
	var x0 := 1498.0
	var strip := Panel.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_theme_stylebox_override("panel", _sb(STRIP, 2))
	add_child(strip)
	_place(strip, x0, 80, 410, 96, 1.0, 0.0)
	var icons := ["pass", "chest", "cart"]
	var actions := [_open_pass, _open_crate, _open_shop.bind(false)]
	for i in 3:
		var b := _button(strip, _sb(CLEAR), _sb(Color(1, 1, 1, 0.08), 2))
		b.position = Vector2(i * 137, 0)
		b.size = Vector2(136, 96)
		var ic := _icon(b, str(icons[i]), 64)
		ic.position = Vector2(36, 16)
		var cb: Callable = actions[i]
		b.pressed.connect(cb)

	var pass_btn := _tile_button(self)
	_place(pass_btn, x0, 178, 378, 150, 1.0, 0.0)
	pass_btn.clip_contents = true
	var art := _texture_rect(pass_btn, Icons.svg_texture(Icons.PASS_ART, 2.0))
	_fill(art)
	var pl := _label(pass_btn, "Aurum Pass", 42, Color.WHITE, font_bold)
	_outline(pl, 5, Color(0.1, 0.05, 0.2, 0.8))
	pl.position = Vector2(12, 98)
	pass_btn.pressed.connect(_open_pass)
	var chev := _icon_button(self, "chevrons", x0 + 378, 178, 32, 150, 30, 1.0, 0.0, Color(0.08, 0.12, 0.21, 0.9), 0)
	chev.pressed.connect(_open_pass)

	_blue_tile(x0, 332, "sale", "Deals", _open_shop.bind(true))
	_blue_tile(x0 + 208, 332, "gift", "Events", _open_events)


func _blue_tile(x: float, y: float, icon_name: String, title: String, action: Callable) -> void:
	var b := _tile_button(self)
	_place(b, x, y, 202, 94, 1.0, 0.0)
	var bg := _texture_rect(b, _vgradient(Color(0.22, 0.52, 0.95, 0.92), Color(0.08, 0.27, 0.64, 0.92)))
	_fill(bg)
	var ic := _icon(b, icon_name, 50)
	ic.position = Vector2(76, 6)
	var l := _label(b, title, 30, Color.WHITE, font_bold)
	l.position = Vector2(0, 52)
	l.size = Vector2(202, 38)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(action)


func _build_mode_card() -> void:
	_mode_card = _tile_button(self)
	_place(_mode_card, 12, 714, 346, 174, 0.0, 1.0)
	_mode_card.clip_contents = true
	var map := _texture_rect(_mode_card, _make_map_preview())
	_fill(map)
	var shade := _texture_rect(_mode_card, _vgradient(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0)))
	shade.position = Vector2.ZERO
	shade.size = Vector2(346, 70)
	_mode_title = _label(_mode_card, "", 38, Color.WHITE, font_heavy)
	_outline(_mode_title, 7)
	_mode_title.position = Vector2(0, 4)
	_mode_title.size = Vector2(336, 50)
	_mode_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var strip := ColorRect.new()
	strip.color = Color(0, 0, 0, 0.55)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode_card.add_child(strip)
	strip.position = Vector2(0, 124)
	strip.size = Vector2(346, 50)
	var squad := _icon(_mode_card, "squad", 36)
	squad.position = Vector2(12, 131)
	_mode_sub = _label(_mode_card, "", 31, Color.WHITE, font_bold)
	_mode_sub.position = Vector2(56, 127)
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", _sb(CLEAR, 0, Color(1, 1, 1, 0.35), 1))
	_mode_card.add_child(frame)
	_fill(frame)
	_mode_card.pressed.connect(_open_mode_select)


func _build_start() -> void:
	var b := _button(self, _sb(Color(0.98, 0.74, 0.0), 2), _sb(Color(1.0, 0.8, 0.12), 2), _sb(Color(0.9, 0.66, 0.0), 2))
	_place(b, 12, 896, 346, 128, 0.0, 1.0)
	var sheen := _texture_rect(b, _vgradient(Color(1, 1, 1, 0.28), Color(1, 1, 1, 0.0)))
	sheen.position = Vector2.ZERO
	sheen.size = Vector2(346, 70)
	_start_label = _label(b, "START", 116, Color(0.07, 0.07, 0.07), font_heavy)
	_start_label.add_theme_color_override("font_shadow_color", CLEAR)
	_start_label.position = Vector2(0, -6)
	_start_label.size = Vector2(296, 136)
	_start_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_start_play = _icon(b, "play", 34)
	_start_play.position = Vector2(292, 47)
	b.pressed.connect(_on_start_pressed)


func _build_status() -> void:
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 10)
	add_child(hb)
	_place(hb, 16, 1030, 640, 40, 0.0, 1.0)
	var globe := _icon(hb, "globe", 30)
	globe.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_signal_icon = _icon(hb, "signal", 26)
	_signal_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_region_label = _label(hb, "", 28, Color.WHITE, font_bold)
	_label(hb, "|", 26, Color(1, 1, 1, 0.45), font_medium)
	_quality_label = _label(hb, "", 28, Color.WHITE, font_bold)
	_label(hb, "|", 26, Color(1, 1, 1, 0.45), font_medium)
	_clock_label = _label(hb, "", 28, Color.WHITE, font_medium)


func _build_chat() -> void:
	var bar := _button(self, _sb(CLEAR), _sb(Color(1, 1, 1, 0.06), 4))
	_place(bar, 1100, 904, 640, 56, 1.0, 1.0)
	bar.pressed.connect(_open_chat)
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 22)
	bar.add_child(hb)
	hb.position = Vector2(12, 6)
	hb.size = Vector2(616, 44)
	_label(hb, "World", 30, WORLD_BLUE, font_bold)
	_chat_msg = _label(hb, "", 30, Color.WHITE, font_medium)
	_chat_msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_msg.clip_text = true
	_chat_msg.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	var chat_btn := _icon_button(self, "chat", 1752, 902, 62, 62, 44, 1.0, 1.0)
	chat_btn.pressed.connect(_open_chat)
	var emote := _icon_button(self, "smile", 1840, 902, 62, 62, 46, 1.0, 1.0)
	emote.pressed.connect(_on_emote)
	var dl := _icon_button(self, "download", 1826, 812, 82, 82, 52, 1.0, 1.0, Color(0.08, 0.1, 0.14, 0.55), 3)
	dl.pressed.connect(_open_downloads)


func _build_nav() -> void:
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 0)
	add_child(hb)
	_place(hb, 520, 994, 1392, 68, 1.0, 1.0)
	var items := [
		["CLAN", _open_clan],
		["SETTINGS", _open_settings],
		["SEASON", _open_season],
		["WORKSHOP", _open_workshop],
		["MISSIONS", _open_missions],
		["INVENTORY", _open_inventory],
	]
	for i in items.size():
		var entry: Array = items[i]
		var title: String = entry[0]
		var action: Callable = entry[1]
		if i > 0:
			var sep := _label(hb, "|", 30, Color(1, 1, 1, 0.35), font_medium)
			sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_nav_items.append(sep)
		var parent: Control = hb
		if title == "SEASON":
			var season := HBoxContainer.new()
			season.mouse_filter = Control.MOUSE_FILTER_IGNORE
			season.add_theme_constant_override("separation", 0)
			hb.add_child(season)
			_nav_items.append(season)
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(14, 0)
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			season.add_child(spacer)
			var badge := PanelContainer.new()
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var bs := _sb(Color(0, 0, 0, 0.25), 2, Color.WHITE, 2)
			bs.skew = Vector2(0.3, 0.0)
			badge.add_theme_stylebox_override("panel", _margins(bs, 10, 0))
			badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			season.add_child(badge)
			_label(badge, "S1", 28, Color.WHITE, font_heavy)
			parent = season
		var b := _nav_button(parent, title)
		b.pressed.connect(action)
		if parent == hb:
			_nav_items.append(b)
		if title == "MISSIONS":
			var dot := Panel.new()
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dot.add_theme_stylebox_override("panel", _sb(Color(0.92, 0.16, 0.16), 8, Color(1, 1, 1, 0.6), 1))
			b.add_child(dot)
			dot.anchor_left = 1.0
			dot.anchor_right = 1.0
			dot.offset_left = -20.0
			dot.offset_right = -4.0
			dot.offset_top = 4.0
			dot.offset_bottom = 20.0
			_missions_dot = dot
	var caret := _button(hb, _sb(CLEAR), _sb(Color(1, 1, 1, 0.08), 4))
	caret.custom_minimum_size = Vector2(70, 68)
	_nav_caret_icon = _icon(caret, "caret_up", 34)
	_nav_caret_icon.position = Vector2(18, 17)
	caret.pressed.connect(_toggle_nav)


func _nav_button(parent: Control, title: String) -> Button:
	var b := _button(parent, _margins(_sb(CLEAR), 20, 4), _margins(_sb(Color(1, 1, 1, 0.07), 4), 20, 4))
	b.text = title
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", 36)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_hover_pressed_color", GOLD)
	b.add_theme_constant_override("outline_size", 6)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	return b


func _toggle_nav() -> void:
	_nav_collapsed = not _nav_collapsed
	for c in _nav_items:
		c.visible = not _nav_collapsed
	_nav_caret_icon.flip_v = _nav_collapsed


func _build_fps() -> void:
	_fps_label = _label(self, "", 24, Color(0.6, 1.0, 0.6), font_medium)
	_place(_fps_label, 900, 92, 120, 30, 0.5, 0.0)
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fps_label.visible = GameState.show_fps


func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_theme_stylebox_override("panel", _margins(_sb(Color(0.05, 0.06, 0.08, 0.9), 8, Color(1.0, 0.78, 0.1, 0.5), 1), 28, 10))
	add_child(_toast)
	_place(_toast, 760, 132, 400, 56, 0.5, 0.0)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_label = _label(_toast, "", 30, Color.WHITE, font_bold)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0


# =============================================================================
# Refresh helpers
# =============================================================================

func _refresh_currency() -> void:
	_gold_label.text = GameState.fmt_int(GameState.gold)
	_credits_label.text = GameState.fmt_int(GameState.credits)


func _refresh_mode() -> void:
	_mode_title.text = GameState.mode_title()
	if _match_state == Match.IDLE:
		_mode_sub.text = GameState.mode_subtitle()


func _refresh_status() -> void:
	_region_label.text = GameState.region_name()
	_quality_label.text = str(GameState.QUALITY_TAGS[GameState.quality])
	var ping := GameState.region_ping()
	if ping < 60:
		_signal_icon.modulate = Color(0.35, 0.9, 0.4)
	elif ping < 100:
		_signal_icon.modulate = Color(1.0, 0.8, 0.2)
	else:
		_signal_icon.modulate = Color(1.0, 0.35, 0.3)


func _refresh_squad() -> void:
	for i in _slot_buttons.size():
		var filled := i < GameState.squad_members.size()
		_slot_icons[i].visible = not filled
		_slot_labels[i].visible = filled
		if filled:
			_slot_labels[i].text = str(GameState.squad_members[i]).substr(0, 1)
			_slot_buttons[i].add_theme_stylebox_override("normal", _sb(Color(1.0, 0.78, 0.1, 0.18), 3, GOLD, 2))
		else:
			_slot_buttons[i].add_theme_stylebox_override("normal", _sb(Color(1, 1, 1, 0.07), 3, Color(1, 1, 1, 0.18), 1))
	_friends_label.text = "%d/%d" % [Online.friends_online_count(), Online.friends.size()]


func _on_squad_slot(index: int) -> void:
	if index < GameState.squad_members.size():
		_open_squad_member(index)
	else:
		_open_find_teammates()


func _open_squad_member(index: int) -> void:
	var member := str(GameState.squad_members[index])
	var body := _open_modal("Squad", 760, 380)
	var row := _hbox(body, 24)
	var ic := _icon(row, "person", 90, GOLD)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(vb)
	_label(vb, member, 46, Color.WHITE, font_heavy)
	_label(vb, "Ready  ·  %s" % GameState.mode_title(), 28, Color(0.5, 1.0, 0.55), font_medium)
	var buttons := _hbox(body, 16)
	_action_button(buttons, "REMOVE FROM SQUAD", _kick_member.bind(index), false, 340)
	_action_button(buttons, "CLOSE", _close_modal.bind(false), true, 200)


func _kick_member(index: int) -> void:
	var member := str(GameState.squad_members[index])
	GameState.remove_squad_member(index)
	_close_modal()
	toast("%s left the squad" % member)


func _refresh_missions_dot() -> void:
	if _missions_dot:
		_missions_dot.visible = GameState.has_claimable_missions()


func _update_clock() -> void:
	var t := Time.get_datetime_dict_from_system(true)
	_clock_label.text = "%04d/%02d/%02d %02d:%02d (UTC+0)" % [t["year"], t["month"], t["day"], t["hour"], t["minute"]]


func toast(text: String) -> void:
	_toast_label.text = text
	move_child(_toast, get_child_count() - 1)
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.15)
	_toast_tween.tween_interval(2.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.35)


# =============================================================================
# Actions
# =============================================================================

func _on_cloud() -> void:
	GameState.save_state()
	toast("Progress synced")


func _on_emote() -> void:
	if world and world.character:
		world.character.call("play_emote")


func _post_chat(sender: String, text: String) -> void:
	var line := "[%s]: %s" % [sender, text]
	_chat_log.append(line)
	if _chat_log.size() > 40:
		_chat_log.remove_at(0)
	_chat_msg.text = line
	if _chat_list and is_instance_valid(_chat_list):
		_add_chat_line(line)


# --- Matchmaking ------------------------------------------------------------

func _on_start_pressed() -> void:
	match _match_state:
		Match.IDLE:
			_begin_matching()
		Match.SEARCHING:
			_stop_matching()
			toast("Matchmaking cancelled")
		_:
			pass


func _begin_matching() -> void:
	_match_state = Match.SEARCHING
	_match_elapsed = 0.0
	_match_needed = randf_range(4.0, 8.0)
	_start_label.text = "CANCEL"
	_start_label.add_theme_font_size_override("font_size", 92)
	_start_play.visible = false
	_mode_card.disabled = true
	_mode_sub.text = "Matching...  00:00"


func _stop_matching() -> void:
	_match_state = Match.IDLE
	_start_label.text = "START"
	_start_label.add_theme_font_size_override("font_size", 116)
	_start_play.visible = true
	_mode_card.disabled = false
	_refresh_mode()


func _on_match_found() -> void:
	_match_state = Match.FOUND
	_start_label.text = "READY"
	var ov := ColorRect.new()
	ov.color = Color(0, 0, 0, 0)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(ov)
	_fill(ov)
	_overlay = ov
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	ov.add_child(box)
	_fill(box)
	var title := _label(box, "MATCH FOUND", 110, GOLD, font_heavy)
	_outline(title, 8, Color(0, 0, 0, 0.6))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var squad: Dictionary = GameState.SQUADS[GameState.squad_index]
	var info := _label(box, "%s   ·   %s   ·   %s %s" % [GameState.mode_title(), GameState.map_name(), str(squad["name"]), "FPP" if GameState.fpp else "TPP"], 36, Color.WHITE, font_bold)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(holder)
	var bar := _progress(holder, 0.0, 760, 14)
	var status := _label(box, "Deploying to Vis Island, Croatia...", 28, TEXT_DIM, font_medium)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ov, "color:a", 0.78, 0.35)
	tw.tween_property(box, "modulate:a", 1.0, 0.35)
	tw.tween_property(bar, "value", 1.0, 3.2).set_delay(0.4).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_interval(0.4)
	tw.chain().tween_callback(_finish_match)


func _finish_match() -> void:
	# Load the real battleground (Vis Island) behind the match loading screen.
	SceneRouter.go("res://scenes/battleground.tscn", "VIS ISLAND", "Croatia  ·  real terrain, streets and buildings", true)


# =============================================================================
# Pop-up panels
# =============================================================================

func _open_modal(title: String, w: float = 980.0, h: float = 600.0) -> VBoxContainer:
	_close_modal(true)
	_chat_list = null
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_fill(dim)
	dim.gui_input.connect(_on_dim_input)
	_modal = dim

	var panel := PanelContainer.new()
	var sb := _sb(Color(0.065, 0.08, 0.11, 0.97), 10, Color(1.0, 0.78, 0.1, 0.5), 2)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 18
	panel.add_theme_stylebox_override("panel", _margins(sb, 30, 20))
	dim.add_child(panel)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -w * 0.5
	panel.offset_right = w * 0.5
	panel.offset_top = -h * 0.5
	panel.offset_bottom = h * 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.pivot_offset = Vector2(w, h) * 0.5

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	var header := HBoxContainer.new()
	vb.add_child(header)
	var t := _label(header, title.to_upper(), 46, GOLD, font_heavy)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := _button(header, _sb(Color(1, 1, 1, 0.06), 6), _sb(Color(1, 1, 1, 0.16), 6))
	close.custom_minimum_size = Vector2(56, 56)
	var ci := _icon(close, "close", 28)
	ci.position = Vector2(14, 14)
	close.pressed.connect(_close_modal.bind(false))
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.12)
	line.custom_minimum_size = Vector2(0, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(line)
	var body := VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	vb.add_child(body)

	move_child(_toast, get_child_count() - 1)
	panel.scale = Vector2(0.92, 0.92)
	dim.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(dim, "modulate:a", 1.0, 0.16)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return body


func _on_dim_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_close_modal()


func _close_modal(immediate: bool = false) -> void:
	_chat_list = null
	_crate_result = null
	if _modal == null or not is_instance_valid(_modal):
		_modal = null
		return
	var m := _modal
	_modal = null
	if immediate:
		m.queue_free()
		return
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(m, "modulate:a", 0.0, 0.14)
	tw.tween_callback(m.queue_free)


func _section(parent: Control, text: String) -> void:
	_label(parent, text, 26, Color(1, 1, 1, 0.55), font_bold)


func _hbox(parent: Control, separation: int = 12) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", separation)
	parent.add_child(hb)
	return hb


func _style_choice(b: Button) -> void:
	var n := _sb(Color(1, 1, 1, 0.06), 6, Color(1, 1, 1, 0.16), 2)
	var h := _sb(Color(1, 1, 1, 0.12), 6, Color(1, 1, 1, 0.32), 2)
	var p := _sb(GOLD, 6, Color(1.0, 0.9, 0.5), 2)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("hover_pressed", p)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(0.08, 0.08, 0.08))
	b.add_theme_color_override("font_hover_pressed_color", Color(0.08, 0.08, 0.08))


func _choice_row(parent: Control, options: Array, selected: int, action: Callable, min_width: float = 170.0) -> Array[Button]:
	var hb := _hbox(parent, 12)
	var buttons: Array[Button] = []
	for i in options.size():
		var b := Button.new()
		b.text = str(options[i])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.custom_minimum_size = Vector2(min_width, 58)
		b.add_theme_font_size_override("font_size", 30)
		_style_choice(b)
		hb.add_child(b)
		buttons.append(b)
	_bind_choice(buttons, selected, action)
	return buttons


func _bind_choice(buttons: Array, selected: int, action: Callable) -> void:
	for i in buttons.size():
		var b: Button = buttons[i]
		b.set_pressed_no_signal(i == selected)
		b.pressed.connect(_on_choice.bind(buttons, i, action))


func _on_choice(buttons: Array, index: int, action: Callable) -> void:
	for i in buttons.size():
		var b: Button = buttons[i]
		b.set_pressed_no_signal(i == index)
	action.call(index)


func _swatch(parent: Control, a: Color, b: Color, title: String) -> Button:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.custom_minimum_size = Vector2(168, 150)
	var sel := _sb(Color(1, 1, 1, 0.12), 8, GOLD, 4)
	btn.add_theme_stylebox_override("normal", _sb(Color(1, 1, 1, 0.06), 8, Color(1, 1, 1, 0.15), 2))
	btn.add_theme_stylebox_override("hover", _sb(Color(1, 1, 1, 0.1), 8, Color(1, 1, 1, 0.35), 2))
	btn.add_theme_stylebox_override("pressed", sel)
	btn.add_theme_stylebox_override("hover_pressed", sel)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	parent.add_child(btn)
	var left := ColorRect.new()
	left.color = a
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(left)
	left.position = Vector2(24, 18)
	left.size = Vector2(60, 64)
	var right := ColorRect.new()
	right.color = b
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(right)
	right.position = Vector2(84, 18)
	right.size = Vector2(60, 64)
	var l := _label(btn, title, 28, Color.WHITE, font_bold)
	l.position = Vector2(0, 94)
	l.size = Vector2(168, 40)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return btn


func _action_button(parent: Control, text: String, action: Callable, primary: bool = true, min_width: float = 260.0) -> Button:
	var bg := GOLD if primary else Color(1, 1, 1, 0.1)
	var b := _button(parent, _sb(bg, 6), _sb(bg.lightened(0.15) if primary else Color(1, 1, 1, 0.18), 6))
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 62)
	b.add_theme_font_override("font", font_heavy)
	b.add_theme_font_size_override("font_size", 32)
	var fc := Color(0.08, 0.08, 0.08) if primary else Color.WHITE
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_hover_color", fc)
	b.add_theme_color_override("font_pressed_color", fc)
	b.add_theme_color_override("font_hover_pressed_color", fc)
	b.pressed.connect(action)
	return b


func _card(parent: Control, bg: Color = Color(1, 1, 1, 0.05)) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _margins(_sb(bg, 8), 18, 12))
	parent.add_child(pc)
	return pc


# --- Individual panels ---------------------------------------------------------

func _open_profile() -> void:
	var body := _open_modal("Player Profile", 980, 560)
	var row := _hbox(body, 34)
	var pic := _texture_rect(row, _portrait_tex)
	pic.custom_minimum_size = Vector2(240, 240)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 8)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_row := _hbox(info, 10)
	_label(name_row, GameState.player_name, 56, Color.WHITE, font_heavy)
	var crown := _icon(name_row, "crown", 40)
	crown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_label(info, "Level %d   ·   Tier: Gold III   ·   Region: %s" % [GameState.level, GameState.region_name()], 30, TEXT_DIM, font_medium)
	_progress(info, GameState.xp_ratio, 520, 12)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 60)
	grid.add_theme_constant_override("v_separation", 18)
	info.add_child(grid)
	var stats := [["1,284", "Matches"], ["96", "Wins"], ["3.42", "K/D"], ["41%", "Top 10"], ["22%", "Headshots"], ["412 m", "Longest kill"]]
	for s in stats:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", -6)
		grid.add_child(cell)
		_label(cell, str(s[0]), 44, GOLD, font_heavy)
		_label(cell, str(s[1]), 26, TEXT_DIM, font_medium)


func _open_mode_select() -> void:
	if _match_state != Match.IDLE:
		return
	var body := _open_modal("Select Mode", 1180, 760)
	_section(body, "MODE")
	_choice_row(body, GameState.MODES, GameState.mode_index, GameState.set_mode)
	_section(body, "MAP")
	var maps_row := _hbox(body, 14)
	var map_buttons: Array[Button] = []
	for i in GameState.MAPS.size():
		var m: Dictionary = GameState.MAPS[i]
		var col: Color = m["color"]
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.custom_minimum_size = Vector2(262, 136)
		var sel := _sb(col, 8, GOLD, 5)
		b.add_theme_stylebox_override("normal", _sb(col.darkened(0.25), 8, Color(1, 1, 1, 0.15), 2))
		b.add_theme_stylebox_override("hover", _sb(col.darkened(0.1), 8, Color(1, 1, 1, 0.4), 2))
		b.add_theme_stylebox_override("pressed", sel)
		b.add_theme_stylebox_override("hover_pressed", sel)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		maps_row.add_child(b)
		var n := _label(b, str(m["name"]), 40, Color.WHITE, font_heavy)
		_outline(n, 5, Color(0, 0, 0, 0.5))
		n.position = Vector2(16, 30)
		var d := _label(b, str(m["info"]), 24, Color(1, 1, 1, 0.85), font_medium)
		d.position = Vector2(16, 80)
		map_buttons.append(b)
	_bind_choice(map_buttons, GameState.map_index, GameState.set_map)
	var row := _hbox(body, 60)
	var team := VBoxContainer.new()
	team.add_theme_constant_override("separation", 10)
	row.add_child(team)
	_section(team, "TEAM")
	var squad_names: Array = []
	for s in GameState.SQUADS:
		squad_names.append(s["name"])
	_choice_row(team, squad_names, GameState.squad_index, GameState.set_squad, 150)
	var view := VBoxContainer.new()
	view.add_theme_constant_override("separation", 10)
	row.add_child(view)
	_section(view, "PERSPECTIVE")
	_choice_row(view, ["TPP", "FPP"], 1 if GameState.fpp else 0, _set_fpp_index, 130)
	var bottom := _hbox(body, 30)
	var ranked := CheckButton.new()
	ranked.text = "Ranked match"
	ranked.focus_mode = Control.FOCUS_NONE
	ranked.button_pressed = GameState.ranked
	ranked.add_theme_font_size_override("font_size", 30)
	ranked.toggled.connect(GameState.set_ranked)
	ranked.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(ranked)
	_action_button(bottom, "CONFIRM", _close_modal.bind(false))


func _set_fpp_index(index: int) -> void:
	GameState.set_fpp(index == 1)


func _open_settings() -> void:
	var body := _open_modal("Settings", 1100, 640)
	_section(body, "GRAPHICS")
	_choice_row(body, GameState.QUALITY_NAMES, GameState.quality, GameState.set_quality, 200)
	_section(body, "FRAME RATE")
	var fps_names: Array = []
	for f in GameState.FPS_OPTIONS:
		fps_names.append("%d FPS" % f)
	_choice_row(body, fps_names, GameState.fps_index, GameState.set_fps, 200)
	_section(body, "SERVER REGION")
	var regions: Array = []
	for r in GameState.REGIONS:
		regions.append("%s  (%d ms)" % [r["name"], r["ping"]])
	_choice_row(body, regions, GameState.region_index, GameState.set_region, 240)
	var fps_toggle := CheckButton.new()
	fps_toggle.text = "Show FPS counter"
	fps_toggle.focus_mode = Control.FOCUS_NONE
	fps_toggle.button_pressed = GameState.show_fps
	fps_toggle.add_theme_font_size_override("font_size", 30)
	fps_toggle.toggled.connect(_set_show_fps)
	var account := _hbox(body, 16)
	_action_button(account, "CHANGE CHARACTER", _change_character, false, 300)
	_action_button(account, "TRAINING GROUND", _open_training, false, 300)
	_action_button(account, "SIGN OUT", _sign_out, false, 220)
	var who := "Guest" if GameState.auth_provider != "google" else "Google: %s" % GameState.account_email
	var who_label := _label(account, who, 24, TEXT_DIM, font_medium)
	who_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var toggles := _hbox(body, 40)
	toggles.add_child(fps_toggle)
	if not (OS.has_feature("mobile") or OS.has_feature("web")):
		var fs := CheckButton.new()
		fs.text = "Full screen  (F11)"
		fs.focus_mode = Control.FOCUS_NONE
		fs.button_pressed = GameState.fullscreen
		fs.add_theme_font_size_override("font_size", 30)
		fs.toggled.connect(GameState.set_fullscreen)
		toggles.add_child(fs)


func _change_character() -> void:
	SceneRouter.go("res://scenes/onboarding.tscn", "CHARACTER", "Choose who you play as")


func _open_training() -> void:
	SceneRouter.go("res://scenes/training.tscn", "TRAINING GROUND", "Movement course  ·  armory  ·  shooting range")


func _sign_out() -> void:
	Online.sign_out()
	GameState.sign_out()
	SceneRouter.go("res://scenes/onboarding.tscn", "AURUM", "Sign in")


func _set_show_fps(on: bool) -> void:
	GameState.show_fps = on
	_fps_label.visible = on
	GameState.save_state()


func _open_inventory() -> void:
	_open_inventory_tab("outfits")


func _open_inventory_tab(tab: String) -> void:
	var body := _open_modal("Inventory", 1280, 760)
	var tabs := _hbox(body, 12)
	for t in [["outfits", "OUTFITS"], ["characters", "CHARACTERS"], ["weapons", "WEAPONS"]]:
		var tb := _action_button(tabs, str(t[1]), _open_inventory_tab.bind(str(t[0])), str(t[0]) == tab, 240)
		tb.custom_minimum_size = Vector2(240, 56)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 520)
	body.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 6 if tab != "weapons" else 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	var cid := GameState.character_id if GameState.character_id != "" else "soldier"
	match tab:
		"outfits":
			for o in CharacterDB.OUTFITS:
				var oid := str(o["id"])
				_item_card(grid, CharacterDB.thumb(cid, oid), str(o["name"]), oid == GameState.outfit_id, Vector2(180, 270), _equip_outfit.bind(oid))
		"characters":
			for c in CharacterDB.CHARACTERS:
				var id := str(c["id"])
				_item_card(grid, CharacterDB.thumb(id, "original"), str(c["name"]), id == GameState.character_id, Vector2(180, 270), _equip_character.bind(id))
		"weapons":
			for wid in WeaponDB.ids():
				var w := WeaponDB.get_weapon(str(wid))
				_item_card(grid, CharacterDB.weapon_thumb(str(wid)), "%s  ·  %s" % [str(w["name"]), str(w["ammo"])], str(wid) == GameState.equipped_weapon, Vector2(280, 170), _equip_weapon.bind(str(wid)))
	_label(body, "Tap an item to equip it. Equipped items have a gold frame.", 24, TEXT_DIM, font_medium)


func _item_card(parent: Control, image: String, title: String, equipped: bool, card_size: Vector2, action: Callable) -> void:
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.custom_minimum_size = card_size
	for state in ["normal", "hover", "pressed"]:
		var bg := Color(1, 1, 1, 0.14 if equipped else (0.1 if state == "hover" else 0.05))
		card.add_theme_stylebox_override(state, _sb(bg, 10, GOLD if equipped else Color(1, 1, 1, 0.15), 4 if equipped else 1))
	card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	card.pressed.connect(action)
	parent.add_child(card)
	if ResourceLoader.exists(image):
		var img := _texture_rect(card, load(image), TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
		img.position = Vector2(8, 6)
		img.size = Vector2(card_size.x - 16, card_size.y - 52)
	var l := _label(card, title, 24, Color.WHITE, font_bold)
	l.position = Vector2(0, card_size.y - 44)
	l.size = Vector2(card_size.x, 38)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	if equipped:
		var tag := _label(card, "EQUIPPED", 20, GOLD, font_heavy)
		tag.position = Vector2(10, 6)


func _equip_outfit(oid: String) -> void:
	GameState.outfit_id = oid
	GameState.save_state()
	if world and world.character and world.character.has_method("apply_outfit"):
		world.character.call("apply_outfit", oid)
	toast("Equipped outfit: %s" % CharacterDB.outfit_name(oid))
	_open_inventory_tab("outfits")


func _equip_character(id: String) -> void:
	GameState.character_id = id
	GameState.save_state()
	toast("Character changed - reloading lobby")
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _equip_weapon(wid: String) -> void:
	GameState.equipped_weapon = wid
	GameState.save_state()
	if world:
		world.hold_weapon(wid)
	toast("Equipped: %s" % str(WeaponDB.get_weapon(wid)["name"]))
	_open_inventory_tab("weapons")

func _open_missions() -> void:
	var body := _open_modal("Missions", 1040, 700)
	var t := Time.get_datetime_dict_from_system(true)
	var left := 86400 - (int(t["hour"]) * 3600 + int(t["minute"]) * 60 + int(t["second"]))
	_label(body, "Daily missions reset in %02d:%02d:%02d" % [left / 3600, (left % 3600) / 60, left % 60], 28, TEXT_DIM, font_medium)
	for i in GameState.missions.size():
		var m: Dictionary = GameState.missions[i]
		var card := _card(body)
		var hb := _hbox(card, 20)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 6)
		hb.add_child(info)
		_label(info, str(m["title"]), 32, Color.WHITE, font_bold)
		var progress := int(m["progress"])
		var goal := int(m["goal"])
		var bar_row := _hbox(info, 14)
		var bar := _progress(bar_row, float(progress) / float(goal), 420, 12)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_label(bar_row, "%d / %d" % [progress, goal], 24, TEXT_DIM, font_medium)
		var reward := _hbox(hb, 6)
		reward.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var coin := _icon(reward, "coin", 32)
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_label(reward, "+%d" % int(m["reward"]), 32, GOLD, font_bold)
		var btn: Button
		if m["claimed"]:
			btn = _action_button(hb, "CLAIMED", _noop, false, 170)
			btn.disabled = true
		elif progress >= goal:
			btn = _action_button(hb, "CLAIM", _claim_mission.bind(i), true, 170)
		else:
			btn = _action_button(hb, "GO", _close_modal.bind(false), false, 170)
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _noop() -> void:
	pass


func _claim_mission(index: int) -> void:
	var reward := GameState.claim_mission(index)
	if reward > 0:
		toast("+%d Gold" % reward)
	_open_missions()


func _open_chat() -> void:
	var body := _open_modal("World Chat", 1000, 680)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 420)
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	_chat_list = list
	for line in _chat_log:
		_add_chat_line(line)
	var row := _hbox(body, 12)
	var input := LineEdit.new()
	input.placeholder_text = "Say something to the world..."
	input.max_length = 120
	input.custom_minimum_size = Vector2(0, 60)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.add_theme_font_size_override("font_size", 30)
	input.add_theme_stylebox_override("normal", _margins(_sb(Color(1, 1, 1, 0.08), 6, Color(1, 1, 1, 0.2), 1), 16, 6))
	input.add_theme_stylebox_override("focus", _margins(_sb(Color(1, 1, 1, 0.1), 6, GOLD, 2), 16, 6))
	row.add_child(input)
	input.text_submitted.connect(_send_chat.bind(input))
	_action_button(row, "SEND", _send_chat_from.bind(input), true, 160)
	input.grab_focus.call_deferred()


func _add_chat_line(line: String) -> void:
	if _chat_list == null or not is_instance_valid(_chat_list):
		return
	var hb := _hbox(_chat_list, 12)
	_label(hb, "World", 28, WORLD_BLUE, font_bold)
	var l := _label(hb, line, 28, Color.WHITE, font_medium)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_chat_to_end.call_deferred()


func _scroll_chat_to_end() -> void:
	if _chat_list and is_instance_valid(_chat_list):
		var scroll := _chat_list.get_parent() as ScrollContainer
		if scroll:
			scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _send_chat(text: String, input: LineEdit) -> void:
	var msg := text.strip_edges()
	if msg.is_empty():
		return
	_post_chat(GameState.player_name, msg)
	input.clear()


func _send_chat_from(input: LineEdit) -> void:
	_send_chat(input.text, input)


func _open_pass() -> void:
	var body := _open_modal("Aurum Pass  ·  Season 1", 1300, 720)
	var art := _texture_rect(body, Icons.svg_texture(Icons.PASS_ART, 2.0), TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	art.custom_minimum_size = Vector2(0, 150)
	var rank_row := _hbox(body, 16)
	_label(rank_row, "Rank 23", 38, GOLD, font_heavy)
	var bar := _progress(rank_row, 0.62, 640, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_label(rank_row, "620 / 1000 RP", 28, TEXT_DIM, font_medium)
	var tiers := _hbox(body, 12)
	var rewards := [["coin", "200 Gold"], ["chest", "Classic Crate"], ["rifle", "Rifle Skin"], ["star", "Emote"], ["gem", "60 Credits"], ["shield", "Helmet Skin"], ["pass", "Frame"]]
	for i in rewards.size():
		var r: Array = rewards[i]
		var current := i == 0
		var pc := PanelContainer.new()
		var bg := Color(1.0, 0.78, 0.1, 0.18) if current else Color(1, 1, 1, 0.05)
		pc.add_theme_stylebox_override("panel", _margins(_sb(bg, 8, GOLD if current else Color(1, 1, 1, 0.12), 2), 10, 10))
		pc.custom_minimum_size = Vector2(162, 200)
		tiers.add_child(pc)
		var vb := VBoxContainer.new()
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", 6)
		pc.add_child(vb)
		var num := _label(vb, str(24 + i), 30, Color.WHITE if current else TEXT_DIM, font_heavy)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var ic_holder := CenterContainer.new()
		vb.add_child(ic_holder)
		_icon(ic_holder, str(r[0]), 64)
		var rl := _label(vb, str(r[1]), 24, Color.WHITE, font_medium)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if i >= 3:
			var lock_holder := CenterContainer.new()
			vb.add_child(lock_holder)
			_icon(lock_holder, "lock", 22, Color(1, 1, 1, 0.6))
	var buy_row := _hbox(body, 20)
	_action_button(buy_row, "UPGRADE PASS  ·  600 CREDITS", _buy_pass, true, 520)
	var hint := _label(buy_row, "Unlock elite rewards and 25 instant ranks.", 26, TEXT_DIM, font_medium)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _buy_pass() -> void:
	if GameState.spend_credits(600):
		toast("Aurum Pass upgraded!")
		_close_modal()
	else:
		toast("Not enough credits")


func _open_crate() -> void:
	var body := _open_modal("Crates", 980, 560)
	var row := _hbox(body, 30)
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(220, 220)
	row.add_child(holder)
	_icon(holder, "chest", 190, GOLD)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 10)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	_label(info, "Classic Crate", 48, Color.WHITE, font_heavy)
	var prizes := _label(info, "Possible rewards: " + ", ".join(PackedStringArray(CRATE_PRIZES)), 26, TEXT_DIM, font_medium)
	prizes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prizes.custom_minimum_size = Vector2(560, 0)
	_crate_result = _label(info, "", 32, GOLD, font_bold)
	_action_button(info, "OPEN  ·  120 GOLD", _roll_crate, true, 340)


func _roll_crate() -> void:
	if not GameState.spend_gold(120):
		toast("Not enough gold")
		return
	var prize: String = CRATE_PRIZES[randi() % CRATE_PRIZES.size()]
	if prize == "Gold Coin x50":
		GameState.add_gold(50)
	if _crate_result and is_instance_valid(_crate_result):
		_crate_result.text = "You got: %s" % prize
	toast("You got: %s" % prize)


func _open_shop(deals: bool) -> void:
	var body := _open_modal("Deals" if deals else "Shop", 1180, 640)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	body.add_child(grid)
	var items := [
		["Midnight Hoodie", "rifle", 480, 0],
		["Desert Scarf", "star", 260, 0],
		["Gilded Rifle Skin", "rifle", 0, 120],
		["Classic Crate x5", "chest", 540, 0],
		["Credits Pack 300", "gem", 0, 0],
		["Neon Parachute", "pass", 0, 90],
	]
	for it in items:
		var title: String = it[0]
		var gold_price: int = it[2]
		var credit_price: int = it[3]
		if deals:
			gold_price = int(gold_price * 0.6)
			credit_price = int(credit_price * 0.6)
		var card := _card(grid)
		card.custom_minimum_size = Vector2(360, 0)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 8)
		card.add_child(vb)
		var top := _hbox(vb, 12)
		_icon(top, str(it[1]), 48)
		_label(top, title, 30, Color.WHITE, font_bold)
		var price_text := "FREE"
		if gold_price > 0:
			price_text = "%s GOLD" % GameState.fmt_int(gold_price)
		elif credit_price > 0:
			price_text = "%d CREDITS" % credit_price
		if deals:
			price_text += "   -40%"
		_action_button(vb, price_text, _buy_item.bind(title, gold_price, credit_price), gold_price > 0 or credit_price > 0, 320)


func _buy_item(title: String, gold_price: int, credit_price: int) -> void:
	var ok := true
	if gold_price > 0:
		ok = GameState.spend_gold(gold_price)
	elif credit_price > 0:
		ok = GameState.spend_credits(credit_price)
	else:
		GameState.credits += 300
		GameState.currency_changed.emit()
		GameState.save_state()
	if ok:
		toast("Purchased: %s" % title)
	else:
		toast("Not enough %s" % ("gold" if gold_price > 0 else "credits"))


func _open_events() -> void:
	var body := _open_modal("Events", 1060, 640)
	var events := [
		["Golden Games", "Win 3 Classic matches this week to earn a golden parachute.", "trophy"],
		["Weekend Arena Rush", "Double gold for every Arena match until Sunday.", "star"],
		["Squad Up", "Play with a friend and both get a Classic Crate.", "squad"],
	]
	for e in events:
		var card := _card(body)
		var hb := _hbox(card, 18)
		var ic := _icon(hb, str(e[2]), 64)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(vb)
		_label(vb, str(e[0]), 34, GOLD, font_heavy)
		var d := _label(vb, str(e[1]), 26, Color.WHITE, font_medium)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var event_name := str(e[0])
		var joined := GameState.joined_events.has(event_name)
		var join := _action_button(hb, "JOINED" if joined else "JOIN", _noop, not joined, 170)
		join.disabled = joined
		join.pressed.connect(_join_event.bind(event_name, join))
		join.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _join_event(event_name: String, button: Button) -> void:
	if not GameState.joined_events.has(event_name):
		GameState.joined_events.append(event_name)
		GameState.save_state()
	button.text = "JOINED"
	button.disabled = true
	toast("Joined: %s" % event_name)


func _open_find_teammates() -> void:
	_open_friends()


## Friends: your player ID, add a friend by ID, friend requests, squad invites and the
## friends list with presence. Data comes from the Online autoload (Firebase).
func _open_friends() -> void:
	var body := _open_modal("Friends", 1100, 760)
	_friends_body = body
	var top := _hbox(body, 18)
	var id_text := "Your ID:  %s" % (Online.player_id if Online.player_id != "" else "--------")
	var id_label := _label(top, id_text, 34, GOLD, font_bold)
	id_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var copy := _action_button(top, "COPY ID", _copy_player_id, false, 170)
	copy.disabled = Online.player_id == ""
	var status := _label(top, Online.status_text(), 26, Color(0.4, 0.9, 0.45) if Online.is_online() else Color(1.0, 0.45, 0.4), font_medium)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var add_row := _hbox(body, 12)
	var input := LineEdit.new()
	input.placeholder_text = "Friend's player ID (8 digits)"
	input.max_length = 8
	input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	input.custom_minimum_size = Vector2(0, 62)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.add_theme_font_size_override("font_size", 30)
	input.add_theme_stylebox_override("normal", _margins(_sb(Color(1, 1, 1, 0.08), 6, Color(1, 1, 1, 0.2), 1), 16, 6))
	input.add_theme_stylebox_override("focus", _margins(_sb(Color(1, 1, 1, 0.1), 6, GOLD, 2), 16, 6))
	add_row.add_child(input)
	var add := _action_button(add_row, "ADD FRIEND", _noop, true, 240)
	add.pressed.connect(_send_friend_request.bind(input, add))
	add.disabled = not Online.is_online()
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	_friends_list = list
	_fill_friends_list()
	Online.poll()


func _fill_friends_list() -> void:
	if not is_instance_valid(_friends_list):
		return
	for c in _friends_list.get_children():
		c.queue_free()
	var list := _friends_list
	if not Online.is_online():
		var off := _label(list, "Friends need an internet connection and an online account. Your progress is still saved on this device and uploads when you are back online.", 28, TEXT_DIM, font_medium)
		off.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	if not Online.invites.is_empty():
		_label(list, "SQUAD INVITES", 26, GOLD, font_bold)
		for inv in Online.invites:
			var hb := _friend_row(list, str(inv["name"]), "ID %s  ·  invited you to their squad" % str(inv["player_id"]), true)
			_small_action(hb, "JOIN", _accept_invite.bind(str(inv["uid"]), str(inv["name"])), true)
			_small_action(hb, "IGNORE", _decline_invite.bind(str(inv["uid"])), false)
	if not Online.requests.is_empty():
		_label(list, "FRIEND REQUESTS", 26, GOLD, font_bold)
		for rq in Online.requests:
			var hb := _friend_row(list, str(rq["name"]), "ID %s" % str(rq["player_id"]), false)
			_small_action(hb, "ACCEPT", _accept_request.bind(str(rq["uid"])), true)
			_small_action(hb, "DECLINE", _decline_request.bind(str(rq["uid"])), false)
	_label(list, "FRIENDS  ·  %d online / %d" % [Online.friends_online_count(), Online.friends.size()], 26, GOLD, font_bold)
	if Online.friends.is_empty():
		var hint := _label(list, "No friends yet. Share your ID or enter a friend's ID above.", 28, TEXT_DIM, font_medium)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for f in Online.friends:
		var info := "Lv. %d  ·  ID %s  ·  %s" % [int(f["level"]), str(f["player_id"]), Online.last_seen_text(f)]
		var hb := _friend_row(list, str(f["name"]), info, bool(f["online"]))
		var in_squad := GameState.squad_members.has(str(f["name"]))
		var inv_b := _small_action(hb, "IN SQUAD" if in_squad else "INVITE", _invite_friend.bind(str(f["uid"]), str(f["name"])), not in_squad)
		inv_b.disabled = in_squad
		_small_action(hb, "REMOVE", _remove_friend.bind(str(f["uid"]), str(f["name"])), false)


func _friend_row(parent: Control, title: String, info: String, online: bool) -> HBoxContainer:
	var card := _card(parent)
	var hb := _hbox(card, 16)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(14, 14)
	dot.color = Color(0.35, 0.9, 0.4) if online else Color(1, 1, 1, 0.25)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(dot)
	var ic := _icon(hb, "person", 44)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", -4)
	hb.add_child(vb)
	_label(vb, title, 32, Color.WHITE, font_bold)
	_label(vb, info, 24, TEXT_DIM, font_medium)
	return hb


func _small_action(parent: Control, text: String, action: Callable, primary: bool) -> Button:
	var b := _action_button(parent, text, action, primary, 150)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


func _copy_player_id() -> void:
	DisplayServer.clipboard_set(Online.player_id)
	toast("ID %s copied" % Online.player_id)


func _send_friend_request(input: LineEdit, button: Button) -> void:
	button.disabled = true
	var err: String = await Online.send_friend_request(input.text)
	if is_instance_valid(button):
		button.disabled = false
	if err == "":
		toast("Friend request sent")
		if is_instance_valid(input):
			input.text = ""
	else:
		toast(err)


func _accept_request(from_uid: String) -> void:
	if await Online.accept_request(from_uid):
		toast("Friend added")


func _decline_request(from_uid: String) -> void:
	await Online.decline_request(from_uid)


func _remove_friend(friend_uid: String, friend_name: String) -> void:
	await Online.remove_friend(friend_uid)
	toast("%s removed from friends" % friend_name)


func _invite_friend(friend_uid: String, friend_name: String) -> void:
	if GameState.squad_members.size() >= GameState.SQUAD_SLOTS:
		toast("Your squad is full")
		return
	if await Online.invite_to_squad(friend_uid):
		toast("Squad invite sent to %s" % friend_name)
	else:
		toast("Could not send the invite")


func _accept_invite(from_uid: String, from_name: String) -> void:
	await Online.accept_invite(from_uid, from_name)
	toast("You joined %s's squad" % from_name)


func _decline_invite(from_uid: String) -> void:
	await Online.decline_invite(from_uid)


func _on_online_changed() -> void:
	_friends_label.text = "%d/%d" % [Online.friends_online_count(), Online.friends.size()]
	if is_instance_valid(_id_label):
		_id_label.text = "ID %s" % Online.player_id if Online.player_id != "" else ""
	_fill_friends_list()


func _open_info(title: String, icon_name: String, lines: Array, button_text: String = "", action: Callable = Callable()) -> void:
	var body := _open_modal(title, 940, 520)
	var row := _hbox(body, 30)
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(180, 180)
	row.add_child(holder)
	_icon(holder, icon_name, 140, Color(1, 1, 1, 0.9))
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 10)
	row.add_child(vb)
	for ln in lines:
		var l := _label(vb, str(ln), 30, Color.WHITE, font_medium)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(600, 0)
	if button_text != "" and action.is_valid():
		_action_button(vb, button_text, action, true, 340)


func _open_clan() -> void:
	if GameState.clan_name != "":
		_open_info("Clan  ·  " + GameState.clan_name, "shield", ["Members: 1 / 50  (%s - Leader)" % GameState.player_name, "Clan level 1  ·  Weekly clan rewards unlock at 5 members."], "LEAVE CLAN", _leave_clan)
		return
	var body := _open_modal("Clan", 940, 460)
	_label(body, "You are not in a clan yet. Create one and invite your friends.", 30, Color.WHITE, font_medium)
	var row := _hbox(body, 12)
	var input := LineEdit.new()
	input.placeholder_text = "Clan name (3-16 letters)"
	input.max_length = 16
	input.custom_minimum_size = Vector2(0, 62)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.add_theme_font_size_override("font_size", 30)
	input.add_theme_stylebox_override("normal", _margins(_sb(Color(1, 1, 1, 0.08), 6, Color(1, 1, 1, 0.2), 1), 16, 6))
	input.add_theme_stylebox_override("focus", _margins(_sb(Color(1, 1, 1, 0.1), 6, GOLD, 2), 16, 6))
	row.add_child(input)
	_action_button(row, "CREATE  ·  200 GOLD", _create_clan.bind(input), true, 320)


func _create_clan(input: LineEdit) -> void:
	var clan := input.text.strip_edges()
	if clan.length() < 3:
		toast("Clan name needs at least 3 letters")
		return
	if not GameState.spend_gold(200):
		toast("Not enough gold")
		return
	GameState.clan_name = clan
	GameState.save_state()
	_close_modal()
	toast("Clan %s created!" % clan)


func _leave_clan() -> void:
	var clan := GameState.clan_name
	GameState.clan_name = ""
	GameState.save_state()
	_close_modal()
	toast("You left %s" % clan)


func _open_season() -> void:
	var lines := ["Tier: Gold III  ·  1,240 points", "Reach Platinum to unlock the season avatar frame.", "Season ends in 41 days."]
	if GameState.season_claimed:
		_open_info("Season 1", "trophy", lines + ["Tier reward already claimed."])
	else:
		_open_info("Season 1", "trophy", lines, "CLAIM TIER REWARD  ·  +150", _claim_season)


func _claim_season() -> void:
	GameState.season_claimed = true
	GameState.add_gold(150)
	_close_modal()
	toast("+150 Gold  ·  Gold III reward")


func _open_workshop() -> void:
	var state := "ON" if GameState.workshop_notify else "OFF"
	_open_info("Workshop", "wrench", ["Build custom rooms, training maps and your own rule sets.", "Workshop launch notifications: %s" % state], "TURN NOTIFICATIONS " + ("OFF" if GameState.workshop_notify else "ON"), _toggle_workshop_notify)


func _toggle_workshop_notify() -> void:
	GameState.workshop_notify = not GameState.workshop_notify
	GameState.save_state()
	toast("Workshop notifications %s" % ("on" if GameState.workshop_notify else "off"))
	_open_workshop()


func _open_downloads() -> void:
	var body := _open_modal("Resource Packs", 1000, 600)
	var packs := [["HD Textures", "420 MB"], ["Arabic Voice Pack", "85 MB"], ["Solara Map Pack", "1.2 GB"], ["Classic Music", "60 MB"]]
	for pk in packs:
		var pack_name := str(pk[0])
		var card := _card(body)
		var hb := _hbox(card, 18)
		var ic := _icon(hb, "download", 44)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_theme_constant_override("separation", 6)
		hb.add_child(vb)
		_label(vb, "%s   ·   %s" % [pack_name, str(pk[1])], 30, Color.WHITE, font_bold)
		var installed := GameState.installed_packs.has(pack_name)
		var bar := _progress(vb, 1.0 if installed else 0.0, 520, 10)
		var btn := _action_button(hb, "INSTALLED" if installed else "DOWNLOAD", _noop, not installed, 200)
		btn.disabled = installed
		btn.pressed.connect(_download_pack.bind(pack_name, bar, btn))
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _download_pack(pack_name: String, bar: ProgressBar, btn: Button) -> void:
	btn.disabled = true
	btn.text = "DOWNLOADING"
	var tw := create_tween()
	tw.tween_property(bar, "value", 1.0, 2.5).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_pack_installed.bind(pack_name, btn))


func _pack_installed(pack_name: String, btn: Button) -> void:
	if not GameState.installed_packs.has(pack_name):
		GameState.installed_packs.append(pack_name)
		GameState.save_state()
	if is_instance_valid(btn):
		btn.text = "INSTALLED"
	toast("%s installed" % pack_name)


func _open_notices() -> void:
	_open_info("Notices", "notice", ["Season 1 is live: new Solara outpost, Aurum Pass and Golden Games event.", "Server maintenance: Tuesday 03:00 UTC (30 min)."])
