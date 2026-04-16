extends Node3D
class_name PongPaddle

var peer_id: int
var chatter: Chatter:
  set(new_chatter):
    gumbot.chatter = new_chatter
    chatter = new_chatter

var chatter_id: String

@onready var gumbot: GumBot = %GumBot

func add_movement_input(direction: Vector2) -> void:
  gumbot.add_movement_input(direction)