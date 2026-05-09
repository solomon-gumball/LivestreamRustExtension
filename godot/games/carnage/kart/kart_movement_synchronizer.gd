class_name KartMovementSynchronizer
extends Node

@export var kart: KartBot

var local_input_buffer: CircularBuffer = CircularBuffer.new()

const TICK_RATE_HZ := 60
const INPUT_BUFFER_DEPTH := 8 # ticks  (~133ms)
const MARGIN_TICKS := 3
const SERVER_SYNC_RATE: float = 1.0 / 20.0

var net_sim_tick := 0
var net_tick_update_timer: Timer = null
var _initial_tick_set := false
var _sync_accumulator: float = 0.0

var owner_peer_id: int = -1
var is_host: bool = false
var is_owning_peer := false

var _server_input_store: Dictionary = {}
var _last_consumed_input: Vector2 = Vector2.ZERO
var _has_initial_state := false
var physics_state: Dictionary = {
  "position": Vector3.ZERO,
  "velocity": Vector3.ZERO,
  "rotation_y": 0.0
}

var mappings := {
  "move_forward": KEY_W,
  "move_back": KEY_S,
  "turn_left": KEY_A,
  "turn_right": KEY_D,
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
  }
  _initial_tick_set = is_host
  _request_net_tick_update()
  is_owning_peer = owner_peer_id == MultiplayerClient.my_peer_id()

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

      if !_initial_tick_set:
        net_sim_tick = new_target_tick
      else:
        if new_target_tick > net_sim_tick:
          net_sim_tick += 1
        elif new_target_tick < net_sim_tick:
          net_sim_tick -= 1

      _initial_tick_set = true
    Carnage.CarnageGameMessage.ServerKartState:
      if is_host: return
      var server_physics_state: Dictionary = packet.get("state")
      var server_tick: int = packet.get("net_sim_tick")
      if !_has_initial_state:
        physics_state = server_physics_state
        _has_initial_state = true
        return
      reconcile_server_update(server_tick, server_physics_state)
    Carnage.CarnageGameMessage.ClientKartInputs:
      if !is_host: return
      var tick: int = packet.get("net_sim_tick", -1)
      var input: Vector2 = packet.get("input", Vector2.ZERO)
      if tick >= 0 and not _server_input_store.has(tick):
        _server_input_store[tick] = input

const POS_CORRECTION_THRESHOLD := 0.1
func reconcile_server_update(server_tick: int, server_state: Dictionary) -> void:
  var local_predicted_state: Dictionary = local_input_buffer.get_entry(server_tick)

  # if no local state, resimulate
  if local_predicted_state.keys().size() == 0:
    resimulate(server_tick, server_state)
    return
  
  var local_pos: Vector3 = local_predicted_state.get("state", {}).get("position", Vector3.ZERO)
  var server_pos: Vector3 = server_state.get("position", Vector3.ZERO)
  if local_pos.distance_to(server_pos) > POS_CORRECTION_THRESHOLD:
    print("correction!")
    resimulate(server_tick, server_state)

func resimulate(from_tick: int, authoritative_state: Dictionary) -> void:
  var state := authoritative_state
  for tick in range(from_tick, net_sim_tick):
    var entry := local_input_buffer.get_entry(tick)
    var input := entry.get("input", Vector2.ZERO) as Vector2
    state = simulate_one_frame(input, state)
  physics_state = state

func consume_input_for_tick(tick: int) -> Vector2:
  if _server_input_store.has(tick):
    _last_consumed_input = _server_input_store[tick]
    _server_input_store.erase(tick)
  return _last_consumed_input

func simulate_one_frame(input_vec: Vector2, state: Dictionary) -> Dictionary:
  var delta := 1.0 / 60.0 # 60hz physics
  var acceleration := input_vec[0]
  kart.global_position = state.position
  kart.rotation.y = state.rotation_y
  kart.velocity = state.velocity

  if abs(acceleration) > 0.0:
    kart.velocity += kart.global_basis.z * acceleration * 0.05
    kart.velocity = kart.velocity.limit_length(1.0)
  else:
    kart.velocity = kart.velocity.lerp(Vector3.ZERO, delta * 5.0)

  kart.move_and_slide()

  return {
    "position": kart.global_position,
    "rotation_y": kart.rotation.y,
    "velocity": kart.velocity,
  }

func _physics_process(delta: float) -> void:
  if !_initial_tick_set: return
  if !is_host and !_has_initial_state: return

  if is_owning_peer:
    var input_vector := Input.get_vector("move_back", "move_forward", "turn_right", "turn_left")
    physics_state = simulate_one_frame(input_vector, physics_state)
    local_input_buffer.store(net_sim_tick, input_vector, physics_state)

    if !is_host:
      MultiplayerClient.send_packet({
        "type": Carnage.CarnageGameMessage.ClientKartInputs,
        "input": input_vector,
        "net_sim_tick": net_sim_tick,
        "owner_peer_id": owner_peer_id
      })
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
  const BUFFER_SIZE := 128  # must be power of 2 for fast modulo
  var input_buffer := []

  func _init() -> void:
    input_buffer.resize(BUFFER_SIZE)

  func store(tick: int, input: Vector2, state: Variant):
    var slot = tick % BUFFER_SIZE
    input_buffer[slot] = { "tick": tick, "input": input, "state": state }

  func get_entry(tick: int) -> Dictionary:
    var slot = tick % BUFFER_SIZE
    var entry = input_buffer[slot]
    if entry == null or entry.tick != tick:
      return {} # was overwritten by a newer tick
    return entry
