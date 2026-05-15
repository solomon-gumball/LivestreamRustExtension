class_name PhysicsKartMovementSynchronizer
extends MovementSynchronizer

@export var kart: PhysicsKart
@export var kart_visual_node: Node3D

@export var collision_box_shape: BoxShape3D
@export var acceleration_curve: Curve
@export var base_acceleration: float = 4.0
@export var max_ground_speed: float = 1.5
@export var drag_coefficient: float = 5.0
@export var min_speed_threshold: float = 0.01
@export var mass: float = 5.0
@export var gravity: float = 2.0
@export var angular_damp: float = 0.5
@export var surface_friction: float = 4.0
@export var collision_torque_scale: float = 0.2

var mappings := {
  "move_forward": KEY_W,
  "move_back": KEY_S,
  "turn_left": KEY_A,
  "turn_right": KEY_D,
}

# Inertia tensor diagonal (Ixx, Iyy, Izz) computed from collision box dimensions.
# Precomputed in _ready so simulate_one_frame doesn't recompute each tick.
var _inertia: Vector3
var _wheel_offsets: Array[Vector3] = []

const MAX_WHEEL_ANGLE := deg_to_rad(35.0)
const WHEEL_TURN_SPEED := deg_to_rad(120.0)

func _ready() -> void:
  super._ready()
  _precompute_inertia()

func _on_synchronizer_ready() -> void:
  _capture_wheel_offsets()

func _capture_wheel_offsets() -> void:
  _wheel_offsets = []
  for w in [kart.wheel_fl, kart.wheel_fr, kart.wheel_rl, kart.wheel_rr]:
    if w:
      var offset := kart.to_local(w.global_position)
      print("wheel offset ", w.name, " = ", offset)
      _wheel_offsets.append(offset)
    else:
      _wheel_offsets.append(Vector3.ZERO)

func _precompute_inertia() -> void:
  if not collision_box_shape:
    _inertia = Vector3(1.0, 1.0, 1.0) * mass
    return
  var s: Vector3 = collision_box_shape.size
  var w := s.x
  var h := s.y
  var d := s.z
  _inertia = Vector3(
    mass * (h * h + d * d) / 12.0,  # Ixx — roll
    mass * (w * w + d * d) / 12.0,  # Iyy — yaw
    mass * (w * w + h * h) / 12.0   # Izz — pitch
  )

func _bind_inputs() -> void:
  for action in mappings:
    if not InputMap.has_action(action):
      InputMap.add_action(action)
    var event := InputEventKey.new()
    event.keycode = mappings[action]
    InputMap.action_add_event(action, event)

func _unbind_inputs() -> void:
  for action in mappings.keys():
    if InputMap.has_action(action):
      InputMap.erase_action(action)

func get_default_input() -> Dictionary:
  return { "move": Vector2.ZERO }

func get_initial_state() -> Dictionary:
  return {
    "position": kart.global_position,
    "basis": kart.global_basis,
    "linear_velocity": Vector3.ZERO,
    "angular_velocity": Vector3.ZERO,
    "wheel_turn": 0.0,
  }

func apply_state_to_entity(state: Dictionary) -> void:
  kart.global_position = state.position
  kart.global_basis = state.basis
  kart.wheel_turn = state.get("wheel_turn", 0.0)
  kart.set_velocities(state.linear_velocity, state.angular_velocity)

func apply_visual_correction(pre_state: Dictionary, post_state: Dictionary) -> void:
  DebugDraw.draw_sphere(pre_state.get("position", Vector3.ZERO), 0.15, Color.RED, 1.0)
  DebugDraw.draw_sphere(post_state.get("position", Vector3.ZERO), 0.15, Color.GREEN, 1.0)
  # kart.apply_visual_correction(pre_state.get("position", Vector3.ZERO), pre_state.get("basis", Basis.IDENTITY))

const POS_CORRECTION_THRESHOLD := 0.02
const VEL_CORRECTION_THRESHOLD := 0.1
const ROT_CORRECTION_THRESHOLD := 0.01  # quaternion dot deviation
const WHEEL_TURN_CORRECTION_THRESHOLD := 0.02

func needs_correction(local_state: Dictionary, server_state: Dictionary) -> bool:
  var pos_err: float = local_state.get("position", Vector3.ZERO).distance_to(server_state.get("position", Vector3.ZERO))
  var vel_err: float = local_state.get("linear_velocity", Vector3.ZERO).distance_to(server_state.get("linear_velocity", Vector3.ZERO))
  var local_q := Quaternion(local_state.get("basis", Basis.IDENTITY))
  var server_q := Quaternion(server_state.get("basis", Basis.IDENTITY))
  var rot_err: float = 1.0 - absf(local_q.dot(server_q))
  var wheel_turn_err: float = absf(local_state.get("wheel_turn", 0.0) - server_state.get("wheel_turn", 0.0))

  return pos_err > POS_CORRECTION_THRESHOLD or \
         vel_err > VEL_CORRECTION_THRESHOLD or \
         rot_err > ROT_CORRECTION_THRESHOLD or \
         wheel_turn_err > WHEEL_TURN_CORRECTION_THRESHOLD

func interpolate_state(from_state: Dictionary, to_state: Dictionary, delta: float) -> Dictionary:
  var weight := delta * 10.0
  var from_q := Quaternion(from_state.get("basis", Basis.IDENTITY))
  var to_q := Quaternion(to_state.get("basis", Basis.IDENTITY))
  return {
    "position": from_state.position.lerp(to_state.position, weight),
    "basis": Basis(from_q.slerp(to_q, weight)),
    "linear_velocity": to_state.get("linear_velocity", Vector3.ZERO),
    "angular_velocity": to_state.get("angular_velocity", Vector3.ZERO),
    "wheel_turn": lerpf(from_state.get("wheel_turn", 0.0), to_state.get("wheel_turn", 0.0), weight),
  }

func _sample_input() -> Dictionary:
  return {
    "move": Input.get_vector("move_back", "move_forward", "turn_right", "turn_left"),
  }

func simulate_one_frame(input: Dictionary, state: Dictionary, tick: int) -> Dictionary:
  var delta := 1.0 / 60.0
  var input_vec: Vector2 = input.get("move", Vector2.ZERO)
  var throttle: float = input_vec.x

  var position: Vector3 = state.get("position", Vector3.ZERO)
  var basis: Basis = state.get("basis", Basis.IDENTITY)
  var linear_velocity: Vector3 = state.get("linear_velocity", Vector3.ZERO)
  var angular_velocity: Vector3 = state.get("angular_velocity", Vector3.ZERO)
  var wheel_turn: float = state.get("wheel_turn", 0.0)

  _logger.log("%s IN pos=%s lvel=%s avel=%s wt=%.4f move=%s" % [
    _sim_tag(tick), position, linear_velocity, angular_velocity, wheel_turn, input_vec])

  # Steering
  var desired_wheel_angle := input_vec.y * MAX_WHEEL_ANGLE
  wheel_turn = move_toward(wheel_turn, desired_wheel_angle, WHEEL_TURN_SPEED * delta)
  wheel_turn = clampf(wheel_turn, -MAX_WHEEL_ANGLE, MAX_WHEEL_ANGLE)

  # Wheel basis with steering rotation applied (front wheels only steer visually;
  # all four wheels share the chassis basis for force computation)
  var steered_basis := basis * Basis(Vector3.UP, wheel_turn)

  # Acceleration force scaled by curve
  var speed := linear_velocity.length()
  var accel_ratio: float = acceleration_curve.sample(clampf(speed / max_ground_speed, 0.0, 1.0)) if acceleration_curve else 1.0
  var drive: float = throttle * base_acceleration * accel_ratio

  # Collect forces from all four wheels
  var total_force := Vector3.ZERO
  var total_torque := Vector3.ZERO
  var any_grounded := false

  # Front wheels use steered basis for drive direction; rear wheels use chassis basis.
  # All four wheels contribute suspension + grip.
  var wheel_inputs := [
    { "wheel": kart.wheel_fl, "force_basis": steered_basis, "drive": drive, "offset": _wheel_offsets[0] },
    { "wheel": kart.wheel_fr, "force_basis": steered_basis, "drive": drive, "offset": _wheel_offsets[1] },
    { "wheel": kart.wheel_rl, "force_basis": basis,         "drive": drive, "offset": _wheel_offsets[2] },
    { "wheel": kart.wheel_rr, "force_basis": basis,         "drive": drive, "offset": _wheel_offsets[3] },
  ]

  for entry in wheel_inputs:
    var w: PhysicsWheel = entry.wheel
    if not w:
      continue
    var wheel_result: Dictionary = w.compute_forces(
      position, basis, entry.force_basis, entry.offset, linear_velocity, angular_velocity, entry.drive, delta
    )
    total_force += wheel_result.force
    total_torque += wheel_result.torque
    if wheel_result.is_grounded:
      any_grounded = true

  # Gravity
  total_force += Vector3.DOWN * gravity * mass

  # Drag when grounded and not throttling
  if any_grounded and absf(throttle) < 0.01 and speed > min_speed_threshold:
    total_force += -linear_velocity.normalized() * drag_coefficient * speed
  elif any_grounded and speed < min_speed_threshold and absf(throttle) < 0.01:
    linear_velocity = Vector3.ZERO

  # Integrate linear
  linear_velocity += (total_force / mass) * delta

  # Clamp ground speed
  if any_grounded and linear_velocity.length() > max_ground_speed:
    var vert := linear_velocity.y
    var horiz := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
    horiz = horiz.normalized() * max_ground_speed
    linear_velocity = Vector3(horiz.x, vert, horiz.z)

  # Integrate angular
  var torque_local: Vector3 = basis.inverse() * total_torque
  var alpha_local := Vector3(
    torque_local.x / _inertia.x,
    torque_local.y / _inertia.y,
    torque_local.z / _inertia.z,
  )
  angular_velocity += (basis * alpha_local) * delta
  angular_velocity *= clampf(1.0 - angular_damp * delta, 0.0, 1.0)

  # Integrate orientation
  var angle := angular_velocity.length()
  if angle > 0.0001:
    var rot_q := Quaternion(angular_velocity / angle, angle * delta)
    basis = Basis(rot_q * Quaternion(basis)).orthonormalized()

  # Wall / floor collision via motion sweep
  var params := PhysicsTestMotionParameters3D.new()
  params.from = Transform3D(basis, position)
  params.motion = linear_velocity * delta

  var result := PhysicsTestMotionResult3D.new()
  if PhysicsServer3D.body_test_motion(kart.get_rid(), params, result):
    var normal := result.get_collision_normal()
    var contact_point := result.get_collision_point()
    position += result.get_travel()

    # Collision impulse magnitude: how hard we were moving into the surface
    var impact_speed := -linear_velocity.dot(normal)
    if impact_speed > 0.0:
      var impulse := normal * impact_speed * mass
      # Apply linear response
      linear_velocity += impulse / mass
      # Apply torque from contact offset — this is what rotates the body onto a flat face
      var contact_offset := contact_point - (position + basis * kart.get_center_of_mass())
      var collision_torque := contact_offset.cross(impulse)
      var ct_local := basis.inverse() * collision_torque
      angular_velocity += basis * Vector3(
        ct_local.x / _inertia.x,
        ct_local.y / _inertia.y,
        ct_local.z / _inertia.z,
      ) * collision_torque_scale

    linear_velocity = linear_velocity.slide(normal)

    # Apply surface friction on non-wall contacts — bleeds off sliding velocity
    # proportional to how flat the surface is (no friction on steep walls).
    var flatness := normal.dot(Vector3.UP)
    if flatness > 0.3:
      linear_velocity *= clampf(1.0 - surface_friction * flatness * delta, 0.0, 1.0)

    # Handle remainder with a second sweep
    var remainder := result.get_remainder()
    if remainder.length() > 0.001:
      params.from = Transform3D(basis, position)
      params.motion = remainder
      var remainder_result := PhysicsTestMotionResult3D.new()
      if PhysicsServer3D.body_test_motion(kart.get_rid(), params, remainder_result):
        position += remainder_result.get_travel()
        linear_velocity = linear_velocity.slide(remainder_result.get_collision_normal())
      else:
        position += remainder

    if normal.dot(Vector3.UP) > 0.7:
      linear_velocity.y = 0.0
  else:
    position += linear_velocity * delta

  _logger.log("%s OUT pos=%s lvel=%s avel=%s wt=%.4f" % [
    _sim_tag(tick), position, linear_velocity, angular_velocity, wheel_turn])

  kart.global_position = position
  kart.global_basis = basis
  kart.wheel_turn = wheel_turn
  kart.set_velocities(linear_velocity, angular_velocity)
  # DebugDraw.draw_sphere(position + Vector3(0, 1.0, 0), 0.1, Color.GREEN if any_grounded else Color.RED)

  return {
    "position": position,
    "basis": basis,
    "linear_velocity": linear_velocity,
    "angular_velocity": angular_velocity,
    "wheel_turn": wheel_turn,
  }
