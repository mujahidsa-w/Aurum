extends Node
## First scene: sends the player to sign-in / character creation, training, or the lobby.


func _ready() -> void:
	_route.call_deferred()


func _route() -> void:
	var target := "res://scenes/lobby.tscn"
	if GameState.auth_provider == "" or GameState.character_id == "":
		target = "res://scenes/onboarding.tscn"
	elif not GameState.trained:
		target = "res://scenes/training.tscn"
	get_tree().change_scene_to_file(target)
