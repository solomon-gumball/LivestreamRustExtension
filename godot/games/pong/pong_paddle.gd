extends Node3D
class_name PongPaddle

var peer_id: int
var chatter: Chatter:
  set(new_chatter):
    gumbot.chatter = new_chatter
    chatter = new_chatter

var chatter_id: String
var velocity: Vector3 = Vector3.ZERO

@onready var gumbot: GumBot = %GumBot
@onready var collision_body: StaticBody3D = %PaddleCollisionArea

func _ready() -> void:
  sync_position = position

var movement_input: Vector2 = Vector2.ZERO
func add_movement_input(direction: Vector2) -> void:
  movement_input = direction

const MAX_SPEED = 2.0
const MAX_RANGE = 1.5
const ACCELERATION = 0.1
const DECELERATION = 5.0

var has_authority := false:
  set(new_val):
    has_authority = new_val

var sync_position: Vector3 = Vector3.ZERO
var sync_velocity: Vector3 = Vector3.ZERO

func _phys_move(delta: float) -> void:
  position += velocity * delta
  position.x = clamp(position.x, -MAX_RANGE, MAX_RANGE)
  movement_input = Vector2.ZERO

func _physics_process(delta: float) -> void:
  if has_authority:
    var accel = movement_input.y * ACCELERATION
    velocity.x += accel
    velocity.x = clamp(velocity.x, -MAX_SPEED, MAX_SPEED)

    if movement_input.y == 0:
      velocity.x = lerpf(velocity.x, 0.0, delta * DECELERATION)

    Network.multiplayer_client.send_packet({
      "type": PongGame.PongGameMessage.PaddleMove,
      "position": position,
      "velocity": velocity
    })

  else:
    position = lerp(position, sync_position, delta * 10.0)
    velocity = lerp(velocity, sync_velocity, delta * 10.0)
  
  _phys_move(delta)
