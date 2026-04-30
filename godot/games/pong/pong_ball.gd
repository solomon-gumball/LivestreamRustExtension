extends CharacterBody3D
class_name PongBall

const BASE_SPEED: float = 3.0
const SPEED_INCREASE_PER_SECOND: float = 0.1

@export var max_hit_angle_speed: float = 1.5
@export var paddle_velocity_influence: float = 0.4
@export var paddle_half_width: float = 0.5
@onready var shape_cast: ShapeCast3D = %ShapeCast

var sync_state: PongGameState.PongEntity = PongGameState.PongEntity.new()

var paddle_l: PongPaddle = null
var paddle_r: PongPaddle = null

var _last_position: Vector3

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
  sync_state.position = bounce_position
  sync_state.velocity = bounce_velocity
  sync_state.sent_at = now
  _last_position = bounce_position
  position = bounce_position

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

const BOUNCE_OFFSET_MARGIN = 0.005
func _check_bounces(proj: Vector3) -> bool:
  shape_cast.global_position = _last_position
  shape_cast.target_position = shape_cast.to_local(proj)
  shape_cast.force_shapecast_update()

  if not shape_cast.is_colliding():
    return false

  var collider: Object = shape_cast.get_collider(0)
  var normal: Vector3 = shape_cast.get_collision_normal(0)
  var safe_fraction := shape_cast.get_closest_collision_safe_fraction()
  var bounce_position: Vector3 = shape_cast.to_global(shape_cast.target_position * safe_fraction) + normal * BOUNCE_OFFSET_MARGIN
  var paddle := collider.get_parent() as PongPaddle if collider else null

  var time_since_last_bounce := Time.get_unix_time_from_system() - sync_state.sent_at
  var new_speed: float = sync_state.velocity.length() + SPEED_INCREASE_PER_SECOND * time_since_last_bounce

  if paddle:
    if paddle != _my_paddle():
      return false
    var new_vel: Vector3
    if absf(normal.z) > 0.5:
      var hit_offset := clampf((bounce_position.x - paddle.position.x) / paddle_half_width, -1.0, 1.0)
      new_vel = Vector3(
        hit_offset * max_hit_angle_speed + paddle.velocity.x * paddle_velocity_influence,
        0.0,
        -sync_state.velocity.z
      )
    else:
      new_vel = sync_state.velocity.bounce(normal)
      new_vel.y = 0.0
    _send_bounce(bounce_position, new_vel.normalized() * new_speed)
    return true
  else:
    if not has_authority():
      return false
    var new_vel := sync_state.velocity.bounce(normal)
    new_vel.y = 0.0
    _send_bounce(bounce_position, new_vel.normalized() * new_speed)
    return true

func _physics_process(_delta: float) -> void:
  if sync_state.sent_at == 0.0:
    return

  var proj := _projected_position()
  position = proj

  var bounced := _check_bounces(proj)
  if not bounced:
    _last_position = proj
