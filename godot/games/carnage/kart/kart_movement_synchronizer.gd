class_name KartMovementSynchronizer
extends Node

var local_input_buffer: CircularBuffer = CircularBuffer.new()

const TICK_RATE := 60
const INPUT_BUFFER_DEPTH := 8 # ticks  (~133ms)
const MARGIN_TICKS := 3
const SERVER_SYNC_RATE: float = 1.0 / 20.0

var net_sim_tick := 0
var net_tick_update_timer: Timer = null
var initial_tick_set := false
var _sync_accumulator: float = 0.0

var owner_peer_id: int = -1
var kart: KartBot = null
var is_host: bool = false

var _server_input_store: Dictionary = {}
var _last_consumed_input: Vector2 = Vector2.ZERO
var physics_state: Dictionary = { "position": Vector3.ZERO, "velocity": Vector3.ZERO, "rotation_y": 0.0 }

func _ready() -> void:
  MultiplayerClient.connected_state.packet_received.connect(_handle_incoming_peer_packet)
  is_host = MultiplayerClient.is_lobby_host()

  net_tick_update_timer = Timer.new()
  net_tick_update_timer.one_shot = false
  net_tick_update_timer.autostart = false
  add_child(net_tick_update_timer)
  net_tick_update_timer.timeout.connect(_request_net_tick_update)
  net_tick_update_timer.start(8.0)

  net_sim_tick = INPUT_BUFFER_DEPTH

func _request_net_tick_update() -> void:
  if !is_host:
    MultiplayerClient.send_packet({
      "type": Carnage.CarnageGameMessage.PingNetTick,
      "client_time": Time.get_ticks_msec(),
      "owner_peer_id": owner_peer_id
    })

func _handle_incoming_peer_packet(sender_id: int, packet: Dictionary) -> void:
  # Only listen to packets directed to this peer
  if owner_peer_id != packet.get("owner_peer_id", 0): return

  match packet.type:
    Carnage.CarnageGameMessage.PingNetTick:
      MultiplayerClient.send_packet({
        "type": Carnage.CarnageGameMessage.PongNetTick,
        "client_time": Time.get_ticks_msec(),
        "owner_peer_id": owner_peer_id
      })
    Carnage.CarnageGameMessage.PongNetTick:
      var rtt_msec := Time.get_ticks_msec() - (packet.get("client_time", -1) as int)
      @warning_ignore("INTEGER_DIVISION")
      var new_target_tick := INPUT_BUFFER_DEPTH + (rtt_msec / 2) + MARGIN_TICKS

      if !initial_tick_set:
        net_sim_tick = new_target_tick
      else:
        if new_target_tick > net_sim_tick:
          net_sim_tick += 1
        elif new_target_tick < net_sim_tick:
          net_sim_tick -= 1

      initial_tick_set = true
    Carnage.CarnageGameMessage.ServerKartState:
      if is_host: return
      var server_physics_state: Dictionary = packet.get("state")
      var server_tick: int = packet.get("net_sim_tick")
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

func simulate_one_frame(_input_vec: Vector2, state: Dictionary) -> Dictionary:
  return state

func _physics_process(delta: float) -> void:
  if !initial_tick_set: return

  if !is_host:
    var input_vector := Input.get_vector("move_forward", "move_back", "move_right", "move_left")
    physics_state = simulate_one_frame(input_vector, physics_state)
    local_input_buffer.store(net_sim_tick, input_vector, physics_state)

    MultiplayerClient.send_packet({
      "type": Carnage.CarnageGameMessage.ClientKartInputs,
      "input": input_vector,
      "net_sim_tick": net_sim_tick,
      "owner_peer_id": owner_peer_id
    })
  else:
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

func _input(event: InputEvent) -> void:
  pass

class CircularBuffer:
  const BUFFER_SIZE := 128  # must be power of 2 for fast modulo
  var input_buffer := []

  func _ready():
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