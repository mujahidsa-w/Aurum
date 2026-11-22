extends Node
## Lobby entry point: builds the 3D world and the HUD, and lets the player
## spin the hero by dragging anywhere on the empty part of the screen.

const LobbyWorld := preload("res://scripts/lobby_world.gd")
const LobbyUI := preload("res://scripts/lobby_ui.gd")

const DRAG_DEGREES_PER_PIXEL := 0.4

var world: LobbyWorld
var ui: LobbyUI

var _dragging := false
var _spin_velocity := 0.0 # degrees per second, for a little inertia after release


func _ready() -> void:
	world = LobbyWorld.new()
	world.name = "World"
	add_child(world)

	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	ui = LobbyUI.new()
	ui.name = "LobbyUI"
	ui.world = world
	layer.add_child(ui)

	world.apply_quality(GameState.quality)
	_apply_outfit()
	GameState.quality_changed.connect(_on_quality_changed)
	GameState.outfit_changed.connect(_apply_outfit)


func _on_quality_changed() -> void:
	world.apply_quality(GameState.quality)


func _apply_outfit() -> void:
	world.character.set_outfit(GameState.outfit_index)
	world.character.set_rifle_skin(GameState.rifle_skin_index)


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		_dragging = mb.pressed
		if mb.pressed:
			_spin_velocity = 0.0
		return
	var motion := event as InputEventMouseMotion
	if motion and _dragging:
		var degrees := motion.relative.x * DRAG_DEGREES_PER_PIXEL
		world.character_pivot.rotate_y(deg_to_rad(degrees))
		var dt := maxf(get_process_delta_time(), 0.001)
		_spin_velocity = lerpf(_spin_velocity, degrees / dt, 0.5)


## F11 or Alt+Enter toggles full screen on desktop.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F11 or (key.keycode == KEY_ENTER and key.alt_pressed):
		GameState.set_fullscreen(not GameState.fullscreen)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _dragging or absf(_spin_velocity) < 1.0:
		return
	world.character_pivot.rotate_y(deg_to_rad(_spin_velocity * delta))
	_spin_velocity *= exp(-5.0 * delta)
