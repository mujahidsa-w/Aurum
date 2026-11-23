extends Node
## Renders screens with the real renderer and saves PNGs. Used by CI under a virtual display
## (.github/workflows/screenshots.yml). Output folder: env SHOT_DIR (default user://shots).

const LobbyScene := preload("res://scenes/lobby.tscn")

var _dir := ""


func _ready() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir() + "/shots"
	DirAccess.make_dir_recursive_absolute(_dir)
	var lobby := LobbyScene.instantiate()
	add_child(lobby)
	await _settle(10.0)
	_save("lobby")
	var ui := lobby.find_child("LobbyUI", true, false)
	if ui and ui.has_method("_open_friends"):
		ui.call("_open_friends")
		await _settle(3.0)
		_save("lobby_friends")
	get_tree().quit()


## Waits for real time (and a minimum of frames) so assets and shaders are ready.
func _settle(seconds: float) -> void:
	var start := Time.get_ticks_msec()
	var frames := 0
	while frames < 30 or Time.get_ticks_msec() - start < seconds * 1000.0:
		await get_tree().process_frame
		frames += 1


func _save(shot_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := _dir.path_join(shot_name + ".png")
	var err := img.save_png(path)
	print("SCREENSHOT %s %dx%d -> %s (%s)" % [shot_name, img.get_width(), img.get_height(), path, error_string(err)])
