extends CharacterBody3D
class_name PongBall

var sync_state: PongEntity = PongEntity.new()
var speed: float = 2.0

func has_authority():
  return sync_state.owner == Network.multiplayer_client.my_peer_id()

func _ready() -> void:
  if has_authority():
    velocity = Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, randf_range(0, TAU))
    velocity *= speed

func _physics_process(delta: float) -> void:
  if !has_authority():
    position = lerp(position, sync_state.position, delta * 10.0)
    velocity = lerp(velocity, sync_state.velocity, delta * 10.0)

  var collision = move_and_collide(velocity * delta)
  if collision:
      velocity = velocity.bounce(collision.get_normal())
      velocity.y = 0

  if has_authority():
    velocity = velocity.normalized() * speed
    Network.multiplayer_client.send_packet({
      "type": PongGame.PongGameMessage.BallMove,
      "position": position,
      "velocity": velocity
    })
    speed += delta * 0.05
