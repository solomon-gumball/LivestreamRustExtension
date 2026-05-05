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
  ClientReady = 1000,
  CamFollow,
  UpdateAnimation,
  AnimationStateRefresh,
  SessionStateRefresh
}

signal all_peers_ready()
signal peer_is_ready(peer_id: int)

var state: Dictionary[int, bool] = {}
var _lobby: Lobby = null
var _all_peers_ready_fired: bool = false

func _ready() -> void:
  MultiplayerClient.packet_received.connect(_handle_peer_packet)
  # MultiplayerClient.rtc_peer_ready.connect(_new_peer_ready)

func _exit_tree() -> void:
  if _instance == self:
    _instance = null
  MultiplayerClient.packet_received.disconnect(_handle_peer_packet)
  # MultiplayerClient.rtc_peer_ready.disconnect(_new_peer_ready)

func setup(lobby: Lobby) -> void:
  _lobby = lobby

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

func _check_all_peers_ready() -> void:
  if _all_peers_ready_fired: return
  if _lobby == null: return
  for peer in _lobby.peers:
    if not peer.connected: continue
    if not state.get(peer.peer_id, false): return
  _all_peers_ready_fired = true
  all_peers_ready.emit()
