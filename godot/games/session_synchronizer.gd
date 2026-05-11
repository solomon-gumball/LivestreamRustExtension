class_name SessionSynchronizer
extends Node

static var _instance: SessionSynchronizer = null

func _init() -> void:
  _instance = self

static func get_instance() -> SessionSynchronizer:
  if _instance == null:
    assert(false, "SessionSynchronizer instance not found! Make sure to add it to the scene tree!")
  return _instance

enum GlobalGameMessage {
  ClientReady = 2000,
  CamFollow,
  UpdateAnimation,
  AnimationStateRefresh,
  SessionStateRefresh,
  PingNetTick,
  PongNetTick,
}

signal rtt_updated(rtt_msec: int, net_tick_prediction_offset: int)
signal all_peers_ready()
signal peer_is_ready(peer_id: int)

var state: Dictionary[int, bool] = {}
var _lobby: Lobby = null
var _all_peers_ready_fired: bool = false
var current_ping := 0

# --- Sim clock ---
const TICK_RATE_HZ := 60
const INPUT_BUFFER_DEPTH := 8
const MARGIN_TICKS := 3

var net_sim_tick := 0
var _initial_tick_set := false
var is_host := false

var _skip_next_frame := false
var _run_extra_frame := false

var _registered_karts: Array[KartMovementSynchronizer] = []
var _ping_timer: Timer = null

func _ready() -> void:
  MultiplayerClient.packet_received.connect(_handle_peer_packet)
  is_host = MultiplayerClient.is_lobby_host()
  _initial_tick_set = is_host

  _ping_timer = Timer.new()
  _ping_timer.wait_time = 8.0
  _ping_timer.one_shot = false
  _ping_timer.autostart = true
  _ping_timer.timeout.connect(_send_ping)
  add_child(_ping_timer)

  _send_ping()

func _exit_tree() -> void:
  if _instance == self:
    _instance = null
  MultiplayerClient.packet_received.disconnect(_handle_peer_packet)

func setup(lobby: Lobby) -> void:
  _lobby = lobby

func register_kart(kart_sync: KartMovementSynchronizer) -> void:
  if not _registered_karts.has(kart_sync):
    _registered_karts.append(kart_sync)

func unregister_kart(kart_sync: KartMovementSynchronizer) -> void:
  _registered_karts.erase(kart_sync)

func _send_ping() -> void:
  if is_host: return
  MultiplayerClient.send_packet({
    "type": GlobalGameMessage.PingNetTick,
    "client_time": Time.get_ticks_msec(),
  })

func _handle_peer_packet(sender_id: int, packet: Dictionary) -> void:
  match packet.type:
    GlobalGameMessage.ClientReady:
      state[sender_id] = true
      _new_peer_ready(sender_id)
      peer_is_ready.emit(sender_id)
      _check_all_peers_ready()
    GlobalGameMessage.SessionStateRefresh:
      var received: Dictionary = packet.get("state", {})
      for peer_id in received:
        if received[peer_id]:
          state[peer_id] = true
      _check_all_peers_ready()
    GlobalGameMessage.PingNetTick:
      if not is_host: return
      MultiplayerClient.send_packet({
        "type": GlobalGameMessage.PongNetTick,
        "client_time": packet.get("client_time", 0),
        "net_sim_tick": net_sim_tick,
      }, sender_id)
    GlobalGameMessage.PongNetTick:
      if is_host: return
      var client_time_ms := packet.get("client_time", -1) as int
      var rtt_msec := Time.get_ticks_msec() - client_time_ms
      var server_net_tick := packet.get("net_sim_tick", 0) as int
      var one_way_ticks := int(round((rtt_msec / 2.0) / 1000.0 * TICK_RATE_HZ))
      current_ping = rtt_msec

      var new_target_tick := server_net_tick + INPUT_BUFFER_DEPTH + one_way_ticks + MARGIN_TICKS

      if not _initial_tick_set:
        net_sim_tick = new_target_tick
        _initial_tick_set = true
      elif abs(net_sim_tick - new_target_tick) > 2:
        if new_target_tick > net_sim_tick:
          print("[SessionSynchronizer] latency increased, running extra frame")
          _run_extra_frame = true
        elif new_target_tick < net_sim_tick:
          print("[SessionSynchronizer] latency decreased, skipping next frame")
          _skip_next_frame = true

      rtt_updated.emit(current_ping, net_sim_tick - server_net_tick)

func _physics_process(delta: float) -> void:
  if not _initial_tick_set: return

  if _skip_next_frame:
    _skip_next_frame = false
    return

  _tick_all_karts(delta)

  if _run_extra_frame:
    _run_extra_frame = false
    _tick_all_karts(delta)

func _tick_all_karts(delta: float) -> void:
  for kart_sync in _registered_karts:
    kart_sync.simulate_tick(net_sim_tick, delta)
  net_sim_tick += 1

func _new_peer_ready(peer_id: int) -> void:
  MultiplayerClient.send_packet(
    { "type": GlobalGameMessage.SessionStateRefresh, "state": state },
    peer_id,
    MultiplayerPeer.TRANSFER_MODE_RELIABLE
  )

func notify_ready() -> void:
  if MultiplayerClient.state.current is MultiplayerClient.Disconnected:
    all_peers_ready.emit()
    return
  state[MultiplayerClient.my_peer_id()] = true
  print(MultiplayerClient.my_peer_id(), ' local ready state -> ', JSON.stringify(state))
  MultiplayerClient.send_packet(
    { "type": GlobalGameMessage.ClientReady },
    MultiplayerPeer.TARGET_PEER_BROADCAST,
    MultiplayerPeer.TRANSFER_MODE_RELIABLE
  )
  _check_all_peers_ready()

func _check_all_peers_ready() -> void:
  if _all_peers_ready_fired: return
  if _lobby == null: return
  for peer in _lobby.peers:
    if not peer.connected: continue
    if not state.get(peer.peer_id, false): return
  _all_peers_ready_fired = true
  all_peers_ready.emit()
