extends CharacterBody3D
class_name PongBall

const BASE_SPEED: float = 1.5
const SPEED_INCREASE_PER_SECOND: float = 0.1

signal bounced(did_hit_paddle: bool)

@export var max_hit_angle_speed: float = 1.5
@export var paddle_velocity_influence: float = 0.4
@onready var shape_cast: ShapeCast3D = %ShapeCast
@onready var bounce_sound_player: AudioStreamPlayer2D = %BouncePlayer

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
  var elapsed: float = MultiplayerClient.get_host_time() - sync_state.sent_at
  return sync_state.position + sync_state.velocity * elapsed

func _send_bounce(bounce_position: Vector3, bounce_velocity: Vector3, local_only: bool = false) -> void:
  var now: float = MultiplayerClient.get_host_time()
  sync_state.position = bounce_position
  sync_state.velocity = bounce_velocity
  sync_state.sent_at = now
  _last_position = bounce_position
  position = bounce_position

  var self_mode := MultiplayerClient.PacketSelfMode.SelfOnly if local_only \
    else MultiplayerClient.PacketSelfMode.SelfIncluded
  
  if not local_only:
    var date_string := Time.get_datetime_string_from_unix_time(now)
    print("(%s) SENDING BALL MOVE pos=%s vel=%s" % [date_string, bounce_position, bounce_velocity])

  MultiplayerClient.send_packet(
    {
      "type": PongGame.PongGameMessage.BallMove,
      "position": bounce_position,
      "velocity": bounce_velocity,
      "sent_at": now,
    },
    MultiplayerPeer.TARGET_PEER_BROADCAST,
    MultiplayerPeer.TRANSFER_MODE_RELIABLE,
    self_mode
  )

const MIN_ANGLE_FROM_X_DEG: float = 15.0
const ANGLE_NUDGE_DEG: float = 5.0

var pong_explosion_template: PackedScene = preload("res://games/pong/pong_explosion.tscn")

const BOUNCE_OFFSET_MARGIN = 0.005
func _correct_shallow_angle(vel: Vector3) -> Vector3:
  var xz := Vector2(vel.x, vel.z)
  var angle_from_x := absf(rad_to_deg(atan2(absf(xz.y), absf(xz.x))))
  if angle_from_x >= MIN_ANGLE_FROM_X_DEG:
    return vel
  var nudge := deg_to_rad(ANGLE_NUDGE_DEG)
  var sign_z := signf(xz.y) if xz.y != 0.0 else 1.0
  var current_angle := atan2(xz.y, xz.x)
  var target_angle := current_angle + sign_z * nudge
  return Vector3(cos(target_angle), 0.0, sin(target_angle)) * vel.length()

func spawn_explosion(location: Vector3, normal: Vector3) -> void:
  var explosion := pong_explosion_template.instantiate() as GPUParticles3D
  explosion.one_shot = true
  get_parent().add_child(explosion)
  explosion.global_position = location
  explosion.look_at(explosion.global_position + normal, Vector3.UP, true)
  explosion.emitting = true
  await explosion.finished
  explosion.queue_free()

func _check_bounces(proj: Vector3) -> bool:
  shape_cast.global_position = _last_position
  shape_cast.target_position = shape_cast.to_local(proj)
  shape_cast.force_shapecast_update()

  if not shape_cast.is_colliding():
    return false

  bounce_sound_player.pitch_scale = randf_range(0.7, 1.5)
  bounce_sound_player.play()

  var collision_point := shape_cast.get_collision_point(0)
  var collider: Object = shape_cast.get_collider(0)
  var normal: Vector3 = shape_cast.get_collision_normal(0)
  var safe_fraction := shape_cast.get_closest_collision_safe_fraction()
  var bounce_position: Vector3 = shape_cast.to_global(shape_cast.target_position * safe_fraction) + normal * BOUNCE_OFFSET_MARGIN
  var paddle := collider.get_parent() as PongPaddle if collider else null

  spawn_explosion(collision_point, normal)
  bounced.emit(paddle != null)

  var time_since_last_bounce: float = MultiplayerClient.get_host_time() - sync_state.sent_at
  var new_speed: float = sync_state.velocity.length() + SPEED_INCREASE_PER_SECOND * time_since_last_bounce

  if paddle:
    var new_vel: Vector3
    if absf(normal.z) > 0.5:
      var paddle_half_width := paddle.paddle_collision_box.size.x * 0.5
      var hit_offset := clampf((bounce_position.x - paddle.position.x) / paddle_half_width, -1.0, 1.0)
      new_vel = Vector3(
        hit_offset * max_hit_angle_speed + paddle.velocity.x * paddle_velocity_influence,
        0.0,
        -sync_state.velocity.z
      )
    else:
      new_vel = sync_state.velocity.bounce(normal)
      new_vel.y = 0.0
    new_vel = _correct_shallow_angle(new_vel)
    _send_bounce(bounce_position, new_vel.normalized() * new_speed, paddle != _my_paddle())
    return true
  else:
    var new_vel := sync_state.velocity.bounce(normal)
    new_vel.y = 0.0
    new_vel = _correct_shallow_angle(new_vel)
    _send_bounce(bounce_position, new_vel.normalized() * new_speed, not has_authority())
    return true

func _physics_process(_delta: float) -> void:
  if sync_state.sent_at == 0.0:
    return

  var proj := _projected_position()
  position = proj

  var did_bounce := _check_bounces(proj)
  if not did_bounce:
    _last_position = proj
