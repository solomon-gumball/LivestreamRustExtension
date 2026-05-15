class_name SessionSynchronizer
extends StateSynchronizer

static var _instance: SessionSynchronizer = null

func _init() -> void:
  _instance = self

static func get_instance() -> SessionSynchronizer:
  if _instance == null:
    assert(false, "SessionSynchronizer instance not found! Make sure to add it to the scene tree!")
  return _instance

enum GlobalGameMessage {
  CamFollow = 2000,
  UpdateAnimation,

  ClientGameLoaded,
  PingNetTick,
  PongNetTick,

  ServerMovementState,
  ClientMovementInputs,

  StateSyncClientReady,
  StateSyncRefreshState,
}

class SessionSyncState:
  var ready_peers_map: Dictionary[int, bool] = {}
  var game_loaded_in: bool = false

signal rtt_updated(rtt_msec: int, net_tick_prediction_offset: int)
signal all_peers_ready()
signal peer_is_ready(peer_id: int)

var session_state: SessionSyncState:
  get: return state as SessionSyncState
  set(v): state = v

var _lobby: Lobby = null
var current_ping := 0

# --- Sim clock ---
const TICK_RATE_HZ := 60
const INPUT_BUFFER_DEPTH := 8
const MARGIN_TICKS := 2
const FALLBACK_START_TIMEOUT := 12.0

var net_sim_tick := 0
var _initial_tick_set := false
var is_host := false

var _skip_next_frame := false
var _run_extra_frame := false

var _registered_synchronizers: Array[MovementSynchronizer] = []
var _ping_timer: Timer = null
var _fallback_start_timer: Timer = null
var _game_loaded_in_locally: bool = false

func _ready() -> void:
  channel_id = "session"
  session_state = SessionSyncState.new()
  super()
  is_host = MultiplayerClient.is_lobby_host()
  _initial_tick_set = is_host

  _ping_timer = Timer.new()
  _ping_timer.wait_time = 8.0
  _ping_timer.one_shot = true
  _ping_timer.autostart = true
  _ping_timer.timeout.connect(_send_ping)

  if is_host:
    _fallback_start_timer = Timer.new()
    _fallback_start_timer.wait_time = FALLBACK_START_TIMEOUT
    _fallback_start_timer.one_shot = true
    _fallback_start_timer.autostart = true
    _fallback_start_timer.timeout.connect(_force_start_timeout)
    add_child(_fallback_start_timer)

  add_child(_ping_timer)

  _send_ping()

func _exit_tree() -> void:
  if _instance == self:
    _instance = null
  MultiplayerClient.packet_received.disconnect(_handle_peer_packet)

func setup(lobby: Lobby) -> void:
  _lobby = lobby

func register_synchronizer(sync: MovementSynchronizer) -> void:
  if not _registered_synchronizers.has(sync):
    _registered_synchronizers.append(sync)

func unregister_synchronizer(sync: MovementSynchronizer) -> void:
  _registered_synchronizers.erase(sync)

func _send_ping() -> void:
  if is_host: return
  send_packet({
    "type": GlobalGameMessage.PingNetTick,
    "client_time": Time.get_ticks_msec(),
  })

const DRIFT_NUDGE_THRESHOLD := 4     # ticks — use nudge
const DRIFT_RESET_THRESHOLD := 10    # ticks — hard reset

func message_received(sender_id: int, packet: Dictionary) -> void:
  match packet.type:
    GlobalGameMessage.ClientGameLoaded:
      if !is_host: return
      session_state.ready_peers_map.set(sender_id, true)
      peer_is_ready.emit(sender_id)
      _authority_check_all_peers_ready()
      send_refresh_state(MultiplayerPeer.TARGET_PEER_BROADCAST)
    GlobalGameMessage.PingNetTick:
      if not is_host: return
      send_packet({
        "type": GlobalGameMessage.PongNetTick,
        "client_time": packet.get("client_time", 0),
        "net_sim_tick": net_sim_tick,
      }, sender_id)
    GlobalGameMessage.PongNetTick:
      if is_host: return
      var client_time_ms := packet.get("client_time", -1) as int
      var rtt_msec := Time.get_ticks_msec() - client_time_ms
      var server_net_tick := packet.get("net_sim_tick", 0) as int
      var one_way_ticks := int(round((float(rtt_msec) / 2.0) / 1000.0 * TICK_RATE_HZ))
      print(rtt_msec, "ms PING - ONE WAY TICKS ", one_way_ticks)
      current_ping = rtt_msec

      var new_target_tick := server_net_tick + INPUT_BUFFER_DEPTH + one_way_ticks + MARGIN_TICKS
      var sim_tick_delta := absi(net_sim_tick - new_target_tick)

      if not _initial_tick_set:
        net_sim_tick = new_target_tick
        _initial_tick_set = true
      elif sim_tick_delta > DRIFT_NUDGE_THRESHOLD:
        if new_target_tick > net_sim_tick:
          print("[SessionSynchronizer] latency increased, running extra frame")
          _run_extra_frame = true
        elif new_target_tick < net_sim_tick:
          print("[SessionSynchronizer] latency decreased, skipping next frame")
          _skip_next_frame = true
      elif sim_tick_delta > DRIFT_RESET_THRESHOLD:
        print("[SessionSynchronizer] client simulation drifted too far. Resetting!")
        _reset_all_synchronizers()
        net_sim_tick = new_target_tick

      rtt_updated.emit(current_ping, net_sim_tick - server_net_tick)
  
  if !is_host:
    print("game is loaded -> ", session_state.game_loaded_in)
  _apply_session_state()

func _apply_session_state() -> void:
  if session_state.game_loaded_in:
    if !_game_loaded_in_locally:
      _game_loaded_in_locally = true
      all_peers_ready.emit()

func _physics_process(delta: float) -> void:
  if not _initial_tick_set: return

  if _skip_next_frame:
    _skip_next_frame = false
    return

  _tick_all_synchronizers(delta)

  if _run_extra_frame:
    _run_extra_frame = false
    _tick_all_synchronizers(delta)

func _reset_all_synchronizers() -> void:
  for sync in _registered_synchronizers:
    sync.clear_local_state()

func _tick_all_synchronizers(delta: float) -> void:
  for sync in _registered_synchronizers:
    sync.simulate_tick(net_sim_tick, delta)
  net_sim_tick += 1

func notify_ready() -> void:
  if MultiplayerClient.state.current is MultiplayerClient.Disconnected:
    all_peers_ready.emit()
    return
  send_packet(
    { "type": GlobalGameMessage.ClientGameLoaded },
    MultiplayerPeer.TARGET_PEER_SERVER,
    MultiplayerPeer.TRANSFER_MODE_RELIABLE
  )

func _authority_check_all_peers_ready() -> void:
  if !is_host: return
  if session_state.game_loaded_in: return
  if _lobby == null: return

  for peer in _lobby.peers:
    if not peer.connected: continue
    if not session_state.ready_peers_map.get(peer.peer_id, false): return

  session_state.game_loaded_in = true

func _force_start_timeout() -> void:
  if session_state.game_loaded_in or !is_host: return
  print("SESSION START TIMEOUT - STARTING GAME ANYWAY!")
  session_state.game_loaded_in = true
  state = session_state
  send_refresh_state(MultiplayerPeer.TARGET_PEER_BROADCAST)
  _apply_session_state()

