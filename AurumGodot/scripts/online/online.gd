extends Node
## Autoload "Online": Firebase Authentication (anonymous guest or Google) + Realtime Database
## over REST. Gives every player a permanent 8-digit player ID, keeps all progress in the
## cloud (restored on any device that signs in with the same account), friends by ID with
## requests, presence (online / last seen) and squad invites between friends.
##
## Database layout (rules in firebase/database.rules.json):
##   users/<uid>/save          full progress      (private)
##   users/<uid>/player_id     8-digit ID         (private)
##   profiles/<uid>            name, level, character, player_id, online, last_seen (public to players)
##   ids/<player_id>           -> uid             (write-once)
##   friends/<uid>/<uid2>      true
##   requests/<to>/<from>      {name, player_id, at}
##   invites/<to>/<from>       {name, player_id, at}   squad invite
##   joins/<to>/<from>         {name, player_id, at}   "I joined your squad"

signal status_changed
signal friends_changed
signal requests_changed
signal invites_changed
## Progress was replaced by a newer cloud save.
signal restored

const Config := preload("res://scripts/online/firebase_config.gd")
const STORE := "user://online.cfg"
const POLL_SECONDS := 15.0
const HEARTBEAT_SECONDS := 60.0
const ONLINE_WINDOW_MS := 3 * 60 * 1000

var uid := ""
var player_id := ""
var provider := ""
var last_error := ""
## [{uid, name, player_id, level, character, online, last_seen}]
var friends: Array = []
## [{uid, name, player_id}]
var requests: Array = []
var invites: Array = []

var _id_token := ""
var _refresh_token := ""
var _token_expiry := 0
var _online := false
var _busy := false
var _poll_t := 0.0
var _beat_t := 0.0
var _push_t := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_store()
	GameState.saved.connect(_on_saved)


func is_online() -> bool:
	return _online


func status_text() -> String:
	if _online:
		return "Online"
	if not GameState.net_online:
		return "Offline (no internet)"
	if last_error != "":
		return "Offline (%s)" % last_error
	return "Offline"


# --- Account -------------------------------------------------------------------------------

## Called on the startup screen: restores the Firebase session for an existing account.
func connect_account() -> void:
	if _busy or not Config.is_configured() or GameState.auth_provider == "":
		return
	_busy = true
	var ok := false
	if _refresh_token != "":
		ok = await _refresh()
	if not ok and GameState.auth_provider == "guest":
		ok = await _sign_up_anonymous()
	if ok:
		await _after_sign_in()
	_busy = false


## Signs in with a Google ID token from the device sign-in flow.
func sign_in_google(google_id_token: String) -> bool:
	if not Config.is_configured() or google_id_token == "":
		return false
	_busy = true
	var body := {
		"postBody": "id_token=%s&providerId=google.com" % google_id_token,
		"requestUri": "http://localhost",
		"returnIdpCredential": true,
		"returnSecureToken": true,
	}
	var r := await _request(_auth_url("accounts:signInWithIdp"), HTTPClient.METHOD_POST, body)
	var ok: bool = bool(r["ok"]) and _take_tokens(r["data"], "idToken", "refreshToken", "localId", "expiresIn")
	if ok:
		provider = "google"
		await _after_sign_in()
	else:
		last_error = _error_of(r)
	_busy = false
	return ok


func sign_in_guest() -> bool:
	if not Config.is_configured():
		return false
	_busy = true
	var ok := await _sign_up_anonymous()
	if ok:
		await _after_sign_in()
	_busy = false
	return ok


func sign_out() -> void:
	if _online:
		_set_presence(false)
	uid = ""
	player_id = ""
	provider = ""
	_id_token = ""
	_refresh_token = ""
	_online = false
	friends.clear()
	requests.clear()
	invites.clear()
	_save_store()
	status_changed.emit()


func _sign_up_anonymous() -> bool:
	var r := await _request(_auth_url("accounts:signUp"), HTTPClient.METHOD_POST, {"returnSecureToken": true})
	var ok: bool = bool(r["ok"]) and _take_tokens(r["data"], "idToken", "refreshToken", "localId", "expiresIn")
	if ok:
		provider = "guest"
	else:
		last_error = _error_of(r)
	return ok


func _refresh() -> bool:
	var form := "grant_type=refresh_token&refresh_token=" + _refresh_token.uri_encode()
	var r := await _request("https://securetoken.googleapis.com/v1/token?key=" + Config.API_KEY, HTTPClient.METHOD_POST, form, PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]))
	var ok: bool = bool(r["ok"]) and _take_tokens(r["data"], "id_token", "refresh_token", "user_id", "expires_in")
	if not ok:
		last_error = _error_of(r)
	return ok


func _take_tokens(data: Variant, id_key: String, refresh_key: String, uid_key: String, exp_key: String) -> bool:
	if not (data is Dictionary) or not data.has(id_key):
		return false
	var d: Dictionary = data
	_id_token = str(d[id_key])
	_refresh_token = str(d.get(refresh_key, _refresh_token))
	uid = str(d.get(uid_key, uid))
	_token_expiry = Time.get_ticks_msec() + (int(d.get(exp_key, 3600)) - 120) * 1000
	_save_store()
	return uid != ""


func _ensure_token() -> bool:
	if _id_token == "":
		return false
	if Time.get_ticks_msec() < _token_expiry:
		return true
	return await _refresh()


func _after_sign_in() -> void:
	last_error = ""
	await _ensure_player_id()
	await _sync_save()
	_online = true
	await _set_presence(true)
	_poll_t = POLL_SECONDS
	_beat_t = 0.0
	status_changed.emit()
	await poll()


## Gives the account a unique 8-digit player ID (kept forever).
func _ensure_player_id() -> void:
	if player_id != "":
		return
	var existing: Variant = await _db_get("users/%s/player_id" % uid)
	if existing != null and str(existing) != "":
		player_id = str(existing)
		_save_store()
		return
	for attempt in 6:
		var candidate := str(randi_range(10000000, 99999999))
		var r := await _db("ids/" + candidate, HTTPClient.METHOD_PUT, uid)
		if r["ok"]:
			player_id = candidate
			await _db("users/%s/player_id" % uid, HTTPClient.METHOD_PUT, player_id)
			_save_store()
			return


# --- Cloud save ----------------------------------------------------------------------------

## Newest copy wins: restores the cloud save if it is newer, otherwise uploads this one.
func _sync_save() -> void:
	var remote: Variant = await _db_get("users/%s/save" % uid)
	if remote is Dictionary:
		var meta: Variant = (remote as Dictionary).get("meta", {})
		var remote_at := int((meta as Dictionary).get("updated_at", 0)) if meta is Dictionary else 0
		if remote_at > GameState.updated_at:
			GameState.import_save(remote)
			restored.emit()
			return
	await _upload_save()


func push_save() -> void:
	_push_t = 0.1


func _on_saved() -> void:
	# Debounce: many quick changes become one upload.
	if _push_t < 0.0:
		_push_t = 2.0


func _upload_save() -> void:
	if uid == "" or not await _ensure_token():
		return
	await _db("users/%s/save" % uid, HTTPClient.METHOD_PUT, GameState.export_save())
	await _update_profile()


func _update_profile() -> void:
	var p := {
		"name": GameState.player_name,
		"level": GameState.level,
		"character": GameState.character_id,
		"player_id": player_id,
		"online": _online,
		"last_seen": {".sv": "timestamp"},
	}
	await _db("profiles/" + uid, HTTPClient.METHOD_PATCH, p)


func _set_presence(on: bool) -> void:
	if uid == "":
		return
	await _db("profiles/" + uid, HTTPClient.METHOD_PATCH, {
		"online": on, "last_seen": {".sv": "timestamp"}, "name": GameState.player_name,
		"level": GameState.level, "character": GameState.character_id, "player_id": player_id,
	})


# --- Friends -------------------------------------------------------------------------------

## Sends a friend request to the player with this ID. Returns "" or an error message.
func send_friend_request(target_id: String) -> String:
	target_id = target_id.strip_edges()
	if not _online:
		return "You are offline"
	if not target_id.is_valid_int() or target_id.length() != 8:
		return "A player ID has 8 digits"
	if target_id == player_id:
		return "That is your own ID"
	var target: Variant = await _db_get("ids/" + target_id)
	if target == null:
		return "No player with ID %s" % target_id
	var target_uid := str(target)
	for f in friends:
		if str(f["uid"]) == target_uid:
			return "You are already friends"
	var r := await _db("requests/%s/%s" % [target_uid, uid], HTTPClient.METHOD_PUT, _me_card())
	return "" if r["ok"] else "Could not send the request (%s)" % _error_of(r)


func accept_request(from_uid: String) -> bool:
	var r := await _db("", HTTPClient.METHOD_PATCH, {
		"friends/%s/%s" % [uid, from_uid]: true,
		"friends/%s/%s" % [from_uid, uid]: true,
		"requests/%s/%s" % [uid, from_uid]: null,
	})
	await poll()
	return r["ok"]


func decline_request(from_uid: String) -> void:
	await _db("requests/%s/%s" % [uid, from_uid], HTTPClient.METHOD_DELETE)
	await poll()


func remove_friend(friend_uid: String) -> void:
	await _db("", HTTPClient.METHOD_PATCH, {
		"friends/%s/%s" % [uid, friend_uid]: null,
		"friends/%s/%s" % [friend_uid, uid]: null,
	})
	await poll()


func invite_to_squad(friend_uid: String) -> bool:
	var r := await _db("invites/%s/%s" % [friend_uid, uid], HTTPClient.METHOD_PUT, _me_card())
	return r["ok"]


## Accepts a squad invite: the inviter appears in this squad and is told we joined.
func accept_invite(from_uid: String, from_name: String) -> void:
	await _db("", HTTPClient.METHOD_PATCH, {
		"invites/%s/%s" % [uid, from_uid]: null,
		"joins/%s/%s" % [from_uid, uid]: _me_card(),
	})
	GameState.add_squad_member(from_name)
	await poll()


func decline_invite(from_uid: String) -> void:
	await _db("invites/%s/%s" % [uid, from_uid], HTTPClient.METHOD_DELETE)
	await poll()


func friends_online_count() -> int:
	var n := 0
	for f in friends:
		if bool(f["online"]):
			n += 1
	return n


## Refreshes friends (with presence), friend requests, squad invites and joins.
func poll() -> void:
	if not _online or uid == "" or not await _ensure_token():
		return
	var ids: Variant = await _db_get("friends/" + uid)
	var list: Array = []
	if ids is Dictionary:
		for fuid in (ids as Dictionary).keys():
			var prof: Variant = await _db_get("profiles/" + str(fuid))
			if prof is Dictionary:
				var p: Dictionary = prof
				var seen := int(p.get("last_seen", 0))
				var now := int(Time.get_unix_time_from_system() * 1000.0)
				list.append({
					"uid": str(fuid), "name": str(p.get("name", "Player")), "player_id": str(p.get("player_id", "")),
					"level": int(p.get("level", 1)), "character": str(p.get("character", "")), "last_seen": seen,
					"online": bool(p.get("online", false)) and now - seen < ONLINE_WINDOW_MS,
				})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["online"]) > int(b["online"]) or (a["online"] == b["online"] and str(a["name"]) < str(b["name"])))
	friends = list
	GameState.friends_total = friends.size()
	GameState.friends_online = friends_online_count()
	friends_changed.emit()
	requests = _cards(await _db_get("requests/" + uid))
	requests_changed.emit()
	invites = _cards(await _db_get("invites/" + uid))
	invites_changed.emit()
	var joins := _cards(await _db_get("joins/" + uid))
	for j in joins:
		GameState.add_squad_member(str(j["name"]))
		await _db("joins/%s/%s" % [uid, str(j["uid"])], HTTPClient.METHOD_DELETE)


func _cards(data: Variant) -> Array:
	var out: Array = []
	if data is Dictionary:
		for k in (data as Dictionary).keys():
			var v: Variant = (data as Dictionary)[k]
			if v is Dictionary:
				out.append({"uid": str(k), "name": str((v as Dictionary).get("name", "Player")), "player_id": str((v as Dictionary).get("player_id", ""))})
	return out


func _me_card() -> Dictionary:
	return {"name": GameState.player_name, "player_id": player_id, "at": {".sv": "timestamp"}}


## "Online", "5 min ago", "3 h ago", "2 days ago".
static func last_seen_text(friend: Dictionary) -> String:
	if bool(friend.get("online", false)):
		return "Online"
	var seen := int(friend.get("last_seen", 0))
	if seen <= 0:
		return "Offline"
	var mins := int((Time.get_unix_time_from_system() * 1000.0 - seen) / 60000.0)
	if mins < 60:
		return "Last seen %d min ago" % maxi(mins, 1)
	if mins < 60 * 24:
		return "Last seen %d h ago" % int(mins / 60.0)
	return "Last seen %d days ago" % int(mins / 1440.0)


# --- Loop ----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _push_t >= 0.0:
		_push_t -= delta
		if _push_t < 0.0 and _online:
			_upload_save()
	if not _online:
		return
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = POLL_SECONDS
		poll()
	_beat_t -= delta
	if _beat_t <= 0.0:
		_beat_t = HEARTBEAT_SECONDS
		_set_presence(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if _online:
			_set_presence(false)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		if _online:
			_set_presence(true)
			poll()


# --- REST helpers ------------------------------------------------------------------------

func _auth_url(method: String) -> String:
	return "https://identitytoolkit.googleapis.com/v1/%s?key=%s" % [method, Config.API_KEY]


func _db_url(path: String) -> String:
	return "%s/%s.json?auth=%s" % [Config.DATABASE_URL, path, _id_token]


func _db(path: String, method: int, body: Variant = null) -> Dictionary:
	if not await _ensure_token():
		return {"ok": false, "code": 401, "data": null}
	return await _request(_db_url(path), method, body)


func _db_get(path: String) -> Variant:
	var r := await _db(path, HTTPClient.METHOD_GET)
	return r["data"] if r["ok"] else null


func _request(url: String, method: int, body: Variant = null, headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 12.0
	add_child(req)
	var data := ""
	var h := headers
	if body != null:
		if body is String:
			data = body
		else:
			data = JSON.stringify(body)
			if h.is_empty():
				h = PackedStringArray(["Content-Type: application/json"])
	if req.request(url, h, method, data) != OK:
		req.queue_free()
		return {"ok": false, "code": 0, "data": null}
	var res: Array = await req.request_completed
	req.queue_free()
	var code := int(res[1])
	var text := (res[3] as PackedByteArray).get_string_from_utf8()
	var parsed: Variant = null
	if text != "":
		parsed = JSON.parse_string(text)
	var ok := int(res[0]) == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	return {"ok": ok, "code": code, "data": parsed}


func _error_of(r: Dictionary) -> String:
	var d: Variant = r.get("data")
	if d is Dictionary:
		var e: Variant = (d as Dictionary).get("error")
		if e is Dictionary:
			return str((e as Dictionary).get("message", "error"))
		if e != null:
			return str(e)
	if int(r.get("code", 0)) == 0:
		return "no connection"
	return "HTTP %d" % int(r.get("code", 0))


func _load_store() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(STORE) != OK:
		return
	uid = str(cfg.get_value("auth", "uid", ""))
	_refresh_token = str(cfg.get_value("auth", "refresh_token", ""))
	provider = str(cfg.get_value("auth", "provider", ""))
	player_id = str(cfg.get_value("auth", "player_id", ""))


func _save_store() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "uid", uid)
	cfg.set_value("auth", "refresh_token", _refresh_token)
	cfg.set_value("auth", "provider", provider)
	cfg.set_value("auth", "player_id", player_id)
	cfg.save(STORE)
