extends CharacterBody3D
class_name KartBot

@onready var kart_movement: KartMovementSynchronizer = $KartMovement
@onready var gumbot: GumBot = %gumbot
# func _ready() -> void:
#   gumbot.freeze