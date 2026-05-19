class_name PhysicsKartMovementSynchronizer
extends MovementSynchronizer

@export var kart: PhysicsKart
@export var kart_visual_node: Node3D

@export var collision_box_shape: BoxShape3D
@export var acceleration_curve: Curve
@export var base_acceleration: float = 3.0
@export var max_ground_speed: float = 2.0
@export var drag_coefficient: float = 5.0
@export var min_speed_threshold: float = 0.01
@export var mass: float = 5.0
@export var gravity: float = 2.0
@export var angular_damp: float = 0.5
@export var surface_friction: float = 1.0
@export var collision_restitution: float = 0.1
@export var max_impulse_angular_delta: float = 8.0
@export var contact_angular_damp: float = 8.0
@export var air_control_torque: float = 0.0
@export var flip_velocity_threshold: float = 0.2
@export var flip_up_dot_threshold: float = 0.5
@export var flip_frame_threshold: int = 60
@export var interpolation_speed: float = 20.0

signal kart_flipped

var _flip_frames: int = 0

var mappings := {
  "move_forward": KEY_W,
  "move_back": KEY_S,
  "turn_left": KEY_A,
  "turn_right": KEY_D,
  "punch": KEY_SPACE,
}

# Inertia tensor diagonal (Ixx, Iyy, Izz) computed from collision box dimensions.
# Precomputed in _ready so simulate_one_frame doesn't recompute each tick.
var _inertia: Vector3
var _wheel_offsets: Array[Vector3] = []
var _visual_rest_offset := Vector3.ZERO
var _visual_rest_local_basis := Basis.IDENTITY
var _interp_visual_tween: Tween = null

const MAX_WHEEL_ANGLE := deg_to_rad(35.0)
const WHEEL_TURN_SPEED := deg_to_rad(80.0)

func _ready() -> void:
  super._ready()
  # if !MultiplayerClient.is_lobby_host():
  #   kart.collision_mask = 1

  _precompute_inertia()

func _on_synchronizer_ready() -> void:
  _capture_wheel_offsets()
  if kart_visual_node:
    _visual_rest_offset = kart.to_local(kart_visual_node.global_position)
    _visual_rest_local_basis = kart.global_basis.inverse() * kart_visual_node.global_basis
    kart_visual_node.top_level = true

func _capture_wheel_offsets() -> void:
  _wheel_offsets = []
  for w in [kart.wheel_fl, kart.wheel_fr, kart.wheel_rl, kart.wheel_rr]:
    if w:
      var offset := kart.to_local(w.global_position)
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
  return { "move": Vector2.ZERO, "punch_pressed": false }

func get_initial_state() -> Dictionary:
  return {
    "position": kart.global_position,
    "rotation": Quaternion(kart.global_basis),
    "linear_velocity": Vector3.ZERO,
    "angular_velocity": Vector3.ZERO,
    "wheel_turn": 0.0,
  }

func apply_state_to_entity(state: Dictionary) -> void:
  kart.global_position = state.position
  kart.global_basis = Basis(state.get("rotation", Quaternion.IDENTITY))
  kart.wheel_turn = state.get("wheel_turn", 0.0)
  kart.set_velocities(state.linear_velocity, state.angular_velocity)

func _process(_delta: float) -> void:
  super._process(_delta)

  if not kart_visual_node:
    return
  if _interp_visual_tween == null or not _interp_visual_tween.is_running():
    kart_visual_node.global_position = kart.global_position + kart.global_basis * _visual_rest_offset
    kart_visual_node.global_basis = kart.global_basis * _visual_rest_local_basis

const VISUAL_CORRECTION_DURATION := 0.3
const VISUAL_TELEPORT_THRESHOLD := 3.0

func apply_visual_correction(pre_state: Dictionary, post_state: Dictionary) -> void:
  DebugDraw.draw_sphere(pre_state.get("position", Vector3.ZERO), 0.15, Color.RED, 1.0)
  DebugDraw.draw_sphere(post_state.get("position", Vector3.ZERO), 0.15, Color.GREEN, 1.0)
  if not kart_visual_node:
    return

  if _interp_visual_tween != null and _interp_visual_tween.is_running():
    _interp_visual_tween.kill()

  # If the correction is large, snap instantly rather than tweening across a visible gap.
  var post_pos: Vector3 = post_state.get("position", Vector3.ZERO)
  if kart_visual_node.global_position.distance_to(post_pos) > VISUAL_TELEPORT_THRESHOLD:
    _interp_visual_tween = null
    return

  var start_pos: Vector3
  var start_q: Quaternion

  if _interp_visual_tween != null and _interp_visual_tween.is_running():
    start_pos = kart_visual_node.global_position
    start_q = Quaternion(kart_visual_node.global_basis)
    _interp_visual_tween.kill()
  else:
    var pre_basis: Basis = Basis(pre_state.get("rotation", Quaternion.IDENTITY))
    var pre_pos: Vector3 = pre_state.get("position", Vector3.ZERO)
    start_pos = pre_pos + pre_basis * _visual_rest_offset
    start_q = Quaternion(pre_basis * _visual_rest_local_basis)

  _interp_visual_tween = get_tree().create_tween()
  _interp_visual_tween.set_ease(Tween.EASE_OUT)
  _interp_visual_tween.set_trans(Tween.TRANS_QUAD)
  _interp_visual_tween.tween_method(
    func(t: float) -> void:
      var target_pos := kart.global_position + kart.global_basis * _visual_rest_offset
      var target_q := Quaternion(kart.global_basis * _visual_rest_local_basis)
      kart_visual_node.global_position = start_pos.lerp(target_pos, t)
      kart_visual_node.global_basis = Basis(start_q.slerp(target_q, t)),
    0.0, 1.0, VISUAL_CORRECTION_DURATION)

const POS_CORRECTION_THRESHOLD := 0.02
const VEL_CORRECTION_THRESHOLD := 0.1
const ROT_CORRECTION_THRESHOLD := 0.01 # quaternion dot deviation
const WHEEL_TURN_CORRECTION_THRESHOLD := 0.02

func needs_correction(local_state: Dictionary, server_state: Dictionary) -> bool:
  var pos_err: float = local_state.get("position", Vector3.ZERO).distance_to(server_state.get("position", Vector3.ZERO))
  var vel_err: float = local_state.get("linear_velocity", Vector3.ZERO).distance_to(server_state.get("linear_velocity", Vector3.ZERO))
  var local_q: Quaternion = local_state.get("rotation", Quaternion.IDENTITY)
  var server_q: Quaternion = server_state.get("rotation", Quaternion.IDENTITY)
  var rot_err: float = 1.0 - absf(local_q.dot(server_q))
  var wheel_turn_err: float = absf(local_state.get("wheel_turn", 0.0) - server_state.get("wheel_turn", 0.0))

  return pos_err > POS_CORRECTION_THRESHOLD or \
         vel_err > VEL_CORRECTION_THRESHOLD or \
         rot_err > ROT_CORRECTION_THRESHOLD or \
         wheel_turn_err > WHEEL_TURN_CORRECTION_THRESHOLD

func interpolate_state(from_state: Dictionary, to_state: Dictionary, delta: float) -> Dictionary:
  if from_state.get("position", Vector3.ZERO).distance_to(to_state.get("position", Vector3.ZERO)) > VISUAL_TELEPORT_THRESHOLD:
    return to_state

  var weight := clampf(delta * interpolation_speed, 0.0, 1.0)
  var from_q: Quaternion = from_state.get("rotation", Quaternion.IDENTITY)
  var to_q: Quaternion = to_state.get("rotation", Quaternion.IDENTITY)

  return {
    "position": from_state.position.lerp(to_state.position, weight),
    "rotation": from_q.slerp(to_q, weight),
    "linear_velocity": to_state.get("linear_velocity", Vector3.ZERO),
    "angular_velocity": to_state.get("angular_velocity", Vector3.ZERO),
    "wheel_turn": lerpf(from_state.get("wheel_turn", 0.0), to_state.get("wheel_turn", 0.0), weight),
  }

var queued_impulse: Vector3 = Vector3.ZERO
func apply_impulse(impulse: Vector3) -> void:
  queued_impulse += impulse

var queued_torque_impulse: Vector3 = Vector3.ZERO
func apply_torque_impulse(torque: Vector3) -> void:
  queued_torque_impulse += torque

func _sample_input() -> Dictionary:
  return {
    "move": Input.get_vector("move_back", "move_forward", "turn_right", "turn_left"),
    "punch_pressed": Input.is_action_just_pressed("punch"),
  }

var punch_timeout: float = 0
var PUNCH_COOLDOWN := 1.0

func _on_extra_packet(_sender_id: int, packet: Dictionary) -> void:
  match packet.type:
    Carnage.CarnageGameMessage.TriggerPunch:
      kart.punch_cosmetic()

      var punch_location: Vector3 = packet.get("punch_location", Vector3.ZERO)
      var punched := kart.get_punched_karts(punch_location)
      var did_hit: bool = punched.size() > 0

      punch_timeout = PUNCH_COOLDOWN
      # DebugDraw
      print("punch_location ", punch_location)

      if did_hit:
        kart.trigger_impact_fx_at_location(punch_location)
      
      if is_host:
        for punched_kart in punched:
          punched_kart.authority_handle_punch_impact(kart)
        
        var punch_message := {
          "type": Carnage.CarnageGameMessage.ServerKartPunch,
          "owner_peer_id": kart.physics_kart_movement_sync.owner_peer_id,
        }
        if did_hit:
          punch_message["punch_location"] = punch_location

        MultiplayerClient.send_packet(
          punch_message,
          MultiplayerPeer.TARGET_PEER_BROADCAST,
          MultiplayerPeer.TRANSFER_MODE_RELIABLE
        )
    Carnage.CarnageGameMessage.ServerKartPunch:
      if is_owning_peer: return

      kart.punch_cosmetic()
      var punch_location = packet.get("punch_location", null)
      if punch_location != null:
        kart.trigger_impact_fx_at_location(punch_location)
        
    Carnage.CarnageGameMessage.HandleKartPunched:
      kart.handle_punched_cosmetic()

func simulate_one_frame(input: Dictionary, state: Dictionary, tick: int) -> Dictionary:
  var delta := 1.0 / 60.0
  var input_vec: Vector2 = input.get("move", Vector2.ZERO)
  var throttle: float = input_vec.x
  var punch_pressed: bool = input.get("punch_pressed", false)

  var position: Vector3 = state.get("position", Vector3.ZERO)
  var basis: Basis = Basis(state.get("rotation", Quaternion.IDENTITY))
  var linear_velocity: Vector3 = state.get("linear_velocity", Vector3.ZERO)
  var angular_velocity: Vector3 = state.get("angular_velocity", Vector3.ZERO)
  var wheel_turn: float = state.get("wheel_turn", 0.0)

  # _logger.log("%s IN pos=%s lvel=%s avel=%s wt=%.4f move=%s" % [
  #   _sim_tag(tick), position, linear_velocity, angular_velocity, wheel_turn, input_vec])

  if punch_pressed and punch_timeout <= 0 and is_owning_peer:
    var punch_location := kart.punch_area.global_position
    MultiplayerClient.send_packet({
        "type": Carnage.CarnageGameMessage.TriggerPunch,
        "owner_peer_id": owner_peer_id,
        "punch_location": punch_location,
      },
      MultiplayerPeer.TARGET_PEER_SERVER,
      MultiplayerPeer.TRANSFER_MODE_RELIABLE,
      MultiplayerClient.PacketSelfMode.SelfIncluded
    )

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

  if !any_grounded:
    # input_vec.x pitches the car forward/back around its local right axis (chassis_basis.x)
    # input_vec.y rolls the car side to side around its local forward axis (chassis_basis.z)
    var air_torque := basis.x * (input_vec.x * air_control_torque) \
                    + basis.z * (-input_vec.y * air_control_torque)
    var at_local := basis.inverse() * air_torque
    angular_velocity += basis * Vector3(
      at_local.x / _inertia.x,
      at_local.y / _inertia.y,
      at_local.z / _inertia.z,
    ) * delta

  # Gravity
  total_force += Vector3.DOWN * gravity * mass

  # Drag when grounded and not throttling
  if any_grounded and absf(throttle) < 0.01 and speed > min_speed_threshold:
    total_force += -linear_velocity.normalized() * drag_coefficient * speed
  elif any_grounded and speed < min_speed_threshold and absf(throttle) < 0.01:
    linear_velocity = Vector3.ZERO

  # Integrate linear
  linear_velocity += (total_force / mass) * delta

  linear_velocity += queued_impulse
  if queued_impulse.length() > 0.01:
    _logger.log("%s IMPULSE applied %s new_lvel=%s" % [_sim_tag(tick), queued_impulse, linear_velocity], true)
  queued_impulse = Vector3.ZERO

  angular_velocity += queued_torque_impulse
  if queued_torque_impulse.length() > 0.01:
    _logger.log("%s TORQUE_IMPULSE applied %s new_avel=%s" % [_sim_tag(tick), queued_torque_impulse, angular_velocity], true)
  queued_torque_impulse = Vector3.ZERO

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

    # Full rigid-body impulse accounting for spin at contact point.
    # v_contact = linear_vel + angular_vel × r,  r = contact offset from CoM
    # j = -(1+e)*dot(v_contact,n) / (1/m + dot(n, (I⁻¹(r×n))×r))
    var flatness := normal.dot(Vector3.UP)
    var com := basis * kart.get_center_of_mass()
    var r := contact_point - (position + com)
    var v_contact := linear_velocity + angular_velocity.cross(r)
    var v_along_normal := v_contact.dot(normal)

    if v_along_normal < 0.0:
      var r_cross_n := r.cross(normal)
      var r_cross_n_local := basis.inverse() * r_cross_n
      var i_inv_r_cross_n_local := Vector3(
        r_cross_n_local.x / _inertia.x,
        r_cross_n_local.y / _inertia.y,
        r_cross_n_local.z / _inertia.z,
      )
      var i_inv_r_cross_n := basis * i_inv_r_cross_n_local
      var angular_denom := normal.dot(i_inv_r_cross_n.cross(r))
      var j: float = -(1.0 + collision_restitution) * v_along_normal / (1.0 / mass + angular_denom)
      var impulse: Vector3 = normal * j
      linear_velocity += impulse / mass
      var delta_av_local := basis.inverse() * r.cross(impulse)
      var delta_av := basis * Vector3(
        delta_av_local.x / _inertia.x,
        delta_av_local.y / _inertia.y,
        delta_av_local.z / _inertia.z,
      )
      angular_velocity += delta_av.limit_length(max_impulse_angular_delta)

    linear_velocity = linear_velocity.slide(normal)

    if flatness > 0.1:
      linear_velocity *= clampf(1.0 - surface_friction * flatness * delta, 0.0, 1.0)
      var damp_factor := clampf(1.0 - contact_angular_damp * flatness * delta, 0.0, 1.0)
      var spin_component := normal * angular_velocity.dot(normal)
      var roll_component := angular_velocity - spin_component
      angular_velocity = roll_component * damp_factor + spin_component * damp_factor * damp_factor

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

  # _logger.log("%s OUT pos=%s lvel=%s avel=%s wt=%.4f" % [
  #   _sim_tag(tick), position, linear_velocity, angular_velocity, wheel_turn])

  kart.global_position = position
  kart.global_basis = basis
  kart.wheel_turn = wheel_turn
  kart.set_velocities(linear_velocity, angular_velocity)
  # DebugDraw.draw_sphere(position + Vector3(0, 1.0, 0), 0.1, Color.GREEN if any_grounded else Color.RED)

  if is_host:
    var is_flipped: bool = (
      not any_grounded and
      basis.y.dot(Vector3.UP) < flip_up_dot_threshold and
      linear_velocity.length() < flip_velocity_threshold
    )
    # print(linear_velocity.length())
    if is_flipped:
      _flip_frames += 1
      if _flip_frames >= flip_frame_threshold:
        _flip_frames = 0
        kart_flipped.emit.call_deferred()
    else:
      _flip_frames = 0

  punch_timeout = max(punch_timeout - delta, 0.0)

  return {
    "position": position,
    "rotation": Quaternion(basis),
    "linear_velocity": linear_velocity,
    "angular_velocity": angular_velocity,
    "wheel_turn": wheel_turn,
  }
