extends CharacterBody3D
class_name PongBall

const SPEED: float = 3.0

@export var max_hit_angle_speed: float = 1.5
@export var paddle_velocity_influence: float = 0.4
@export var paddle_half_width: float = 0.5

var sync_state: PongEntity = PongEntity.new()

var paddle_l: PongPaddle = null
var paddle_r: PongPaddle = null

var _shape := SphereShape3D.new()

func _ready() -> void:
  _shape.radius = 0.05

func has_authority() -> bool:
  return MultiplayerClient.is_authority()

func _my_paddle() -> PongPaddle:
  var my_id := MultiplayerClient.my_peer_id()
  if paddle_l and paddle_l.sync_state.owner == my_id:
    return paddle_l
  if paddle_r and paddle_r.sync_state.owner == my_id:
    return paddle_r
  return null

func _projected_position() -> Vector3:
  var elapsed := Time.get_unix_time_from_system() - sync_state.sent_at
  return sync_state.position + sync_state.velocity * elapsed

func _send_bounce(bounce_position: Vector3, bounce_velocity: Vector3) -> void:
  var now := Time.get_unix_time_from_system()
  # Push slightly off the surface so the next intersect_shape doesn't re-detect the same collision
  sync_state.position = bounce_position + bounce_velocity.normalized() * _shape.radius * 2.0
  sync_state.velocity = bounce_velocity
  sync_state.sent_at = now
  print("PEER:", MultiplayerClient.my_peer_id(), " SENT BOUNCE EVENT AT Z - ", bounce_position.z)
  MultiplayerClient.send_packet(
    {
      "type": PongGame.PongGameMessage.BallMove,
      "position": bounce_position,
      "velocity": bounce_velocity,
      "sent_at": now,
    },
    MultiplayerPeer.TARGET_PEER_BROADCAST,
    MultiplayerPeer.TRANSFER_MODE_RELIABLE,
    true
  )

func _check_bounces(proj: Vector3) -> void:
  var space := get_world_3d().direct_space_state
  var query := PhysicsShapeQueryParameters3D.new()
  query.shape = _shape
  query.transform = Transform3D(Basis.IDENTITY, proj)
  query.exclude = [self]
  var hits := space.intersect_shape(query)
  if hits.is_empty():
    return

  var collider: Object = hits[0].collider
  var paddle := collider.get_parent() as PongPaddle if collider else null

  if paddle:
    # Only the paddle owner sends paddle bounces
    if paddle != _my_paddle():
      return
    var hit_offset := clampf((proj.x - paddle.position.x) / paddle_half_width, -1.0, 1.0)
    var new_vel := Vector3(
      hit_offset * max_hit_angle_speed + paddle.velocity.x * paddle_velocity_influence,
      0.0,
      -sync_state.velocity.z
    ).normalized() * SPEED
    _send_bounce(proj, new_vel)
  else:
    # Wall — only the host sends wall bounces
    if not has_authority():
      return
    var new_vel := Vector3(-sync_state.velocity.x, 0.0, sync_state.velocity.z).normalized() * SPEED
    _send_bounce(proj, new_vel)

func _physics_process(_delta: float) -> void:
  if sync_state.sent_at == 0.0:
    return

  var proj := _projected_position()
  position = proj

  _check_bounces(proj)
