@tool
@abstract
extends Node3D
class_name GameBase

var lobby: Lobby

@warning_ignore("UNUSED_SIGNAL")
signal game_finished
signal chatter_loaded(chatter: Chatter)
signal all_chatters_loaded_locally()
signal peer_is_ready(peer_id: int)
signal all_peers_loaded_in()

enum GlobalGameMessage {
  ClientReady = 1000,
  CamFollow,
  UpdateAnimation,
  AnimationStateRefresh
}

var chatters: Dictionary[String, Chatter] = {}
var ready_peers: Dictionary[int, bool] = {}

var is_game_host: bool = false
var is_offline_mode: bool = true

var peers_ready_fired: bool = false
var chatters_loaded_fired: bool = false

var game_state: BaseGameState = null
var anim_player: AnimationPlayer = null

func _ready() -> void:
  if Engine.is_editor_hint():
    return

  assert(lobby != null, "Lobby should never be null in a GameBase instance")

  is_game_host = MultiplayerClient.is_lobby_host()

  var user_sub_channels: Array[String] = []
  for peer in lobby.peers:
    user_sub_channels.append(peer.chatter_id)
  
  if !is_game_host:
    MultiplayerClient.send_packet(
      { "type": GlobalGameMessage.ClientReady },
      MultiplayerPeer.TARGET_PEER_SERVER,
      MultiplayerPeer.TRANSFER_MODE_RELIABLE
    )

  WSClient.subscribe(user_sub_channels)
  WSClient.authenticated_state.chatter_updated.connect(_handle_chatter_updated)
  MultiplayerClient.packet_received.connect(_base_handle_peer_packet)
  MultiplayerClient.connected_state.lobby_updated.connect(_lobby_was_updated)

  await get_tree().physics_frame
  if MultiplayerClient.state.current is MultiplayerClient.Disconnected:
    all_peers_loaded_in.emit()
    all_chatters_loaded_locally.emit()
  else:
    _check_game_ready()
    # peers_ready_fired = true
    # all_peers_loaded_in.emit()

func _lobby_was_updated() -> void:
  lobby = MultiplayerClient.current_lobby
  if lobby == null:
    game_finished.emit()
    return
  _subscribe_to_chatters_in_lobby()
  handle_lobby_updated()
  _check_game_ready()

func handle_lobby_updated() -> void:
  assert(false, "handle_lobby_updated should be overridden by game implementation")

func _subscribe_to_chatters_in_lobby() -> void:
  if lobby == null: return
  var user_sub_channels: Array[String] = []
  for peer in lobby.peers:
    user_sub_channels.append(peer.chatter_id)
  WSClient.subscribe(user_sub_channels)

func _check_game_ready() -> void:
  if lobby == null: return
  if peers_ready_fired:
    return
  for peer in lobby.peers:
    # print(peer.peer_id, " lobby peers are")
    if peer.peer_id == MultiplayerClient.my_peer_id(): continue
    if !peer.connected: continue
    if not ready_peers.has(peer.peer_id):
      return
  peers_ready_fired = true
  all_peers_loaded_in.emit()

func _handle_chatter_updated(chatter: Chatter) -> void:
  chatters[chatter.id] = chatter
  chatter_loaded.emit(chatter)

  for peer in lobby.peers:
    if not chatters.has(peer.chatter_id):
      return

  if chatters_loaded_fired: return

  chatters_loaded_fired = true
  all_chatters_loaded_locally.emit()

func _base_handle_peer_packet(sender_id: int, packet: Dictionary) -> void:
  match packet.type:
    GlobalGameMessage.ClientReady:
      print("game_host=", MultiplayerClient.is_lobby_host(), " received ready from ", sender_id)
      ready_peers[sender_id] = true
      peer_is_ready.emit(sender_id)
      if is_game_host:
        _check_game_ready()
