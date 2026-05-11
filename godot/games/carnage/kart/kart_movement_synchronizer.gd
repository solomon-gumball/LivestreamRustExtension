class_name KartMovementSynchronizer
extends Node

signal punch_landed(attacker_peer_id: int, target_peer_id: int)

@export var kart: KartBot

var local_input_buffer: CircularBuffer = CircularBuffer.new()

const INPUT_BUFFER_DEPTH := 8
const SERVER_SYNC_RATE: float = 1.0 / 20.0

var _current_tick := 0
var _sync_accumulator: float = 0.0

var owner_peer_id: int = -1
var is_host: bool = false
var is_owning_peer := false

var _server_input_store: Dictionary = {}
var _last_consumed_input: Dictionary = { "move": Vector2.ZERO, "punch_pressed": false }
var _has_initial_state := false
var _remote_state_target: Dictionary = {}
var physics_state: Dictionary = {
  "position": Vector3.ZERO,
  "velocity": Vector3.ZERO,
  "rotation_y": 0.0,
  "wheel_turn": 0.0,
}

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

func _ready() -> void:
  _bind_inputs()
  MultiplayerClient.packet_received.connect(_handle_incoming_peer_packet)
  is_host = MultiplayerClient.is_lobby_host()

  await get_tree().process_frame
  physics_state = {
    "position": kart.global_position,
    "rotation_y": kart.rotation.y,
    "velocity": Vector3.ZERO,
    "wheel_turn": 0.0,
  }
  is_owning_peer = owner_peer_id == MultiplayerClient.my_peer_id()
  _logger.setup(is_host, owner_peer_id)
  SessionSynchronizer.get_instance().register_kart(self)

func _enter_tree() -> void:
  if is_owning_peer: _bind_inputs()

func _exit_tree() -> void:
  if is_owning_peer: _unbind_inputs()
  SessionSynchronizer.get_instance().unregister_kart(self)

func _handle_incoming_peer_packet(_sender_id: int, packet: Dictionary) -> void:
  if owner_peer_id != packet.get("owner_peer_id", 0): return

  match packet.type:
    Carnage.CarnageGameMessage.ServerKartState:
      if is_host: return
      var server_physics_state: Dictionary = packet.get("state")
      var server_tick: int = packet.get("net_sim_tick")
      if !_has_initial_state:
        physics_state = server_physics_state
        _remote_state_target = server_physics_state
        _has_initial_state = true
        return
      if is_owning_peer:
        reconcile_server_update(server_tick, server_physics_state)
      else:
        _remote_state_target = server_physics_state
    Carnage.CarnageGameMessage.ClientKartInputs:
      if !is_host: return
      var tick: int = packet.get("net_sim_tick", -1)
      if tick >= 0 and not _server_input_store.has(tick):
        _server_input_store[tick] = packet.get("input", {})
    Carnage.CarnageGameMessage.ServerKartPunch:
      if is_owning_peer: return  # already triggered locally on button press
      kart.punch_cosmetic()

const POS_CORRECTION_THRESHOLD := 0.1
const VEL_CORRECTION_THRESHOLD := 0.1
const ROT_CORRECTION_THRESHOLD := deg_to_rad(1.0)
const WHEEL_TURN_CORRECTION_THRESHOLD := 0.02

func reconcile_server_update(server_tick: int, server_state: Dictionary) -> void:
  var local_predicted_state: Dictionary = local_input_buffer.get_entry(server_tick)

  if local_predicted_state.keys().size() == 0:
    _logger.log(
      "LOCAL missing input server_tick=%d my_local_tick=%d" %
      [server_tick, _current_tick],
      true
    )
    physics_state = server_state
    return

  var local_state: Dictionary = local_predicted_state.get("state", {})
  var local_wheel_turn: float = local_state.get("wheel_turn", 0.0)
  var local_pos: Vector3 = local_state.get("position", Vector3.ZERO)
  var local_vel: Vector3 = local_state.get("velocity", Vector3.ZERO)
  var local_rot_y: float = local_state.get("rotation_y", 0.0)
  var server_wheel_turn: float = server_state.get("wheel_turn", 0.0)
  var server_pos: Vector3 = server_state.get("position", Vector3.ZERO)
  var server_vel: Vector3 = server_state.get("velocity", Vector3.ZERO)
  var server_rot_y: float = server_state.get("rotation_y", 0.0)

  var pos_err := local_pos.distance_to(server_pos)
  var vel_err := local_vel.distance_to(server_vel)
  var rot_err: float = abs(local_rot_y - server_rot_y)
  var wheel_turn_err: float = abs(local_wheel_turn - server_wheel_turn)

  if pos_err > POS_CORRECTION_THRESHOLD or \
     vel_err > VEL_CORRECTION_THRESHOLD or \
     rot_err > ROT_CORRECTION_THRESHOLD or \
     wheel_turn_err > WHEEL_TURN_CORRECTION_THRESHOLD:
    _logger.log(
      "correction at server_tick=%d pos_err=%.4f vel_err=%.4f rot_err=%.4f wt_err=%.4f" %
      [server_tick, pos_err, vel_err, rot_err, wheel_turn_err],
      true
    )
    resimulate(server_tick, server_state)

func resimulate(from_tick: int, authoritative_state: Dictionary) -> void:
  var pre_pos: Vector3 = physics_state.get("position", Vector3.ZERO)
  var pre_rot_y: float = physics_state.get("rotation_y", 0.0)

  var state := authoritative_state
  for tick in range(from_tick + 1, _current_tick):
    var entry := local_input_buffer.get_entry(tick)
    var input: Dictionary = entry.get("input", _last_consumed_input)
    state = simulate_one_frame(input, state, tick)
    local_input_buffer.store(tick, input, state)
  physics_state = state

  var pos_delta: Vector3 = pre_pos - state.get("position", Vector3.ZERO)
  var rot_delta: float = pre_rot_y - state.get("rotation_y", 0.0)
  kart.apply_visual_correction(pos_delta, rot_delta)

func consume_input_for_tick(tick: int) -> Dictionary:
  if _server_input_store.has(tick):
    _last_consumed_input = _server_input_store[tick]
    _server_input_store.erase(tick)
  else:
    _logger.log("HOST missing input tick=%d using_prev=%s" % [
      tick, _last_consumed_input
    ], true)
  return _last_consumed_input

const MAX_SPEED := 4.0
const ACCELERATION := 0.1
const DRAG := 3.0

const GRAVITY := 9.8
const TURN_RAMP := 1.0
const GRIP := 0.05
const MAX_WHEEL_ANGLE := deg_to_rad(45.0)
const WHEEL_TURN_SPEED := deg_to_rad(100.0)

var _logger := SimLogger.new()

func _init() -> void:
  add_child(_logger)

func _sim_tag(tick: int) -> String:
  return "[sim:%d peer:%d host:%s]" % [tick, owner_peer_id, is_host]

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

func _sample_input() -> Dictionary:
  return {
    "move": Input.get_vector("move_back", "move_forward", "turn_right", "turn_left"),
    "punch_pressed": Input.is_action_just_pressed("punch"),
  }

var did_start_simulating = false
func simulate_tick(current_tick: int, delta: float) -> void:
  if not is_host and not _has_initial_state: return
  _current_tick = current_tick

  if !is_host and !did_start_simulating:
    print("CLIENT STARTED SIMULATING!")
    did_start_simulating = true

  if is_owning_peer:
    var input_vector := _sample_input()

    # if input_vector.get("punch_pressed", false):
    #   kart.punch_cosmetic()

    physics_state = simulate_one_frame(input_vector, physics_state, current_tick)
    local_input_buffer.store(current_tick, input_vector, physics_state)

    if !is_host:
      MultiplayerClient.send_packet({
        "type": Carnage.CarnageGameMessage.ClientKartInputs,
        "input": input_vector,
        "net_sim_tick": current_tick,
        "owner_peer_id": owner_peer_id
      })
    else:
      _sync_accumulator += delta / Engine.time_scale
      if _sync_accumulator >= SERVER_SYNC_RATE:
        _sync_accumulator -= SERVER_SYNC_RATE
        MultiplayerClient.send_packet({
          "type": Carnage.CarnageGameMessage.ServerKartState,
          "net_sim_tick": current_tick,
          "owner_peer_id": owner_peer_id,
          "state": physics_state,
        })

  elif !is_owning_peer and !is_host:
    if _remote_state_target.is_empty(): return
    # var weight := (1.0 / SERVER_SYNC_RATE) * delta
    var weight := delta * 5.0
    physics_state = {
      "position": physics_state.position.lerp(_remote_state_target.position, weight),
      "rotation_y": lerp(physics_state.rotation_y, _remote_state_target.rotation_y, weight),
      "velocity": _remote_state_target.get("velocity", Vector3.ZERO),
      "wheel_turn": lerp(physics_state.wheel_turn, _remote_state_target.get("wheel_turn", 0.0), weight),
    }
    kart.global_position = physics_state.position
    kart.rotation.y = physics_state.rotation_y
    kart.wheel_turn = physics_state.wheel_turn

  elif is_host:
    var host_input := consume_input_for_tick(current_tick)
    physics_state = simulate_one_frame(host_input, physics_state, current_tick)

    _sync_accumulator += delta / Engine.time_scale
    if _sync_accumulator >= SERVER_SYNC_RATE:
      _sync_accumulator -= SERVER_SYNC_RATE
      MultiplayerClient.send_packet({
        "type": Carnage.CarnageGameMessage.ServerKartState,
        "net_sim_tick": current_tick,
        "owner_peer_id": owner_peer_id,
        "state": physics_state,
      })

    var cutoff := current_tick - INPUT_BUFFER_DEPTH
    for t in _server_input_store.keys():
      if t < cutoff:
        _server_input_store.erase(t)

class CircularBuffer:
  const BUFFER_SIZE := 256
  var input_buffer := []

  func _init() -> void:
    input_buffer.resize(BUFFER_SIZE)

  func store(tick: int, input: Dictionary, state: Variant):
    var slot = tick % BUFFER_SIZE
    input_buffer[slot] = { "tick": tick, "input": input, "state": state }

  func get_entry(tick: int) -> Dictionary:
    var slot = tick % BUFFER_SIZE
    var entry = input_buffer[slot]
    if entry == null or entry.tick != tick:
      if entry and entry.tick != tick: print("MISMATCH: entry.tick -> ", entry.tick, " tick -> ", tick)
      return {}
    return entry
