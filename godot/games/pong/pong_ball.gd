extends CharacterBody3D
class_name PongBall

const SPEED: float = 3.0

@export var max_hit_angle_speed: float = 1.5
@export var paddle_velocity_influence: float = 0.4
@export var paddle_half_width: float = 0.5

var sync_state: PongGameState.PongEntity = PongGameState.PongEntity.new()

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

func _find_clear_position(from: Vector3, direction: Vector3) -> Vector3:
  var space := get_world_3d().direct_space_state
  var query := PhysicsShapeQueryParameters3D.new()
  query.shape = _shape
  query.exclude = [self]
  var step := _shape.radius
  var pos := from
  for i in 5:
    query.transform = Transform3D(Basis.IDENTITY, pos)
    if space.intersect_shape(query).is_empty():
      return pos
    pos += direction * step
  return pos

func _send_bounce(bounce_position: Vector3, bounce_velocity: Vector3) -> void:
  var now := Time.get_unix_time_from_system()
  sync_state.position = _find_clear_position(bounce_position, bounce_velocity.normalized())
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

  # Ray from behind the ball through the contact point to get the surface normal
  var ray_origin := proj - sync_state.velocity.normalized() * _shape.radius * 2.0
  var ray_target := proj + sync_state.velocity.normalized() * _shape.radius * 2.0
  var ray := PhysicsRayQueryParameters3D.create(ray_origin, ray_target)
  ray.exclude = [self]
  var ray_hit := space.intersect_ray(ray)
  if ray_hit.is_empty():
    return
  var normal: Vector3 = ray_hit.normal

  if paddle:
    if paddle != _my_paddle():
      return
    var new_vel: Vector3
    # Face hit (Z normal): apply hit-offset angle based on where on the face the ball landed
    if absf(normal.z) > 0.5:
      var hit_offset := clampf((proj.x - paddle.position.x) / paddle_half_width, -1.0, 1.0)
      new_vel = Vector3(
        hit_offset * max_hit_angle_speed + paddle.velocity.x * paddle_velocity_influence,
        0.0,
        -sync_state.velocity.z
      )
    else:
      # Top/bottom edge hit: reflect off the actual normal
      new_vel = sync_state.velocity.bounce(normal)
      new_vel.y = 0.0
    _send_bounce(proj, new_vel.normalized() * SPEED)
  else:
    if not has_authority():
      return
    var new_vel := sync_state.velocity.bounce(normal)
    new_vel.y = 0.0
    _send_bounce(proj, new_vel.normalized() * SPEED)

func _physics_process(_delta: float) -> void:
  if sync_state.sent_at == 0.0:
    return

  var proj := _projected_position()
  position = proj

  _check_bounces(proj)
