@tool
extends CharacterBody3D
class_name KartBot

@onready var kart_wheel_l: MeshInstance3D = %KartWheel_L
@onready var kart_wheel_r: MeshInstance3D = %KartWheel_R
@onready var kart_movement: KartMovementSynchronizer = $KartMovement
@onready var gumbot: GumBot = %gumbot

@export var wheel_turn: float = 0.0:
  set(new_value):
    wheel_turn = new_value
    kart_wheel_l.rotation.y = wheel_turn
    kart_wheel_r.rotation.y = wheel_turn

# func _ready() -> void:
#   gumbot.freeze