extends Node3D
class_name PhysicsWheel

@export var ray_cast: RayCast3D
@export var spring_strength: float = 600.0
@export var spring_damping: float = 30.0
@export var rest_distance: float = 0.95
@export var wheel_radius: float = 0.8
@export var wheel_mesh: MeshInstance3D
@export var wheel_friction_curve: Curve
@export var tire_mass: float = 2.0
@export var base_friction: float = 0.1
@onready var smoke_fx: GPUParticles3D = %SmokeFX

var initial_position: Vector3
var _last_global_position: Vector3

func _ready() -> void:
  initial_position = position
  smoke_fx.amount_ratio = 0.0

func _process(delta: float) -> void:
  var is_grounded := _check_grounded()
  if delta > 0.0 and is_grounded:
    var vel := (global_position - _last_global_position) / delta
    var lateral_speed := absf(global_basis.x.dot(vel))
    smoke_fx.amount_ratio = clampf(lateral_speed / 1.0, 0.0, 1.0)
  else:
    smoke_fx.amount_ratio = 0.0
  _last_global_position = global_position

func _check_grounded() -> bool:
  var tire_center := global_position + Vector3(0, -rest_distance, 0)
  var params := PhysicsShapeQueryParameters3D.new()
  var shape := SphereShape3D.new()
  shape.radius = wheel_radius
  params.shape = shape
  params.collision_mask = 1
  params.transform = Transform3D(Basis.IDENTITY, tire_center)
  var hits := get_tree().get_root().get_world_3d().direct_space_state.intersect_shape(params, 1)
  return hits.size() > 0

  # var tire_center := global_position + Vector3(0, -rest_distance, 0)
  # DebugDraw.draw_line(global_position, tire_center, Color.YELLOW)
  # DebugDraw.draw_sphere(tire_center, 0.02, Color.YELLOW, 0.0)
  # DebugDraw.draw_sphere(tire_center + Vector3(0, -wheel_radius, 0), 0.02, Color.RED, 0.0)

# Returns { "force": Vector3, "torque": Vector3, "is_grounded": bool }
# Uses a manual ray query derived from the simulated chassis state so the cast
# origin is always in sync with simulate_one_frame, not one frame behind.
func compute_forces(
    chassis_pos: Vector3,
    chassis_basis: Basis,
    force_basis: Basis,
    wheel_offset: Vector3,
    linear_vel: Vector3,
    angular_vel: Vector3,
    drive: float,
    delta: float
) -> Dictionary:
  # Use chassis_basis (unsteered) for attachment point and ray direction so the
  # wheel position doesn't orbit when steering. force_basis (steered) is only
  # used for computing force directions. wheel_offset is pre-captured in local
  # space so this is independent of scene tree nesting depth.
  var wheel_world_pos: Vector3 = chassis_pos + chassis_basis * wheel_offset
  var ray_origin: Vector3 = wheel_world_pos
  var ray_end: Vector3 = wheel_world_pos + chassis_basis * Vector3(0, -(rest_distance + wheel_radius), 0)

  var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
  query.collision_mask = 1
  var hit: Dictionary = get_tree().get_root().get_world_3d().direct_space_state.intersect_ray(query)

  if hit.is_empty():
    return { "force": Vector3.ZERO, "torque": Vector3.ZERO, "is_grounded": false }

  # Reject contact if the wheel isn't roughly facing the ground — prevents
  # sideways wheels from pushing the kart when rolled over.
  var alignment := chassis_basis.y.dot(hit.normal)
  if alignment < 0.3 or hit.normal.y < 0.5:
    return { "force": Vector3.ZERO, "torque": Vector3.ZERO, "is_grounded": false }

  var coll_point: Vector3 = hit.position
  var collision_normal: Vector3 = hit.normal

  # Suspension
  var spring_len: float = ray_origin.distance_to(coll_point) - wheel_radius
  var compression: float = rest_distance - spring_len
  var spring_up_dir: Vector3 = force_basis.y

  # Velocity of the chassis at this contact point (accounts for angular motion at the corners)
  var world_velocity: Vector3 = linear_vel + angular_vel.cross(coll_point - chassis_pos)
  var relative_velocity: float = spring_up_dir.dot(world_velocity)

  var suspension_force: Vector3 = spring_up_dir * (spring_strength * compression - spring_damping * relative_velocity)

  # Lateral grip (opposes sliding in the wheel's side direction)
  var vel_in_side_dir: float = force_basis.x.dot(world_velocity)
  var tire_brake_dot: float = absf(force_basis.x.dot(world_velocity.normalized()))
  var friction_lookup: float = wheel_friction_curve.sample(tire_brake_dot)
  var desired_acceleration: float = (-vel_in_side_dir * friction_lookup * base_friction) / delta
  var steering_force: Vector3 = desired_acceleration * force_basis.x * tire_mass 

  # Drive (project wheel-forward onto the collision plane so it stays on the surface)
  var projected_forward: Vector3 = Plane(collision_normal).project(force_basis.z * 5.0)
  var drive_force: Vector3 = projected_forward.normalized() * drive

  var total_force: Vector3 = suspension_force + steering_force + drive_force
  var torque: Vector3 = (coll_point - chassis_pos).cross(total_force)

  # DebugDraw.draw_line(coll_point, coll_point + total_force * 0.001, Color.YELLOW, 0.01)
  # DebugDraw.draw_line(coll_point + Vector3(0.03, 0, 0), coll_point + suspension_force * 0.001 + Vector3(0.03, 0, 0), Color.CYAN, 0.01)

  # Update the visual wheel mesh position to reflect suspension compression
  if wheel_mesh:
    wheel_mesh.position.y = -spring_len

  return { "force": total_force, "torque": torque, "is_grounded": true }
