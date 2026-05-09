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
      pass
    Carnage.CarnageGameMessage.ClientKartInputs:
      pass

func simulate_one_frame() -> void:
  pass

func _physics_process(delta: float) -> void:
  if !initial_tick_set: return

  var input_vector := Input.get_vector("move_forward", "move_back", "move_right", "move_left")

  # TODO: Run simulation here
  simulate_one_frame()

  if !is_host:
    # Client sends input
    MultiplayerClient.send_packet({
      "type": Carnage.CarnageGameMessage.ClientKartInputs,
      "input": input_vector,
      "net_sim_tick": net_sim_tick,
      "owner_peer_id": owner_peer_id
    })
    local_input_buffer.store(net_sim_tick, input_vector, { "pos": kart.global_position, "rot": kart.global_rotation })

  if is_host:
    _sync_accumulator += delta / Engine.time_scale
    if _sync_accumulator >= SERVER_SYNC_RATE:
      _sync_accumulator -= SERVER_SYNC_RATE
      MultiplayerClient.send_packet({
        "type": Carnage.CarnageGameMessage.ServerKartState,
        "net_sim_tick": net_sim_tick,
        "owner_peer_id": owner_peer_id,
        "position": kart.global_position,
        "rotation": kart.global_rotation,
      })
  
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
          return {}  # was overwritten by a newer tick
      return entry