extends Node
## Google sign-in with the OAuth 2.0 device flow: the system browser (Safari on iPhone,
## Chrome/default browser on Android, desktop browser on PC) opens Google's page, the player
## chooses any Google account (or adds another) and confirms; the game polls for the result.
## No native plugin is needed, so it works the same on every platform.

signal code_ready(user_code: String, url: String)
signal signed_in(profile: Dictionary)
signal failed(reason: String)

const Config := preload("res://scripts/onboarding/google_config.gd")
const DEVICE_URL := "https://oauth2.googleapis.com/device/code"
const TOKEN_URL := "https://oauth2.googleapis.com/token"
const FORM := ["Content-Type: application/x-www-form-urlencoded"]

var verification_url := "https://www.google.com/device"
var user_code := ""

var _http: HTTPRequest
var _device_code := ""
var _interval := 5.0
var _wait := 0.0
var _deadline := 0
var _polling := false
var _busy := false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)


func start() -> void:
	if not Config.is_configured():
		failed.emit("not_configured")
		return
	cancel()
	_busy = true
	var body := "client_id=%s&scope=%s" % [Config.CLIENT_ID.uri_encode(), Config.SCOPES.uri_encode()]
	_http.request_completed.connect(_on_device_code, CONNECT_ONE_SHOT)
	var err := _http.request(DEVICE_URL, FORM, HTTPClient.METHOD_POST, body)
	if err != OK:
		_busy = false
		failed.emit("network")


func open_browser() -> void:
	DisplayServer.clipboard_set(user_code)
	OS.shell_open(verification_url)


func cancel() -> void:
	_polling = false
	if _busy:
		_http.cancel_request()
		_busy = false
	for c in _http.request_completed.get_connections():
		_http.request_completed.disconnect(c["callable"])


func _on_device_code(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or typeof(data) != TYPE_DICTIONARY:
		failed.emit("network" if result != HTTPRequest.RESULT_SUCCESS else "rejected")
		return
	var d: Dictionary = data
	_device_code = str(d.get("device_code", ""))
	user_code = str(d.get("user_code", ""))
	verification_url = str(d.get("verification_url", d.get("verification_uri", verification_url)))
	_interval = float(d.get("interval", 5))
	_deadline = Time.get_ticks_msec() + int(d.get("expires_in", 1800)) * 1000
	_wait = _interval
	_polling = true
	code_ready.emit(user_code, verification_url)
	open_browser()


func _process(delta: float) -> void:
	if not _polling or _busy:
		return
	if Time.get_ticks_msec() > _deadline:
		_polling = false
		failed.emit("expired")
		return
	_wait -= delta
	if _wait <= 0.0:
		_wait = _interval
		_poll()


func _poll() -> void:
	_busy = true
	var body := "client_id=%s&client_secret=%s&device_code=%s&grant_type=%s" % [
		Config.CLIENT_ID.uri_encode(), Config.CLIENT_SECRET.uri_encode(), _device_code.uri_encode(),
		"urn:ietf:params:oauth:grant-type:device_code".uri_encode()]
	_http.request_completed.connect(_on_token, CONNECT_ONE_SHOT)
	if _http.request(TOKEN_URL, FORM, HTTPClient.METHOD_POST, body) != OK:
		_busy = false


func _on_token(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		return # transient network issue: keep polling
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		return
	var d: Dictionary = data
	if code == 200 and d.has("id_token"):
		_polling = false
		var claims := decode_jwt(str(d["id_token"]))
		signed_in.emit({
			"email": str(claims.get("email", "")),
			"name": str(claims.get("name", claims.get("given_name", ""))),
			"picture": str(claims.get("picture", "")),
		})
		return
	match str(d.get("error", "")):
		"authorization_pending":
			pass
		"slow_down":
			_interval += 5.0
		"access_denied":
			_polling = false
			failed.emit("denied")
		"expired_token":
			_polling = false
			failed.emit("expired")
		_:
			_polling = false
			failed.emit("rejected")


## Reads the claims (email, name, picture) from a Google ID token.
static func decode_jwt(token: String) -> Dictionary:
	var parts := token.split(".")
	if parts.size() < 2:
		return {}
	var b64 := parts[1].replace("-", "+").replace("_", "/")
	while b64.length() % 4 != 0:
		b64 += "="
	var data: Variant = JSON.parse_string(Marshalls.base64_to_raw(b64).get_string_from_utf8())
	return data if typeof(data) == TYPE_DICTIONARY else {}
