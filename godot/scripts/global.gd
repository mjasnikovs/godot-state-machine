extends Node

# Each character registers itself here in _ready, so no script needs a scene path to reach it.

var player: Player = null
var dummy: Dummy = null


func register_player(node: Player) -> void:
	player = node


func register_dummy(node: Dummy) -> void:
	dummy = node
