class_name KartMovementSynchronizer
extends Node

signal punch_landed(attacker_peer_id: int, target_peer_id: int)

@export var kart: KartBot

var local_input_buffer: CircularBuffer = CircularBuffer.new()

const TICK_RATE_HZ := 60
const INPUT_BUFFER_DEPTH := 8 # 8 ticks * 1/60 = (~133ms)
const MARGIN_TICKS := 10 # Accounts for jitter
const SERVER_SYNC_RATE: float = 1.0 / 20.0

var net_sim_tick := 0
var net_tick_update_timer: Timer = null
var _initial_tick_set := false
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
  # is_host = peer

  net_tick_update_timer = Timer.new()
  net_tick_update_timer.one_shot = false
  net_tick_update_timer.autostart = false
  add_child(net_tick_update_timer)
  net_tick_update_timer.timeout.connect(_request_net_tick_update)
  net_tick_update_timer.start(8.0)

  net_sim_tick = 0

  await get_tree().process_frame
  physics_state = {
    "position": kart.global_position,
    "rotation_y": kart.rotation.y,
    "velocity": Vector3.ZERO,
    "wheel_turn": 0.0,
  }
  _initial_tick_set = is_host
  _request_net_tick_update()
  is_owning_peer = owner_peer_id == MultiplayerClient.my_peer_id()
  _logger.setup(is_host, owner_peer_id)

func _enter_tree() -> void:
  if is_owning_peer: _bind_inputs()

func _exit_tree() -> void:
  if is_owning_peer: _unbind_inputs()

func _request_net_tick_update() -> void:
  if !is_host:
    MultiplayerClient.send_packet({
      "type": Carnage.CarnageGameMessage.PingNetTick,
      "client_time": Time.get_ticks_msec(),
      "owner_peer_id": owner_peer_id
    })

func _handle_incoming_peer_packet(_sender_id: int, packet: Dictionary) -> void:
  # Only listen to packets directed to this peer
  if owner_peer_id != packet.get("owner_peer_id", 0): return

  match packet.type:
    Carnage.CarnageGameMessage.PingNetTick:
      MultiplayerClient.send_packet({
        "type": Carnage.CarnageGameMessage.PongNetTick,
        "client_time": packet.get("client_time", 0),
        "owner_peer_id": owner_peer_id,
        "net_sim_tick": net_sim_tick
      })
    Carnage.CarnageGameMessage.PongNetTick:
      var client_time_ms := packet.get("client_time", -1) as int
      var rtt_msec := Time.get_ticks_msec() - client_time_ms
      var server_net_tick := packet.get("net_sim_tick", 0) as int
      var one_way_ticks := int(round((rtt_msec / 2.0) / 1000.0 * TICK_RATE_HZ))
      var new_target_tick := server_net_tick + INPUT_BUFFER_DEPTH + one_way_ticks + MARGIN_TICKS

      if is_host: return
      if !_initial_tick_set:
        net_sim_tick = new_target_tick
      elif abs(net_sim_tick - new_target_tick) > 2:
        if new_target_tick > net_sim_tick:
          _logger.log("CLIENT latency increased significantly, incrementing local sim_tick", true)
          _physics_process(1.0 / 60.0)

        elif new_target_tick < net_sim_tick:
          _logger.log("CLIENT latency decreased significantly, decrementing local sim_tick", true)
          net_sim_tick -= 1

      _initial_tick_set = true
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

const POS_CORRECTION_THRESHOLD := 0.1
const VEL_CORRECTION_THRESHOLD := 0.1
const ROT_CORRECTION_THRESHOLD := deg_to_rad(1.0)
const WHEEL_TURN_CORRECTION_THRESHOLD := 0.02

func reconcile_server_update(server_tick: int, server_state: Dictionary) -> void:
  var local_predicted_state: Dictionary = local_input_buffer.get_entry(server_tick)

  # if no local state, snap directly — client never predicted this tick
  if local_predicted_state.keys().size() == 0:
    _logger.log(
      "LOCAL missing input server_tick=%d my_local_tick=%d" %
      [server_tick, net_sim_tick],
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
  var state := authoritative_state
  # Start from tick after correction, since correction is truth and
  # we don't need to updated that original entry
  for tick in range(from_tick + 1, net_sim_tick):
    var entry := local_input_buffer.get_entry(tick)
    var input: Dictionary = entry.get("input", _last_consumed_input)
    state = simulate_one_frame(input, state)
    local_input_buffer.store(tick, input, state)
  physics_state = state

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
const TURN_RAMP := 1.0         # how quickly turn speed scales with velocity
const GRIP := 0.02             # lateral friction factor: 1.0 = no drift, 0.0 = full ice
const MAX_WHEEL_ANGLE := deg_to_rad(45.0)
const WHEEL_TURN_SPEED := deg_to_rad(100.0)

var _logger := SimLogger.new()

func _init() -> void:
  add_child(_logger)

func _sim_tag() -> String:
  return "[sim:%d peer:%d host:%s]" % [net_sim_tick, owner_peer_id, is_host]

func simulate_one_frame(input: Dictionary, state: Dictionary) -> Dictionary:
  var delta := 1.0 / 60.0
  var input_vec: Vector2 = input.get("move", Vector2.ZERO)
  var punch_pressed: bool = input.get("punch_pressed", false)
  var throttle := input_vec[0]

  var wheel_turn: float = state.wheel_turn
  var velocity: Vector3 = state.velocity
  var rotation_y: float = state.rotation_y
  var forward := Vector3(sin(rotation_y), 0.0, cos(rotation_y))

  _logger.log("%s IN pos=%s vel=%s rot=%.4f wt=%.4f move=%s punch=%s" % [
    _sim_tag(), state.position, state.velocity, state.rotation_y, state.wheel_turn,
    input_vec, punch_pressed])

  # Acceleration / drag
  if abs(throttle) > 0.0:
    velocity += forward * throttle * ACCELERATION
    velocity = velocity.limit_length(MAX_SPEED)
  else:
    velocity = velocity.move_toward(Vector3.ZERO, delta * DRAG)

  _logger.log("%s AFTER_ACCEL vel=%s" % [_sim_tag(), velocity])

  if punch_pressed and is_host:
    kart.punch_cosmetic()
    var hit := _check_punch_overlap()
    if hit != -1:
      punch_landed.emit(owner_peer_id, hit)

  var desired_wheel_angle := input_vec[1] * MAX_WHEEL_ANGLE
  wheel_turn = move_toward(wheel_turn, desired_wheel_angle, WHEEL_TURN_SPEED * delta)
  wheel_turn = clampf(wheel_turn, -MAX_WHEEL_ANGLE, MAX_WHEEL_ANGLE)

  var speed := velocity.length()
  var travel_sign := signf(forward.dot(velocity))
  rotation_y += (wheel_turn / MAX_WHEEL_ANGLE) * speed * TURN_RAMP * travel_sign * delta

  _logger.log("%s AFTER_STEER rot=%.4f wt=%.4f" % [_sim_tag(), rotation_y, wheel_turn])

  var wheel_angle := rotation_y + wheel_turn
  var wheel_right_vector := Vector3(cos(wheel_angle), 0.0, -sin(wheel_angle))
  var lateral_velocity := wheel_right_vector.dot(velocity)
  velocity -= wheel_right_vector * lateral_velocity * GRIP

  _logger.log("%s AFTER_GRIP vel=%s lateral=%.4f" % [_sim_tag(), velocity, lateral_velocity])

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

  _logger.log("%s AFTER_COLLIDE vel=%s" % [_sim_tag(), velocity])

  var position := kart.global_position

  kart.velocity = velocity
  kart.wheel_turn = wheel_turn

  _logger.log("%s OUT pos=%s vel=%s rot=%.4f wt=%.4f" % [
    _sim_tag(), position, velocity, rotation_y, wheel_turn])

  return {
    "wheel_turn": wheel_turn,
    "position": position,
    "rotation_y": rotation_y,
    "velocity": velocity,
  }

func _check_punch_overlap() -> int:
  return -1

func _sample_input() -> Dictionary:
  return {
    "move": Input.get_vector("move_back", "move_forward", "turn_right", "turn_left"),
    "punch_pressed": Input.is_action_just_pressed("punch"),
  }

func _physics_process(delta: float) -> void:
  if !_initial_tick_set: return
  if !is_host and !_has_initial_state: return

  # Authority or autonomous proxy
  if is_owning_peer:
    var input_vector := _sample_input()

    if input_vector.get("punch_pressed", false):
      kart.punch_cosmetic()

    physics_state = simulate_one_frame(input_vector, physics_state)
    local_input_buffer.store(net_sim_tick, input_vector, physics_state)

    if !is_host:
      MultiplayerClient.send_packet({
        "type": Carnage.CarnageGameMessage.ClientKartInputs,
        "input": input_vector,  # input_vector is already the full { move, punch_pressed } dict
        "net_sim_tick": net_sim_tick,
        "owner_peer_id": owner_peer_id
      })
    else:
      _sync_accumulator += delta / Engine.time_scale
      if _sync_accumulator >= SERVER_SYNC_RATE:
        _sync_accumulator -= SERVER_SYNC_RATE
        MultiplayerClient.send_packet({
          "type": Carnage.CarnageGameMessage.ServerKartState,
          "net_sim_tick": net_sim_tick,
          "owner_peer_id": owner_peer_id,
          "state": physics_state,
        })

  # Simulated Proxy
  elif !is_owning_peer and !is_host:
    if _remote_state_target.is_empty(): return
    var weight := (1.0 / SERVER_SYNC_RATE) * delta
    physics_state = {
      "position": physics_state.position.lerp(_remote_state_target.position, weight),
      "rotation_y": lerp(physics_state.rotation_y, _remote_state_target.rotation_y, weight),
      "velocity": _remote_state_target.get("velocity", Vector3.ZERO),
      "wheel_turn": lerp(physics_state.wheel_turn, _remote_state_target.get("wheel_turn", 0.0), weight),
    }
    kart.global_position = physics_state.position
    kart.rotation.y = physics_state.rotation_y
    kart.wheel_turn = physics_state.wheel_turn
  
  # Authority for remote autonomous
  elif is_host:
    var host_input := consume_input_for_tick(net_sim_tick)
    physics_state = simulate_one_frame(host_input, physics_state)

    _sync_accumulator += delta / Engine.time_scale
    if _sync_accumulator >= SERVER_SYNC_RATE:
      _sync_accumulator -= SERVER_SYNC_RATE
      MultiplayerClient.send_packet({
        "type": Carnage.CarnageGameMessage.ServerKartState,
        "net_sim_tick": net_sim_tick,
        "owner_peer_id": owner_peer_id,
        "state": physics_state,
      })

    var cutoff := net_sim_tick - INPUT_BUFFER_DEPTH
    for tick in _server_input_store.keys():
      if tick < cutoff:
        _server_input_store.erase(tick)

  net_sim_tick += 1

class CircularBuffer:
  const BUFFER_SIZE := 256  # must be power of 2 for fast modulo
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
      return {} # was overwritten by a newer tick
    return entry
