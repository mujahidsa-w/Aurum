extends Node
## Idle scene of the dedicated server between matches (the waiting room lives in Net).

var _t := 0.0


func _ready() -> void:
	print("AURUM SERVER: waiting room open")


func _process(delta: float) -> void:
	_t += delta
	if _t >= 60.0:
		_t = 0.0
		print("AURUM SERVER: idle, %d connected" % multiplayer.get_peers().size())
