extends Control
## Startup loader: loads the game's resources on background threads, measures the internet
## connection (latency + download speed) and connects the account to the online services,
## then opens sign-in (first launch) or the lobby.

const Router := preload("res://scripts/scene_router.gd")
const CharacterDB := preload("res://scripts/game/character_db.gd")
const WeaponDB := preload("res://scripts/game/weapon_db.gd")

const SPEED_HOST := "speed.cloudflare.com"
const FALLBACK_HOST := "www.gstatic.com"
const DOWNLOAD_BYTES := 4000000
const NET_TIMEOUT_MS := 9000
const GOLD := Color(1.0, 0.78, 0.1)

var _queue: Array[String] = []
var _total := 0
var _loaded := 0
var _resources_done := false
var _net_done := false
var _online_done := false
var _online_started := false
var _leaving := false
var _started_at := 0

# Network test (written by the worker thread, read by the UI).
var _net_thread: Thread
var _net_bytes := 0
var _net_phase := "Measuring latency"
var _net_ok := false
var _net_mbps := 0.0
var _net_ping := 0.0

var _bar: ProgressBar
var _status: Label
var _percent: Label
var _net_label: Label
var _net_bars: NetBars
var _shown := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_started_at = Time.get_ticks_msec()
	_build_ui()
	_queue_resources()
	_net_thread = Thread.new()
	_net_thread.start(_net_worker)


func _exit_tree() -> void:
	if _net_thread and _net_thread.is_started():
		_net_thread.wait_to_finish()


# --- Resources ---------------------------------------------------------------------------

func _queue_resources() -> void:
	var paths: Array[String] = []
	for c in CharacterDB.CHARACTERS:
		paths.append(CharacterDB.model_path(str(c["id"])))
		for o in CharacterDB.OUTFITS:
			paths.append(CharacterDB.thumb(str(c["id"]), str(o["id"])))
	for id in WeaponDB.ids():
		paths.append(WeaponDB.model_path(str(id)))
		paths.append(CharacterDB.weapon_thumb(str(id)))
	for scene in ["res://scenes/onboarding.tscn", "res://scenes/lobby.tscn", "res://scenes/training.tscn"]:
		paths.append(scene)
	for p in paths:
		if ResourceLoader.exists(p) and not SceneRouter.preloaded.has(p):
			_queue.append(p)
	_total = maxi(_queue.size(), 1)
	# Request a few at a time so the progress bar moves smoothly.
	for i in mini(6, _queue.size()):
		ResourceLoader.load_threaded_request(_queue[i], "", true)


func _poll_resources() -> void:
	if _resources_done:
		return
	var pending := 0
	for i in range(_queue.size() - 1, -1, -1):
		var p := _queue[i]
		var st := ResourceLoader.load_threaded_get_status(p)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			SceneRouter.preloaded[p] = ResourceLoader.load_threaded_get(p)
			_queue.remove_at(i)
			_loaded += 1
		elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_queue.remove_at(i)
			_loaded += 1
		elif st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			pending += 1
	# Keep up to 6 loads in flight.
	var started := 0
	for p in _queue:
		if pending + started >= 6:
			break
		if ResourceLoader.load_threaded_get_status(p) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_request(p, "", true)
			started += 1
	if _queue.is_empty():
		_resources_done = true


# --- Network test (worker thread) ----------------------------------------------------------

func _net_worker() -> void:
	var deadline := Time.get_ticks_msec() + NET_TIMEOUT_MS
	var http := _open_connection(SPEED_HOST, deadline)
	if http == null:
		# Speed-test host unreachable: at least measure latency against another host.
		http = _open_connection(FALLBACK_HOST, deadline)
		if http == null:
			_finish_net.call_deferred(false, 0.0, 0.0)
			return
		var fb_headers := PackedStringArray(["User-Agent: AurumGame/1.0"])
		var fb_best := INF
		for i in 3:
			var t := Time.get_ticks_usec()
			if _http_get(http, "/generate_204", fb_headers, deadline, false) < 0:
				break
			fb_best = minf(fb_best, (Time.get_ticks_usec() - t) / 1000.0)
		http.close()
		_finish_net.call_deferred(fb_best != INF, 0.0, fb_best if fb_best != INF else 0.0)
		return
	var headers := PackedStringArray(["User-Agent: AurumGame/1.0", "Accept: */*"])
	# Latency: three tiny requests on the open connection, keep the best.
	var best := INF
	for i in 3:
		var t0 := Time.get_ticks_usec()
		if _http_get(http, "/__down?bytes=0", headers, deadline, false) < 0:
			break
		best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
	if best == INF:
		_finish_net.call_deferred(false, 0.0, 0.0)
		return
	_set_phase.call_deferred("Measuring download speed")
	var t1 := Time.get_ticks_usec()
	var got := _http_get(http, "/__down?bytes=%d" % DOWNLOAD_BYTES, headers, deadline, true)
	var secs := maxf((Time.get_ticks_usec() - t1) / 1000000.0, 0.001)
	http.close()
	if got <= 0:
		_finish_net.call_deferred(true, 0.0, best)
		return
	_finish_net.call_deferred(true, got * 8.0 / secs / 1000000.0, best)


func _open_connection(host: String, deadline: int) -> HTTPClient:
	var http := HTTPClient.new()
	if http.connect_to_host(host, 443, TLSOptions.client()) != OK:
		return null
	while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
		http.poll()
		OS.delay_usec(500)
		if Time.get_ticks_msec() > deadline:
			break
	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		return null
	return http


func _set_phase(text: String) -> void:
	_net_phase = text


## Blocking GET on an open connection; returns body bytes read (-1 on error).
func _http_get(http: HTTPClient, path: String, headers: PackedStringArray, deadline: int, count: bool) -> int:
	if http.request(HTTPClient.METHOD_GET, path, headers) != OK:
		return -1
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		OS.delay_usec(200)
		if Time.get_ticks_msec() > deadline:
			return -1
	var total := 0
	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()
		var chunk := http.read_response_body_chunk()
		if chunk.size() == 0:
			OS.delay_usec(200)
		else:
			total += chunk.size()
			if count:
				_net_bytes = total
		if Time.get_ticks_msec() > deadline:
			break
	if http.get_status() != HTTPClient.STATUS_CONNECTED and http.get_status() != HTTPClient.STATUS_BODY and total == 0:
		return -1
	return total


func _finish_net(ok: bool, mbps: float, ping: float) -> void:
	_net_ok = ok
	_net_mbps = mbps
	_net_ping = ping
	_net_done = true
	GameState.net_online = ok
	GameState.net_mbps = mbps
	GameState.net_ping_ms = ping


# --- Flow ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_poll_resources()
	if _resources_done and _net_done and not _online_started:
		_online_started = true
		_connect_online()
	var res := float(_loaded) / _total
	var progress := res * 0.7 + (0.15 if _net_done else 0.0) + (0.15 if _online_done else 0.0)
	_shown = move_toward(_shown, progress, delta * 0.9)
	_bar.value = _shown
	_percent.text = "%d%%" % int(round(_shown * 100.0))
	if not _resources_done:
		_status.text = "Loading game resources  %d / %d" % [_loaded, _total]
	elif not _net_done:
		_status.text = _net_phase
	elif not _online_done:
		_status.text = "Connecting to Aurum servers"
	else:
		_status.text = "Ready"
	_update_net_label()
	if _online_done and _shown >= 0.999 and not _leaving and Time.get_ticks_msec() - _started_at > 2500:
		_leave()


func _connect_online() -> void:
	if _net_ok:
		await Online.connect_account()
	_online_done = true


func _update_net_label() -> void:
	if not _net_done:
		var live := ""
		if _net_bytes > 0:
			live = "  ·  %.1f MB" % (_net_bytes / 1000000.0)
		_net_label.text = "Internet: " + _net_phase.to_lower() + live
		_net_bars.level = -1
	elif not _net_ok:
		_net_label.text = "Internet: offline  ·  online features unavailable"
		_net_bars.level = 0
	else:
		var level := 1
		var quality := "Weak"
		if _net_ping < 70.0 and (_net_mbps > 10.0 or _net_mbps == 0.0):
			level = 3
			quality = "Excellent"
		elif _net_ping < 140.0 and _net_mbps > 3.0:
			level = 2
			quality = "Good"
		var online := ""
		if _online_done:
			online = "  ·  " + ("online" if Online.is_online() else "servers unreachable")
		var speed := "%.1f Mbps" % _net_mbps if _net_mbps > 0.0 else "speed n/a"
		_net_label.text = "%s  ·  %s  ·  %d ms%s" % [quality, speed, int(_net_ping), online]
		_net_bars.level = level
	_net_bars.queue_redraw()


func _leave() -> void:
	_leaving = true
	var target := GameState.entry_scene()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.45)
	tw.tween_callback(_open.bind(target))


func _open(target: String) -> void:
	var cached: Variant = SceneRouter.preloaded.get(target)
	if cached is PackedScene:
		get_tree().change_scene_to_packed(cached)
	else:
		get_tree().change_scene_to_file(target)


# --- UI ------------------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := TextureRect.new()
	bg.texture = Router.background_texture()
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dust := CPUParticles2D.new()
	dust.amount = 70
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(1100, 600)
	dust.position = Vector2(960, 540)
	dust.direction = Vector2(1, -0.3)
	dust.spread = 25.0
	dust.gravity = Vector2.ZERO
	dust.initial_velocity_min = 8.0
	dust.initial_velocity_max = 28.0
	dust.scale_amount_min = 1.5
	dust.scale_amount_max = 4.0
	dust.color = Color(1.0, 0.8, 0.35, 0.35)
	add_child(dust)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_bottom = -120
	var title := Router._label("AURUM", 170, GOLD, 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := Router._label("BATTLE ROYALE", 38, Color(1, 1, 1, 0.8), 24)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	_bar = Router.make_bar()
	add_child(_bar)
	_bar.anchor_left = 0.06
	_bar.anchor_right = 0.94
	_bar.anchor_top = 1.0
	_bar.anchor_bottom = 1.0
	_bar.offset_top = -92
	_bar.offset_bottom = -84
	_status = Router._label("", 26, Color(1, 1, 1, 0.8))
	add_child(_status)
	_status.anchor_left = 0.06
	_status.anchor_right = 0.6
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.offset_top = -140
	_status.offset_bottom = -100
	_percent = Router._label("0%", 30, GOLD)
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_percent)
	_percent.anchor_left = 0.6
	_percent.anchor_right = 0.94
	_percent.anchor_top = 1.0
	_percent.anchor_bottom = 1.0
	_percent.offset_top = -142
	_percent.offset_bottom = -100
	_net_bars = NetBars.new()
	add_child(_net_bars)
	_net_bars.anchor_left = 1.0
	_net_bars.anchor_right = 1.0
	_net_bars.offset_left = -96
	_net_bars.offset_right = -56
	_net_bars.offset_top = 44
	_net_bars.offset_bottom = 80
	_net_label = Router._label("", 24, Color(1, 1, 1, 0.75))
	_net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_net_label)
	_net_label.anchor_left = 1.0
	_net_label.anchor_right = 1.0
	_net_label.offset_left = -980
	_net_label.offset_right = -110
	_net_label.offset_top = 46
	_net_label.offset_bottom = 80
	var foot := Router._label("v0.5  ·  Midnight Sand Studios  ·  Developed by Mujahid", 22, Color(1, 1, 1, 0.4))
	add_child(foot)
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.offset_left = 0
	foot.offset_right = 900
	foot.anchor_left = 0.06
	foot.offset_top = -60
	foot.offset_bottom = -30


## Signal-strength bars (-1 = measuring, 0 = offline, 1..3 = quality).
class NetBars extends Control:
	var level := -1
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if level < 0:
			queue_redraw()

	func _draw() -> void:
		for i in 3:
			var h := size.y * (0.4 + 0.3 * i)
			var r := Rect2(Vector2(i * size.x / 3.0, size.y - h), Vector2(size.x / 3.0 - 4.0, h))
			var on := i < level
			var c := Color(1.0, 0.78, 0.1) if on else Color(1, 1, 1, 0.18)
			if level == 0:
				c = Color(0.9, 0.25, 0.2, 0.8) if i == 0 else Color(1, 1, 1, 0.18)
			elif level < 0:
				c = Color(1, 1, 1, 0.25 + 0.5 * maxf(0.0, sin(_t * 5.0 - i)))
			draw_rect(r, c)
