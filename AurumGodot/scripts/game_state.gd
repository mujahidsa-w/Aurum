extends Node
## Global player / lobby state. Registered as the "GameState" autoload.
## Everything the lobby shows (currencies, selected mode, graphics, outfit...)
## lives here and is saved to user:// so it survives restarts.

signal currency_changed
signal mode_changed
signal quality_changed
signal region_changed
signal outfit_changed
signal missions_changed
signal squad_changed

const SAVE_PATH := "user://aurum_save.cfg"

const QUALITY_NAMES := ["Smooth", "Balanced", "HD", "Ultra HD"]
const QUALITY_TAGS := ["SMOOTH", "BALANCED", "HD", "UHD"]
const FPS_OPTIONS := [30, 60, 90, 120]
const REGIONS := [
	{"name": "Europe", "ping": 38},
	{"name": "Middle East", "ping": 26},
	{"name": "Asia", "ping": 84},
	{"name": "North America", "ping": 118},
]
const MODES := ["Classic", "Arcade", "Arena"]
const MAPS := [
	{"name": "Vis Island", "info": "18x9 km  ·  Croatia (real)", "color": Color(0.27, 0.52, 0.33)},
	{"name": "Dunewatch", "info": "8x8 km  ·  Desert", "color": Color(0.74, 0.55, 0.29)},
	{"name": "Frostline", "info": "6x6 km  ·  Snow", "color": Color(0.52, 0.66, 0.8)},
	{"name": "Verdant", "info": "4x4 km  ·  Jungle", "color": Color(0.16, 0.42, 0.26)},
]
const SQUADS := [
	{"name": "Solo", "size": 1},
	{"name": "Duo", "size": 2},
	{"name": "Squad", "size": 4},
]

var player_name := "MujahidSA"
var level := 72
var xp_ratio := 0.28
var gold := 2650
var credits := 280
var mode_index := 0
var ranked := true
var map_index := 0
var squad_index := 2
var fpp := false
var quality := 2
var fps_index := 1
var region_index := 0
var outfit_index := 0
var rifle_skin_index := 0
var show_fps := false
var friends_online := 0
var friends_total := 10
var missions: Array = []
var squad_members: Array = []
var clan_name := ""
var joined_events: Array = []
var installed_packs: Array = []
var workshop_notify := false
var season_claimed := false
var fullscreen := true

const SQUAD_SLOTS := 3


func _init() -> void:
	missions = [
		{"title": "Play 1 Classic match", "progress": 1, "goal": 1, "reward": 120, "claimed": false},
		{"title": "Drive a vehicle for 2 km", "progress": 2, "goal": 2, "reward": 80, "claimed": false},
		{"title": "Get 5 eliminations", "progress": 3, "goal": 5, "reward": 150, "claimed": false},
		{"title": "Invite a friend to your squad", "progress": 0, "goal": 1, "reward": 50, "claimed": false},
	]


func _ready() -> void:
	load_state()
	Engine.max_fps = FPS_OPTIONS[fps_index]
	apply_window_mode()


# --- Text helpers ---------------------------------------------------------

func mode_title() -> String:
	return "%s - %s" % [MODES[mode_index], "Ranked" if ranked else "Casual"]


func mode_subtitle() -> String:
	var squad: Dictionary = SQUADS[squad_index]
	return "%d %s  |  %s" % [int(squad["size"]), "FPP" if fpp else "TPP", map_name()]


func map_name() -> String:
	var m: Dictionary = MAPS[map_index]
	return str(m["name"])


func region_name() -> String:
	var r: Dictionary = REGIONS[region_index]
	return str(r["name"])


func region_ping() -> int:
	var r: Dictionary = REGIONS[region_index]
	return int(r["ping"])


static func fmt_int(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


# --- Mutators -------------------------------------------------------------

func add_gold(amount: int) -> void:
	gold = maxi(gold + amount, 0)
	currency_changed.emit()
	save_state()


func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	add_gold(-amount)
	return true


func spend_credits(amount: int) -> bool:
	if credits < amount:
		return false
	credits -= amount
	currency_changed.emit()
	save_state()
	return true


func set_mode(index: int) -> void:
	mode_index = clampi(index, 0, MODES.size() - 1)
	_mode_updated()


func set_map(index: int) -> void:
	map_index = clampi(index, 0, MAPS.size() - 1)
	_mode_updated()


func set_squad(index: int) -> void:
	squad_index = clampi(index, 0, SQUADS.size() - 1)
	_mode_updated()


func set_fpp(value: bool) -> void:
	fpp = value
	_mode_updated()


func set_ranked(value: bool) -> void:
	ranked = value
	_mode_updated()


func _mode_updated() -> void:
	mode_changed.emit()
	save_state()


func set_quality(index: int) -> void:
	quality = clampi(index, 0, QUALITY_NAMES.size() - 1)
	quality_changed.emit()
	save_state()


func set_fps(index: int) -> void:
	fps_index = clampi(index, 0, FPS_OPTIONS.size() - 1)
	Engine.max_fps = FPS_OPTIONS[fps_index]
	save_state()


func set_region(index: int) -> void:
	region_index = clampi(index, 0, REGIONS.size() - 1)
	region_changed.emit()
	save_state()


func set_outfit(index: int) -> void:
	outfit_index = index
	outfit_changed.emit()
	save_state()


func set_rifle_skin(index: int) -> void:
	rifle_skin_index = index
	outfit_changed.emit()
	save_state()


func has_claimable_missions() -> bool:
	for m in missions:
		if not m["claimed"] and int(m["progress"]) >= int(m["goal"]):
			return true
	return false


func claim_mission(index: int) -> int:
	if index < 0 or index >= missions.size():
		return 0
	var m: Dictionary = missions[index]
	if m["claimed"] or int(m["progress"]) < int(m["goal"]):
		return 0
	m["claimed"] = true
	var reward := int(m["reward"])
	gold += reward
	currency_changed.emit()
	missions_changed.emit()
	save_state()
	return reward


func add_squad_member(member: String) -> bool:
	if squad_members.size() >= SQUAD_SLOTS or squad_members.has(member):
		return false
	squad_members.append(member)
	squad_changed.emit()
	return true


func remove_squad_member(index: int) -> void:
	if index >= 0 and index < squad_members.size():
		squad_members.remove_at(index)
		squad_changed.emit()


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply_window_mode()
	save_state()


func apply_window_mode() -> void:
	if OS.has_feature("mobile") or OS.has_feature("web"):
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


# --- Persistence ----------------------------------------------------------

func save_state() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "gold", gold)
	cfg.set_value("player", "credits", credits)
	cfg.set_value("lobby", "mode_index", mode_index)
	cfg.set_value("lobby", "ranked", ranked)
	cfg.set_value("lobby", "map_index", map_index)
	cfg.set_value("lobby", "squad_index", squad_index)
	cfg.set_value("lobby", "fpp", fpp)
	cfg.set_value("settings", "quality", quality)
	cfg.set_value("settings", "fps_index", fps_index)
	cfg.set_value("settings", "region_index", region_index)
	cfg.set_value("settings", "show_fps", show_fps)
	cfg.set_value("outfit", "outfit_index", outfit_index)
	cfg.set_value("outfit", "rifle_skin_index", rifle_skin_index)
	cfg.set_value("social", "clan_name", clan_name)
	cfg.set_value("social", "joined_events", joined_events)
	cfg.set_value("settings", "installed_packs", installed_packs)
	cfg.set_value("settings", "workshop_notify", workshop_notify)
	cfg.set_value("settings", "fullscreen", fullscreen)
	cfg.set_value("player", "season_claimed", season_claimed)
	var claimed: Array = []
	for m in missions:
		claimed.append(bool(m["claimed"]))
	cfg.set_value("missions", "claimed", claimed)
	cfg.save(SAVE_PATH)


func load_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	gold = int(cfg.get_value("player", "gold", gold))
	credits = int(cfg.get_value("player", "credits", credits))
	mode_index = clampi(int(cfg.get_value("lobby", "mode_index", mode_index)), 0, MODES.size() - 1)
	ranked = bool(cfg.get_value("lobby", "ranked", ranked))
	map_index = clampi(int(cfg.get_value("lobby", "map_index", map_index)), 0, MAPS.size() - 1)
	squad_index = clampi(int(cfg.get_value("lobby", "squad_index", squad_index)), 0, SQUADS.size() - 1)
	fpp = bool(cfg.get_value("lobby", "fpp", fpp))
	quality = clampi(int(cfg.get_value("settings", "quality", quality)), 0, QUALITY_NAMES.size() - 1)
	fps_index = clampi(int(cfg.get_value("settings", "fps_index", fps_index)), 0, FPS_OPTIONS.size() - 1)
	region_index = clampi(int(cfg.get_value("settings", "region_index", region_index)), 0, REGIONS.size() - 1)
	show_fps = bool(cfg.get_value("settings", "show_fps", show_fps))
	outfit_index = int(cfg.get_value("outfit", "outfit_index", outfit_index))
	rifle_skin_index = int(cfg.get_value("outfit", "rifle_skin_index", rifle_skin_index))
	clan_name = str(cfg.get_value("social", "clan_name", clan_name))
	joined_events = cfg.get_value("social", "joined_events", [])
	installed_packs = cfg.get_value("settings", "installed_packs", [])
	workshop_notify = bool(cfg.get_value("settings", "workshop_notify", workshop_notify))
	fullscreen = bool(cfg.get_value("settings", "fullscreen", fullscreen))
	season_claimed = bool(cfg.get_value("player", "season_claimed", season_claimed))
	var claimed: Array = cfg.get_value("missions", "claimed", [])
	for i in mini(claimed.size(), missions.size()):
		missions[i]["claimed"] = bool(claimed[i])
