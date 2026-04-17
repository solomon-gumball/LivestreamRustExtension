extends CharacterBody3D
class_name PongBall

var has_authority := false:
  set(new_value):
    has_authority = new_value

var sync_position: Vector3 = Vector3.ZERO
var sync_velocity: Vector3 = Vector3.ZERO

var is_finished: bool = false

func start() -> void:
  velocity = Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, randf_range(0, TAU))
  velocity *= 1.0

func _physics_process(delta: float) -> void:
  if !has_authority:
    position = lerp(position, sync_position, delta * 10.0)
    velocity = lerp(velocity, sync_velocity, delta * 10.0)
  
  if !is_finished:
    var collision = move_and_collide(velocity * delta)
    if collision:
        velocity = velocity.bounce(collision.get_normal())

  Network.multiplayer_client.send_packet({
    "type": PongGame.PongGameMessage.BallMove,
    "position": position,
    "velocity": velocity
  })
