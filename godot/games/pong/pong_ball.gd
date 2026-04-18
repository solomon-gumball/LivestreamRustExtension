extends CharacterBody3D
class_name PongBall

const MAX_PREDICTION_DELTA = 0.2

@export var max_hit_angle_speed: float = 1.5
@export var paddle_velocity_influence: float = 0.4
@export var paddle_half_width: float = 0.5

var sync_state: PongEntity = PongEntity.new()
var speed: float = 2.0

func has_authority() -> bool:
  return sync_state.owner == Network.multiplayer_client.my_peer_id()

func _ready() -> void:
  if has_authority():
    velocity = Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, randf_range(0, TAU))
    velocity *= speed

func move(total_delta: float, max_step: float = 1.0 / 60.0) -> void:
  var remaining := total_delta
  while remaining > 0.0:
    var step := minf(remaining, max_step)
    var collision: KinematicCollision3D = move_and_collide(velocity * step)
    if collision:
      _handle_collision(collision)
    remaining -= step

func _handle_collision(collision: KinematicCollision3D) -> void:
  var paddle := collision.get_collider().get_parent() as PongPaddle
  if paddle:
    var hit_offset := clampf((position.x - paddle.position.x) / paddle_half_width, -1.0, 1.0)
    velocity.z = -velocity.z
    velocity.x = hit_offset * max_hit_angle_speed + paddle.velocity.x * paddle_velocity_influence
    velocity.y = 0.0
  else:
    velocity = velocity.bounce(collision.get_normal())
    velocity.y = 0.0

func _physics_process(delta: float) -> void:
  # ProjectSettings.load_resource_pack(
  if !has_authority():
    position = sync_state.position
    velocity = sync_state.velocity
    var packet_delta := minf(MAX_PREDICTION_DELTA, Time.get_unix_time_from_system() - sync_state.sent_at)
    move(packet_delta)
  else:
    move(delta)

  if has_authority():
    velocity = velocity.normalized() * speed
    Network.multiplayer_client.send_packet({
      "type": PongGame.PongGameMessage.BallMove,
      "position": position,
      "velocity": velocity,
      "sent_at": Time.get_unix_time_from_system()
    })
    speed += delta * 0.05
