extends Node
## Legacy entry point (kept for tools/tests): routes like the startup screen does.


func _ready() -> void:
	_route.call_deferred()


func _route() -> void:
	get_tree().change_scene_to_file(GameState.entry_scene())
