extends Node3D
class_name PongPaddle

var peer_id: int
var chatter: Chatter:
  set(new_chatter):
    gumbot.chatter = new_chatter
    chatter = new_chatter

var chatter_id: String
var velocity: Vector2 = Vector2.ZERO

@onready var gumbot: GumBot = %GumBot

var movement_input: Vector2 = Vector2.ZERO

func add_movement_input(direction: Vector2) -> void:
  movement_input = direction

const MAX_SPEED = 5.0
const MAX_RANGE = 1.5

func _physics_process(delta: float) -> void:
  var accel = movement_input.y * 10.0
  velocity.x += accel

  velocity.x = clamp(velocity.x, -MAX_SPEED, MAX_SPEED)

  if movement_input.y == 0:
    velocity.x = lerp(velocity.x, 0, delta * 5.0)
  
  var new_position = velocity * delta
  new_position.y = clamp(new_position.y, -MAX_RANGE, MAX_RANGE)
  # translation = new_position