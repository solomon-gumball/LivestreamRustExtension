class_name KartMovementSynchronizer
extends MovementSynchronizer

@export var kart: KartBot

var mappings := {
  "move_forward": KEY_W,
  "move_back": KEY_S,
  "turn_left": KEY_A,
  "turn_right": KEY_D,
  "punch": KEY_SPACE,
}

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
    "rotation_y": kart.rotation.y,
    "velocity": Vector3.ZERO,
    "wheel_turn": 0.0,
  }

func apply_state_to_entity(state: Dictionary) -> void:
  kart.global_position = state.position
  kart.rotation.y = state.rotation_y
  kart.wheel_turn = state.get("wheel_turn", 0.0)

func apply_visual_correction(pre_state: Dictionary, post_state: Dictionary) -> void:
  DebugDraw.draw_sphere(pre_state.get("position", Vector3.ZERO), 0.15, Color.RED, 1.0)
  DebugDraw.draw_sphere(post_state.get("position", Vector3.ZERO), 0.15, Color.GREEN, 1.0)
  kart.apply_visual_correction(
    pre_state.get("position", Vector3.ZERO),
    pre_state.get("rotation_y", 0.0)
  )

const POS_CORRECTION_THRESHOLD := 0.02
const VEL_CORRECTION_THRESHOLD := 0.02
const ROT_CORRECTION_THRESHOLD := deg_to_rad(1.0)
const WHEEL_TURN_CORRECTION_THRESHOLD := 0.02

func needs_correction(local_state: Dictionary, server_state: Dictionary) -> bool:
  var pos_err: float = local_state.get("position", Vector3.ZERO).distance_to(server_state.get("position", Vector3.ZERO))
  var vel_err: float = local_state.get("velocity", Vector3.ZERO).distance_to(server_state.get("velocity", Vector3.ZERO))
  var rot_err: float = abs(local_state.get("rotation_y", 0.0) - server_state.get("rotation_y", 0.0))
  var wheel_turn_err: float = abs(local_state.get("wheel_turn", 0.0) - server_state.get("wheel_turn", 0.0))

  return pos_err > POS_CORRECTION_THRESHOLD or \
         vel_err > VEL_CORRECTION_THRESHOLD or \
         rot_err > ROT_CORRECTION_THRESHOLD or \
         wheel_turn_err > WHEEL_TURN_CORRECTION_THRESHOLD

func interpolate_state(from_state: Dictionary, to_state: Dictionary, delta: float) -> Dictionary:
  var weight := delta * 10.0
  return {
    "position": from_state.position.lerp(to_state.position, weight),
    "rotation_y": lerp(from_state.rotation_y, to_state.rotation_y, weight),
    "velocity": to_state.get("velocity", Vector3.ZERO),
    "wheel_turn": lerp(from_state.wheel_turn, to_state.get("wheel_turn", 0.0), weight),
  }

func _sample_input() -> Dictionary:
  return {
    "move": Input.get_vector("move_back", "move_forward", "turn_right", "turn_left"),
    "punch_pressed": Input.is_action_just_pressed("punch"),
  }

func _on_extra_packet(_sender_id: int, packet: Dictionary) -> void:
  match packet.type:
    Carnage.CarnageGameMessage.ServerKartPunch:
      if is_owning_peer: return
      kart.punch_cosmetic()

const MAX_SPEED := 1.0
const ACCELERATION := 0.03
const DRAG := 3.0

const GRAVITY := 9.8
const TURN_RAMP := 4.0
const GRIP := 0.05
const MAX_WHEEL_ANGLE := deg_to_rad(45.0)
const WHEEL_TURN_SPEED := deg_to_rad(100.0)

func simulate_one_frame(input: Dictionary, state: Dictionary, tick: int) -> Dictionary:
  var delta := 1.0 / 60.0
  var input_vec: Vector2 = input.get("move", Vector2.ZERO)
  var punch_pressed: bool = input.get("punch_pressed", false)
  var throttle := input_vec[0]

  var wheel_turn: float = state.wheel_turn
  var velocity: Vector3 = state.velocity
  var rotation_y: float = state.rotation_y
  var forward := Vector3(sin(rotation_y), 0.0, cos(rotation_y))

  _logger.log("%s IN pos=%s vel=%s rot=%.4f wt=%.4f move=%s punch=%s" % [
    _sim_tag(tick), state.position, state.velocity, state.rotation_y, state.wheel_turn,
    input_vec, punch_pressed])

  if abs(throttle) > 0.0:
    velocity += forward * throttle * ACCELERATION
    velocity = velocity.limit_length(MAX_SPEED)
  else:
    velocity = velocity.move_toward(Vector3.ZERO, delta * DRAG)

  _logger.log("%s AFTER_ACCEL vel=%s" % [_sim_tag(tick), velocity])

  if punch_pressed:
    kart.punch_cosmetic()
    if is_host:
      kart.punch_collide()
      MultiplayerClient.send_packet({
        "type": Carnage.CarnageGameMessage.ServerKartPunch,
        "owner_peer_id": owner_peer_id,
      })

  var desired_wheel_angle := input_vec[1] * MAX_WHEEL_ANGLE
  wheel_turn = move_toward(wheel_turn, desired_wheel_angle, WHEEL_TURN_SPEED * delta)
  wheel_turn = clampf(wheel_turn, -MAX_WHEEL_ANGLE, MAX_WHEEL_ANGLE)

  var speed := velocity.length()
  var travel_sign := signf(forward.dot(velocity))
  rotation_y += (wheel_turn / MAX_WHEEL_ANGLE) * speed * TURN_RAMP * travel_sign * delta

  _logger.log("%s AFTER_STEER rot=%.4f wt=%.4f" % [_sim_tag(tick), rotation_y, wheel_turn])

  var wheel_angle := rotation_y + wheel_turn
  var wheel_right_vector := Vector3(cos(wheel_angle), 0.0, -sin(wheel_angle))
  var lateral_velocity := wheel_right_vector.dot(velocity)
  velocity -= wheel_right_vector * lateral_velocity * GRIP

  _logger.log("%s AFTER_GRIP vel=%s lateral=%.4f" % [_sim_tag(tick), velocity, lateral_velocity])

  velocity.y -= GRAVITY * delta

  kart.global_position = state.position
  kart.rotation.y = rotation_y
  var remaining := velocity * delta
  for _i in 2:
    var collision := kart.move_and_collide(remaining)
    if not collision:
      break
    var normal := collision.get_normal()
    remaining = remaining.slide(normal)
    velocity = velocity.slide(normal)
    if normal.dot(Vector3.UP) > 0.7:
      velocity.y = 0.0

  _logger.log("%s AFTER_COLLIDE vel=%s" % [_sim_tag(tick), velocity])

  var position := kart.global_position

  kart.velocity = velocity
  kart.wheel_turn = wheel_turn

  _logger.log("%s OUT pos=%s vel=%s rot=%.4f wt=%.4f" % [
    _sim_tag(tick), position, velocity, rotation_y, wheel_turn])

  return {
    "wheel_turn": wheel_turn,
    "position": position,
    "rotation_y": rotation_y,
    "velocity": velocity,
  }
