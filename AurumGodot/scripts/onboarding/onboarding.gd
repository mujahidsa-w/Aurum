extends Control
## First-run flow: Google sign-in (or guest) -> choose gender and a realistic character
## (3D preview, drag to rotate) -> choose outfit (pictures) -> enter name -> training.

const GoogleAuth := preload("res://scripts/onboarding/google_auth.gd")
const GoogleConfig := preload("res://scripts/onboarding/google_config.gd")
const CharacterDB := preload("res://scripts/game/character_db.gd")
const RealisticCharacter := preload("res://scripts/game/realistic_character.gd")
const Icons := preload("res://scripts/ui_icons.gd")

const GOLD := Color(1.0, 0.78, 0.1)
const PANEL := Color(0.05, 0.07, 0.1, 0.82)

const GOOGLE_G := "<svg xmlns='http://www.w3.org/2000/svg' width='64' height='64' viewBox='0 0 48 48'><path fill='#EA4335' d='M24 9.5c3.5 0 6.6 1.2 9.1 3.6l6.8-6.8C35.8 2.4 30.3 0 24 0 14.6 0 6.6 5.4 2.7 13.3l7.9 6.2C12.5 13.6 17.8 9.5 24 9.5z'/><path fill='#4285F4' d='M46.1 24.5c0-1.6-.1-3.1-.4-4.5H24v9h12.4c-.5 2.9-2.2 5.3-4.6 6.9l7.4 5.7c4.3-4 6.9-9.9 6.9-17.1z'/><path fill='#FBBC05' d='M10.6 28.6c-.5-1.4-.8-3-.8-4.6s.3-3.2.8-4.6l-7.9-6.2C1 16.6 0 20.2 0 24s1 7.4 2.7 10.7l7.9-6.1z'/><path fill='#34A853' d='M24 48c6.5 0 11.9-2.1 15.9-5.8l-7.4-5.7c-2.1 1.4-4.8 2.3-8.5 2.3-6.2 0-11.5-4.1-13.4-9.8l-7.9 6.1C6.6 42.6 14.6 48 24 48z'/></svg>"

enum Step { LOGIN, CHARACTER, OUTFIT, NAME }

var _step := Step.LOGIN
var _gender := "male"
var _character := "nathan"
var _outfit := "original"

var _font: Font
var _font_heavy: Font
var _auth: GoogleAuth
var _content: Control
var _preview_vp: SubViewport
var _preview_root: Node3D
var _preview_char: RealisticCharacter
var _preview_yaw := 0.0
var _dragging := false
var _status: Label
var _code_label: Label
var _name_edit: LineEdit
var _name_hint: Label
var _continue: Button
var _steps_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = _load_font("res://fonts/BarlowCondensed-SemiBold.ttf")
	_font_heavy = _load_font("res://fonts/BarlowCondensed-ExtraBold.ttf")
	var th := Theme.new()
	th.default_font = _font
	th.default_font_size = 30
	theme = th
	_auth = GoogleAuth.new()
	add_child(_auth)
	_auth.code_ready.connect(_on_code_ready)
	_auth.signed_in.connect(_on_signed_in)
	_auth.failed.connect(_on_auth_failed)
	_build_preview()
	if GameState.character_id != "":
		_character = GameState.character_id
		_gender = str(CharacterDB.get_character(_character)["gender"])
		_outfit = GameState.outfit_id
	_show_character_preview()
	if GameState.auth_provider != "":
		_go(Step.CHARACTER)
	else:
		_go(Step.LOGIN)


func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f := load(path) as Font
		if f:
			return f
	return ThemeDB.fallback_font


# --- 3D preview ------------------------------------------------------------------------

func _build_preview() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.07)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_vp = SubViewport.new()
	_preview_vp.own_world_3d = true
	_preview_vp.msaa_3d = Viewport.MSAA_4X
	container.add_child(_preview_vp)
	_preview_root = Node3D.new()
	_preview_vp.add_child(_preview_root)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	var hdr := "res://assets/textures/sky_partly_cloudy_2k.hdr"
	if ResourceLoader.exists(hdr):
		pano.panorama = load(hdr)
		sky.sky_material = pano
	else:
		sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.background_energy_multiplier = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	_preview_root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	_preview_root.add_child(sun)
	sun.rotation_degrees = Vector3(-35, -30, 0)
	var floor_mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.3
	disc.bottom_radius = 1.3
	disc.height = 0.06
	disc.radial_segments = 48
	floor_mi.mesh = disc
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.12, 0.13, 0.15)
	fm.metallic = 0.4
	fm.roughness = 0.35
	floor_mi.material_override = fm
	floor_mi.position = Vector3(0, -0.03, 0)
	_preview_root.add_child(floor_mi)
	var cam := Camera3D.new()
	cam.fov = 30.0
	_preview_root.add_child(cam)
	cam.position = Vector3(0.0, 1.15, 4.2)
	cam.look_at(Vector3(0.45, 0.95, 0.0), Vector3.UP)
	cam.current = true


func _show_character_preview() -> void:
	if _preview_char:
		_preview_char.queue_free()
		_preview_char = null
	var rc := RealisticCharacter.new()
	_preview_root.add_child(rc)
	if rc.setup(_character, _outfit):
		_preview_char = rc
		rc.rotation.y = PI + _preview_yaw # face the camera
		rc.play("pose_idle" if rc.has_animation("pose_idle") else "idle", 0.0)
	else:
		rc.queue_free()


func _process(delta: float) -> void:
	if _preview_char:
		if not _dragging:
			_preview_yaw = lerpf(_preview_yaw, 0.0, delta * 0.8)
		_preview_char.rotation.y = PI + _preview_yaw


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		_dragging = mb.pressed
	var mm := event as InputEventMouseMotion
	if mm and _dragging:
		_preview_yaw += mm.relative.x * 0.01


# --- UI helpers ------------------------------------------------------------------------

func _label(parent: Control, text: String, size_px: int, color: Color = Color.WHITE, heavy: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", _font_heavy if heavy else _font)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, action: Callable, primary: bool = true, width: float = 420.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(width, 70)
	b.add_theme_font_override("font", _font_heavy)
	b.add_theme_font_size_override("font_size", 32)
	var bg := GOLD if primary else Color(1, 1, 1, 0.1)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg.lightened(0.1) if state == "hover" else (bg.darkened(0.4) if state == "disabled" else bg)
		sb.set_corner_radius_all(8)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var fc := Color(0.08, 0.08, 0.08) if primary else Color.WHITE
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, fc)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _panel(x: float, y: float, w: float, h: float, ax: float = 0.0) -> VBoxContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_corner_radius_all(12)
	sb.border_color = Color(1.0, 0.78, 0.1, 0.35)
	sb.set_border_width_all(2)
	sb.content_margin_left = 32
	sb.content_margin_right = 32
	sb.content_margin_top = 26
	sb.content_margin_bottom = 26
	pc.add_theme_stylebox_override("panel", sb)
	pc.anchor_left = ax
	pc.anchor_right = ax
	pc.anchor_top = 0.5
	pc.anchor_bottom = 0.5
	pc.offset_left = x - ax * 1920.0
	pc.offset_right = x + w - ax * 1920.0
	pc.offset_top = y - 540.0
	pc.offset_bottom = y + h - 540.0
	_content.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	pc.add_child(vb)
	return vb


func _go(step: Step) -> void:
	_step = step
	if _content:
		_content.queue_free()
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var title := _label(_content, "AURUM", 64, GOLD, true)
	title.position = Vector2(48, 28)
	if step != Step.LOGIN:
		_steps_label = _label(_content, "", 28, Color(1, 1, 1, 0.8))
		_steps_label.position = Vector2(48, 108)
		var names := ["1  Character", "2  Outfit", "3  Name"]
		var parts: Array[String] = []
		for i in names.size():
			parts.append(("[ " + names[i] + " ]") if i == int(step) - 1 else names[i])
		_steps_label.text = "     ".join(PackedStringArray(parts))
	match step:
		Step.LOGIN:
			_build_login()
		Step.CHARACTER:
			_build_character_step()
		Step.OUTFIT:
			_build_outfit_step()
		Step.NAME:
			_build_name_step()


# --- Step 1: sign in -------------------------------------------------------------------------

func _build_login() -> void:
	var vb := _panel(1220, 230, 620, 620, 1.0)
	_label(vb, "Welcome, soldier", 52, Color.WHITE, true)
	_label(vb, "Sign in to keep your character, outfits and progress on every device.", 28, Color(1, 1, 1, 0.75))
	var g := _button(vb, "     Continue with Google", _start_google, false, 556)
	var gb := StyleBoxFlat.new()
	gb.bg_color = Color.WHITE
	gb.set_corner_radius_all(8)
	g.add_theme_stylebox_override("normal", gb)
	g.add_theme_stylebox_override("hover", gb)
	g.add_theme_stylebox_override("pressed", gb)
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		g.add_theme_color_override(k, Color(0.12, 0.12, 0.12))
	var logo := TextureRect.new()
	logo.texture = Icons.svg_texture(GOOGLE_G, 1.0)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_child(logo)
	logo.position = Vector2(26, 17)
	logo.size = Vector2(36, 36)
	_code_label = _label(vb, "", 56, GOLD, true)
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.visible = false
	_status = _label(vb, "", 26, Color(1, 1, 1, 0.8))
	_button(vb, "Play as guest", _guest, false, 556)
	_label(vb, "Guest progress stays on this device only.", 22, Color(1, 1, 1, 0.5))


func _start_google() -> void:
	if not GoogleConfig.is_configured():
		_status.text = "Google sign-in is not set up in this build yet (the developer must add an OAuth client ID in scripts/onboarding/google_config.gd). You can play as a guest now."
		return
	_status.text = "Contacting Google..."
	_auth.start()


func _on_code_ready(code: String, _url: String) -> void:
	_code_label.text = code
	_code_label.visible = true
	_status.text = "Your code was copied. Google opened in your browser: paste the code, choose any account (or add another) and allow. Waiting for confirmation..."


func _on_signed_in(profile: Dictionary) -> void:
	GameState.auth_provider = "google"
	GameState.account_email = str(profile.get("email", ""))
	GameState.account_name = str(profile.get("name", ""))
	if _status:
		_status.text = "Signed in. Restoring your progress from the cloud..."
	# Link the Google account to the online services and restore any saved progress.
	await Online.sign_in_google(str(profile.get("id_token", "")))
	GameState.auth_provider = "google"
	GameState.account_email = str(profile.get("email", ""))
	GameState.account_name = str(profile.get("name", ""))
	GameState.save_state()
	if GameState.character_id != "" and GameState.player_name != "" and GameState.trained:
		# Returning player on a new device: everything was restored.
		SceneRouter.go(GameState.entry_scene(), "WELCOME BACK", GameState.player_name)
		return
	_go(Step.CHARACTER)


func _on_auth_failed(reason: String) -> void:
	var msg := {
		"not_configured": "Google sign-in is not set up in this build yet.",
		"network": "No connection to Google. Check your internet and try again.",
		"denied": "Sign-in was cancelled in the browser.",
		"expired": "The code expired. Tap Continue with Google again.",
		"rejected": "Google rejected the request. Check the OAuth client settings.",
	}
	if _status:
		_status.text = str(msg.get(reason, "Sign-in failed."))


func _guest() -> void:
	_auth.cancel()
	GameState.auth_provider = "guest"
	GameState.save_state()
	Online.sign_in_guest()
	_go(Step.CHARACTER)


# --- Step 2: character -------------------------------------------------------------------------

func _build_character_step() -> void:
	var vb := _panel(1220, 160, 640, 760, 1.0)
	_label(vb, "Choose your character", 46, Color.WHITE, true)
	var genders := HBoxContainer.new()
	genders.add_theme_constant_override("separation", 12)
	vb.add_child(genders)
	for gdef in [["male", "MALE"], ["female", "FEMALE"]]:
		var b := _button(genders, str(gdef[1]), _set_gender.bind(str(gdef[0])), str(gdef[0]) == _gender, 280)
		b.custom_minimum_size = Vector2(280, 62)
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 14)
	vb.add_child(grid)
	for c in CharacterDB.by_gender(_gender):
		var id := str(c["id"])
		var card := Button.new()
		card.focus_mode = Control.FOCUS_NONE
		card.custom_minimum_size = Vector2(176, 300)
		for state in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(1, 1, 1, 0.12 if id == _character else 0.05)
			sb.set_corner_radius_all(10)
			sb.border_color = GOLD if id == _character else Color(1, 1, 1, 0.15)
			sb.set_border_width_all(4 if id == _character else 1)
			card.add_theme_stylebox_override(state, sb)
		card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		card.pressed.connect(_set_character.bind(id))
		grid.add_child(card)
		var tp := CharacterDB.thumb(id, "original")
		if ResourceLoader.exists(tp):
			var img := TextureRect.new()
			img.texture = load(tp)
			img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			img.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(img)
			img.position = Vector2(8, 6)
			img.size = Vector2(160, 240)
		var nl := _label(card, str(c["name"]), 28, Color.WHITE, true)
		nl.position = Vector2(0, 252)
		nl.size = Vector2(176, 40)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(vb, "Drag the character to look around.", 24, Color(1, 1, 1, 0.55))
	_button(vb, "CONTINUE", _go.bind(Step.OUTFIT), true, 576)


func _set_gender(g: String) -> void:
	if g == _gender:
		return
	_gender = g
	var list := CharacterDB.by_gender(g)
	if not list.is_empty():
		_character = str(list[0]["id"])
	_outfit = "original"
	_show_character_preview()
	_go(Step.CHARACTER)


func _set_character(id: String) -> void:
	_character = id
	_show_character_preview()
	_go(Step.CHARACTER)


# --- Step 3: outfit ---------------------------------------------------------------------------

func _build_outfit_step() -> void:
	var vb := _panel(1180, 150, 700, 780, 1.0)
	_label(vb, "Choose your outfit", 46, Color.WHITE, true)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vb.add_child(grid)
	for o in CharacterDB.OUTFITS:
		var oid := str(o["id"])
		var card := Button.new()
		card.focus_mode = Control.FOCUS_NONE
		card.custom_minimum_size = Vector2(200, 250)
		for state in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(1, 1, 1, 0.12 if oid == _outfit else 0.05)
			sb.set_corner_radius_all(10)
			sb.border_color = GOLD if oid == _outfit else Color(1, 1, 1, 0.15)
			sb.set_border_width_all(4 if oid == _outfit else 1)
			card.add_theme_stylebox_override(state, sb)
		card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		card.pressed.connect(_set_outfit.bind(oid))
		grid.add_child(card)
		var tp := CharacterDB.thumb(_character, oid)
		if ResourceLoader.exists(tp):
			var img := TextureRect.new()
			img.texture = load(tp)
			img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			img.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(img)
			img.position = Vector2(20, 4)
			img.size = Vector2(160, 200)
		var nl := _label(card, str(o["name"]), 26, Color.WHITE, true)
		nl.position = Vector2(0, 206)
		nl.size = Vector2(200, 36)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	_button(row, "BACK", _go.bind(Step.CHARACTER), false, 200)
	_button(row, "CONTINUE", _go.bind(Step.NAME), true, 420)


func _set_outfit(oid: String) -> void:
	_outfit = oid
	if _preview_char:
		_preview_char.apply_outfit(oid)
	_go(Step.OUTFIT)


# --- Step 4: name -------------------------------------------------------------------------------

func _build_name_step() -> void:
	var vb := _panel(1220, 280, 640, 520, 1.0)
	_label(vb, "Choose your name", 46, Color.WHITE, true)
	_label(vb, "3 to 14 letters. English or Arabic letters only - no numbers, spaces or symbols.", 26, Color(1, 1, 1, 0.75))
	_name_edit = LineEdit.new()
	_name_edit.max_length = 14
	_name_edit.custom_minimum_size = Vector2(0, 76)
	_name_edit.add_theme_font_size_override("font_size", 38)
	_name_edit.placeholder_text = "Your name"
	var default_name := GameState.account_name.replace(" ", "")
	if not GameState.is_valid_name(default_name):
		default_name = ""
	_name_edit.text = default_name
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.08)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 18
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.set_border_width_all(2)
	_name_edit.add_theme_stylebox_override("normal", sb)
	_name_edit.add_theme_stylebox_override("focus", sb)
	vb.add_child(_name_edit)
	_name_hint = _label(vb, "", 26)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	_button(row, "BACK", _go.bind(Step.OUTFIT), false, 200)
	_continue = _button(row, "START TRAINING", _finish, true, 380)
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_submitted.connect(_on_name_submitted)
	_on_name_changed(_name_edit.text)


func _on_name_changed(text: String) -> void:
	var ok := GameState.is_valid_name(text)
	_continue.disabled = not ok
	if text.is_empty():
		_name_hint.text = ""
	elif ok:
		_name_hint.text = "Looks good!"
		_name_hint.add_theme_color_override("font_color", Color(0.45, 0.95, 0.5))
	else:
		_name_hint.text = "Only letters A-Z or Arabic letters, 3 to 14 characters."
		_name_hint.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))


func _on_name_submitted(_text: String) -> void:
	if not _continue.disabled:
		_finish()


func _finish() -> void:
	var player_name := _name_edit.text.strip_edges()
	if not GameState.is_valid_name(player_name):
		return
	GameState.player_name = player_name
	GameState.character_id = _character
	GameState.outfit_id = _outfit
	GameState.save_state()
	Online.push_save()
	if GameState.trained:
		SceneRouter.go("res://scenes/lobby.tscn", "LOBBY", "Welcome back, %s" % player_name)
	else:
		SceneRouter.go("res://scenes/training.tscn", "TRAINING GROUND", "Learn to move, loot and shoot")
