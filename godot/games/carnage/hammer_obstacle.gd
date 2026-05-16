@tool
class_name HammerObstacle
extends Node3D

@onready var simulation_synchronizer: NetTickSimulated = %NetTickSimulated
@onready var rotation_node: Node3D = %RotationNode
@export_range(0.0, 1.0, 0.01) var rotation_speed: float = .03
@export_range(0.0, 1.0, 0.01) var cycle_offset: float = 0.0
@export var hammer_head: StaticBody3D
@export var impact_area: Area3D
@export var impulse_force: float = 1.5

func _ready() -> void:
  if Engine.is_editor_hint(): return
  simulation_synchronizer.tick_simulated.connect(simulate_tick)

var debug_tick: int = 0
func _physics_process(delta: float) -> void:
  if Engine.is_editor_hint():
    debug_tick = Engine.get_physics_frames()
    simulate_tick(debug_tick, delta)

func simulate_tick(_current_tick: int,  _delta: float) -> void:
  # var s := cos(_current_tick * rotation_speed)
  # rotation_node.rotation_degrees.z = 90.0 * sign(s) * pow(abs(s), 2.0)
  var overlapping_bodies := impact_area.get_overlapping_bodies()
  for body in overlapping_bodies:
    if body is PhysicsKart:
      var kart := body as PhysicsKart
      var impulse_direction := impact_area.global_transform.origin.direction_to(kart.global_transform.origin)
      impulse_direction.y = 0.0
      impulse_direction = impulse_direction.normalized()
      impulse_direction = impulse_direction.rotated(Vector3.UP.cross(impulse_direction), deg_to_rad(-20.0))

      # DebugDraw.draw_line(impact_area.global_transform.origin, impact_area.global_transform.origin + impulse_direction * 5.0, Color.RED, .01, 5.0)
      kart.physics_kart_movement_sync.apply_impulse(impulse_direction * impulse_force)

  rotation_node.rotation_degrees.z = 90.0 * (sin(_current_tick * rotation_speed + cycle_offset * TAU))