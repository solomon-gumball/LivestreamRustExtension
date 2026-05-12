class_name MovementSynchronizer
extends Node

var local_input_buffer: CircularBuffer = CircularBuffer.new()

const INPUT_BUFFER_DEPTH := 8
const SERVER_SYNC_RATE: float = 1.0 / 20.0

var _current_tick := 0
var _sync_accumulator: float = 0.0

var owner_peer_id: int = -1
var is_host: bool = false
var is_owning_peer := false

var _server_input_store: Dictionary = {}
var _last_consumed_input: Dictionary = {}
var _has_initial_state := false
var _remote_state_target: Dictionary = {}
var physics_state: Dictionary = {}

var _logger := SimLogger.new()

func _init() -> void:
  add_child(_logger)

func _ready() -> void:
  _last_consumed_input = get_default_input()
  MultiplayerClient.packet_received.connect(_handle_incoming_peer_packet)
  is_host = MultiplayerClient.is_lobby_host()

  await get_tree().process_frame
  physics_state = get_initial_state()
  is_owning_peer = owner_peer_id == MultiplayerClient.my_peer_id()
  _logger.setup(is_host, owner_peer_id)
  if is_owning_peer:
    _bind_inputs()
  SessionSynchronizer.get_instance().register_synchronizer(self)
  _on_synchronizer_ready()

func _exit_tree() -> void:
  if is_owning_peer:
    _unbind_inputs()
  SessionSynchronizer.get_instance().unregister_synchronizer(self)

func _handle_incoming_peer_packet(sender_id: int, packet: Dictionary) -> void:
  if owner_peer_id != packet.get("owner_peer_id", 0): return

  match packet.type:
    SessionSynchronizer.GlobalGameMessage.ServerMovementState:
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
    SessionSynchronizer.GlobalGameMessage.ClientMovementInputs:
      if !is_host: return
      var tick: int = packet.get("net_sim_tick", -1)
      if tick >= 0 and not _server_input_store.has(tick):
        _server_input_store[tick] = packet.get("input", {})
    _:
      _on_extra_packet(sender_id, packet)

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

  if needs_correction(local_state, server_state):
    _logger.log("correction at server_tick=%d" % server_tick, true)
    resimulate(server_tick, server_state)

func resimulate(from_tick: int, authoritative_state: Dictionary) -> void:
  var pre_state := physics_state.duplicate()

  var state := authoritative_state
  for tick in range(from_tick + 1, _current_tick):
    var entry := local_input_buffer.get_entry(tick)
    var input: Dictionary = entry.get("input", _last_consumed_input)
    state = simulate_one_frame(input, state, tick)
    local_input_buffer.store(tick, input, state)
  physics_state = state

  apply_visual_correction(pre_state, state)

func consume_input_for_tick(tick: int) -> Dictionary:
  if _server_input_store.has(tick):
    _last_consumed_input = _server_input_store[tick]
    _server_input_store.erase(tick)
  else:
    _logger.log("HOST missing input tick=%d using_prev=%s" % [
      tick, _last_consumed_input
    ], true)
  return _last_consumed_input

func _sim_tag(tick: int) -> String:
  return "[sim:%d peer:%d host:%s]" % [tick, owner_peer_id, is_host]

var did_start_simulating = false
func simulate_tick(current_tick: int, delta: float) -> void:
  if not is_host and not _has_initial_state: return
  _current_tick = current_tick

  if !is_host and !did_start_simulating:
    print("CLIENT STARTED SIMULATING!")
    did_start_simulating = true

  if is_owning_peer:
    var input_vector := _sample_input()
    physics_state = simulate_one_frame(input_vector, physics_state, current_tick)
    local_input_buffer.store(current_tick, input_vector, physics_state)

    if !is_host:
      MultiplayerClient.send_packet({
        "type": SessionSynchronizer.GlobalGameMessage.ClientMovementInputs,
        "input": input_vector,
        "net_sim_tick": current_tick,
        "owner_peer_id": owner_peer_id
      })
    else:
      _sync_accumulator += delta / Engine.time_scale
      if _sync_accumulator >= SERVER_SYNC_RATE:
        _sync_accumulator -= SERVER_SYNC_RATE
        MultiplayerClient.send_packet({
          "type": SessionSynchronizer.GlobalGameMessage.ServerMovementState,
          "net_sim_tick": current_tick,
          "owner_peer_id": owner_peer_id,
          "state": physics_state,
        })

  elif !is_owning_peer and !is_host:
    if _remote_state_target.is_empty(): return
    physics_state = interpolate_state(physics_state, _remote_state_target, delta)
    apply_state_to_entity(physics_state)

  elif is_host:
    var host_input := consume_input_for_tick(current_tick)
    physics_state = simulate_one_frame(host_input, physics_state, current_tick)

    _sync_accumulator += delta / Engine.time_scale
    if _sync_accumulator >= SERVER_SYNC_RATE:
      _sync_accumulator -= SERVER_SYNC_RATE
      MultiplayerClient.send_packet({
        "type": SessionSynchronizer.GlobalGameMessage.ServerMovementState,
        "net_sim_tick": current_tick,
        "owner_peer_id": owner_peer_id,
        "state": physics_state,
      })

    var cutoff := current_tick - INPUT_BUFFER_DEPTH
    for t in _server_input_store.keys():
      if t < cutoff:
        _server_input_store.erase(t)

# --- Abstract methods (must be overridden in subclass) ---

func simulate_one_frame(_input: Dictionary, _state: Dictionary, _tick: int) -> Dictionary:
  assert(false, "MovementSynchronizer: simulate_one_frame() must be implemented by subclass")
  return {}

func _sample_input() -> Dictionary:
  assert(false, "MovementSynchronizer: _sample_input() must be implemented by subclass")
  return {}

func get_default_input() -> Dictionary:
  assert(false, "MovementSynchronizer: get_default_input() must be implemented by subclass")
  return {}

func get_initial_state() -> Dictionary:
  assert(false, "MovementSynchronizer: get_initial_state() must be implemented by subclass")
  return {}

func apply_state_to_entity(_state: Dictionary) -> void:
  assert(false, "MovementSynchronizer: apply_state_to_entity() must be implemented by subclass")

func apply_visual_correction(_pre_state: Dictionary, _post_state: Dictionary) -> void:
  assert(false, "MovementSynchronizer: apply_visual_correction() must be implemented by subclass")

func needs_correction(_local_state: Dictionary, _server_state: Dictionary) -> bool:
  assert(false, "MovementSynchronizer: needs_correction() must be implemented by subclass")
  return false

func interpolate_state(_from_state: Dictionary, _to_state: Dictionary, _delta: float) -> Dictionary:
  assert(false, "MovementSynchronizer: interpolate_state() must be implemented by subclass")
  return {}

# --- Virtual methods (optional to override in subclass) ---

func _bind_inputs() -> void:
  pass

func _unbind_inputs() -> void:
  pass

func _on_synchronizer_ready() -> void:
  pass

func _on_extra_packet(_sender_id: int, _packet: Dictionary) -> void:
  pass

# --- Inner class ---

class CircularBuffer:
  const BUFFER_SIZE := 256
  var input_buffer := []

  func _init() -> void:
    input_buffer.resize(BUFFER_SIZE)

  func store(tick: int, input: Dictionary, state: Variant) -> void:
    var slot = tick % BUFFER_SIZE
    input_buffer[slot] = { "tick": tick, "input": input, "state": state }

  func get_entry(tick: int) -> Dictionary:
    var slot = tick % BUFFER_SIZE
    var entry = input_buffer[slot]
    if entry == null or entry.tick != tick:
      if entry and entry.tick != tick: print("MISMATCH: entry.tick -> ", entry.tick, " tick -> ", tick)
      return {}
    return entry
