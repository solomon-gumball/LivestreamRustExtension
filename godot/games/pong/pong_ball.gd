extends Area3D
class_name PongBall

var has_authority := false:
  set(new_value):
    has_authority = new_value
    monitoring = has_authority

var sync_position: Vector3 = Vector3.ZERO
var sync_velocity: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO

var is_finished: bool = false

signal finished

func start() -> void:
  velocity = Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, randf_range(0, TAU))
  velocity *= 1.0
  area_entered.connect(_area_entered)

func _area_entered(area: Area3D) -> void:
  is_finished = true
  finished.emit()
  Network.multiplayer_client.send_packet({
    "type": PongGame.PongGameMessage.RoundComplete
  })

func _physics_process(delta: float) -> void:
  if is_finished:
    return
  if !has_authority:
    position = lerp(position, sync_position, delta * 10.0)
    velocity = lerp(position, sync_velocity, delta * 10.0)
  else:
    position += velocity * delta

    Network.multiplayer_client.send_packet({
      "type": PongGame.PongGameMessage.BallMove,
      "position": position,
      "velocity": velocity
    })
