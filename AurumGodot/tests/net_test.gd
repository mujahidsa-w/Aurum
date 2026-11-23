extends Node
## Multiplayer end-to-end test client (CI). Run two of these against a dedicated server:
##   godot --headless --path AurumGodot res://tests/net_test.tscn -- --name=Alpha --role=shooter
## Checks: join waiting room -> match start -> island built -> go -> sees the other player
## and the server's bots moving (snapshots) -> shooter hits victim -> server applies damage.


func _ready() -> void:
	var runner := Runner.new()
	runner.name = "NetTestRunner"
	get_tree().root.add_child.call_deferred(runner)


class Runner extends Node:
	var player_name := "Tester"
	var role := "shooter"
	var port := 7777
	var _t := 0.0
	var _go_t := -1.0
	var _done := false
	var _hit_sent := false
	var _checked_world := false

	func _ready() -> void:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--name="):
				player_name = a.substr(7)
			elif a.begins_with("--role="):
				role = a.substr(7)
			elif a.begins_with("--port="):
				port = int(a.substr(7))
		GameState.player_name = player_name
		GameState.character_id = "nathan" if role == "shooter" else "sophia"
		GameState.outfit_id = "original"
		GameState.auth_provider = "guest"
		GameState.trained = true
		GameState.server_address = "127.0.0.1:%d" % port
		Net.lobby_updated.connect(func(n: int, s: int) -> void: _log("waiting room: %d players, starts in %ds" % [n, s]))
		Net.match_started.connect(_on_match_started)
		Net.connection_lost.connect(func(r: String) -> void: _finish(false, "connection lost: " + r))
		Net.go_received.connect(func() -> void: _go_t = 0.0)
		if not Net.find_match():
			_finish(false, "no server address")

	func _on_match_started() -> void:
		_log("match started (seed %d, %d players)" % [Net.match_seed, Net.roster.size()])
		get_tree().change_scene_to_file("res://scenes/battleground.tscn")

	func _process(delta: float) -> void:
		if _done:
			return
		_t += delta
		if _t > 280.0:
			_finish(false, "timeout (go=%s)" % str(Net.go_arrived))
			return
		if _go_t < 0.0 or Net.battle == null:
			return
		_go_t += delta
		var b: Node = Net.battle
		var net: Dictionary = b.get("_net")
		var me := Net.my_id()
		if not _checked_world and _go_t > 6.0:
			_checked_world = true
			var humans := 0
			var bots := 0
			var tracked := 0
			for id in net:
				var p: Node = net[id]
				if int(id) > 0 and int(id) != me:
					humans += 1
				elif int(id) < 0:
					bots += 1
				if bool(p.get("_has_state")):
					tracked += 1
			_log("sees %d other player(s), %d bots, %d with live snapshots" % [humans, bots, tracked])
			if humans != 1 or bots != 22 or tracked < 20:
				_finish(false, "world check failed")
				return
		if role == "shooter" and _checked_world and not _hit_sent and _go_t > 8.0:
			for id in net:
				if int(id) > 0 and int(id) != me:
					_hit_sent = true
					_log("shooting player %d for 30 damage (torso)" % int(id))
					Net.send_hit(int(id), 30.0, 1.2)
			if _hit_sent:
				# Shooter passes once the server confirms the victim's new health.
				pass
		if role == "shooter" and _hit_sent:
			for id in net:
				if int(id) > 0 and int(id) != me:
					var hp := float((net[id] as Node).get("health"))
					if absf(hp - 70.0) < 0.5:
						_finish(true, "server confirmed the hit (victim health %.0f)" % hp)
		if role == "victim" and _checked_world:
			var pl: Node = b.get("player")
			var hp2 := float(pl.get("health"))
			if absf(hp2 - 70.0) < 0.5:
				_finish(true, "received server damage (health %.0f)" % hp2)

	func _log(text: String) -> void:
		print("NET TEST %s: %s" % [player_name, text])

	func _finish(ok: bool, text: String) -> void:
		if _done:
			return
		_done = true
		_log(("PASS - " if ok else "FAIL - ") + text)
		# Give the other client time to observe the result before disconnecting.
		await get_tree().create_timer(6.0).timeout
		get_tree().quit(0 if ok else 1)
