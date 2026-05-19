class_name BouncyProp
extends Node3D

@export var static_body: StaticBody3D
@export var bounce_area: Area3D
@export var bounce_force: float = 3.0
@export var bounce_torque: float = 2.0

const BOUNCE_COOLDOWN := 0.5
var _cooldowns: Dictionary = {}

func _ready() -> void:
  bounce_area.body_entered.connect(_on_bounce_area_body_entered)

func _process(delta: float) -> void:
  for key in _cooldowns.keys():
    _cooldowns[key] -= delta
    if _cooldowns[key] <= 0.0:
      _cooldowns.erase(key)

func _on_bounce_area_body_entered(body: Node) -> void:
  if not MultiplayerClient.is_lobby_host():
    return
  if not body is PhysicsKart:
    return
  var kart := body as PhysicsKart
  var kart_id := kart.get_instance_id()
  if _cooldowns.has(kart_id):
    return
  _cooldowns[kart_id] = BOUNCE_COOLDOWN

  print("APPLY IMPULSE")
  var away := (kart.global_position - global_position)
  away.y = 0.0
  away = away.normalized()

  var tilt_axis := away.cross(Vector3.UP).normalized()
  var impulse := away.rotated(tilt_axis, deg_to_rad(45)) * bounce_force
  var torque := -tilt_axis * bounce_torque
  kart.physics_kart_movement_sync.apply_impulse(impulse)
  kart.physics_kart_movement_sync.apply_torque_impulse(torque)