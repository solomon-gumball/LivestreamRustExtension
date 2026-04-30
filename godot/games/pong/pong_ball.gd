extends CharacterBody3D
class_name PongBall

const SPEED: float = 3.0
const WALL_X_MAX: float = 2.366
const WALL_X_MIN: float = -2.366

@export var max_hit_angle_speed: float = 1.5
@export var paddle_velocity_influence: float = 0.4
@export var paddle_half_width: float = 0.5

var sync_state: PongEntity = PongEntity.new()

# paddles set by pong_game after instantiation
var paddle_l: PongPaddle = null
var paddle_r: PongPaddle = null

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
  var packet := {
    "type": PongGame.PongGameMessage.BallMove,
    "position": bounce_position,
    "velocity": bounce_velocity,
    "sent_at": now,
  }
  # Apply locally immediately so we don't double-detect this bounce
  sync_state.position = bounce_position
  sync_state.velocity = bounce_velocity
  sync_state.sent_at = now
  print("SENDING BOUNCE!!!")
  MultiplayerClient.send_packet(
    packet,
    MultiplayerPeer.TARGET_PEER_BROADCAST,
    MultiplayerPeer.TRANSFER_MODE_RELIABLE,
    true
  )

func _check_wall_bounce(proj: Vector3) -> void:
  if proj.x >= WALL_X_MAX or proj.x <= WALL_X_MIN:
    var bounce_pos := proj
    bounce_pos.x = clamp(bounce_pos.x, WALL_X_MIN, WALL_X_MAX)
    var bounce_vel := sync_state.velocity
    bounce_vel.x = -bounce_vel.x
    _send_bounce(bounce_pos, bounce_vel)

func _check_paddle_bounce(proj: Vector3) -> void:
  var paddle := _my_paddle()
  if paddle == null:
    return

  var vel := sync_state.velocity
  # Only check the paddle the ball is currently moving toward
  var moving_toward_positive_z := vel.z > 0.0
  var is_right_paddle := paddle.position.z > 0.0

  if moving_toward_positive_z != is_right_paddle:
    return

  var paddle_z := paddle.position.z
  var prev_proj := sync_state.position + sync_state.velocity * \
    (Time.get_unix_time_from_system() - sync_state.sent_at - get_process_delta_time())

  # Detect crossing the paddle's Z face this frame
  var crossed := (prev_proj.z < paddle_z and proj.z >= paddle_z) or \
                 (prev_proj.z > paddle_z and proj.z <= paddle_z)
  if not crossed:
    return

  # Check X overlap with paddle
  var half := paddle.paddle_collision_box.size.x * 0.5
  if proj.x < paddle.position.x - half or proj.x > paddle.position.x + half:
    return

  var hit_offset := clampf((proj.x - paddle.position.x) / paddle_half_width, -1.0, 1.0)
  var new_vel := Vector3(
    hit_offset * max_hit_angle_speed + paddle.velocity.x * paddle_velocity_influence,
    0.0,
    -vel.z
  )
  new_vel = new_vel.normalized() * SPEED
  _send_bounce(proj, new_vel)

func _physics_process(_delta: float) -> void:
  if sync_state.sent_at == 0.0:
    return

  var proj := _projected_position()
  position = proj

  if has_authority():
    _check_wall_bounce(proj)
  _check_paddle_bounce(proj)
