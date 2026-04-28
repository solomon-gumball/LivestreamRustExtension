@tool
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
  UpdateAnimation
}

var chatters: Dictionary[String, Chatter] = {}
var ready_peers: Dictionary[int, bool] = {}

var is_game_host: bool = false
var is_offline_mode: bool = true

var peers_ready_fired: bool = false
var chatters_loaded_fired: bool = false

var game_state: BaseGameState = null

func _ready() -> void:
  if Engine.is_editor_hint():
    return

  if is_offline_mode:
    is_game_host = true
    var mock_game_data := GameMetadata.new()
    var mock_data := MockData.generate_mock_game_lobby(5, 3, 5, 5, mock_game_data)
    lobby = mock_data.get("lobby")
    print(lobby.peers)
    await get_tree().physics_frame

    for chatter in mock_data.get("chatters"):
      chatter_loaded.emit(chatter)
    all_chatters_loaded_locally.emit()
    all_peers_loaded_in.emit()
    return

  assert(lobby != null, "Lobby should never be null in a GameBase instance")

  is_game_host = lobby.host_chatter_id == WSClient.my_chatter().id

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
  _check_game_ready()

func _lobby_was_updated() -> void:
  lobby = MultiplayerClient.current_lobby
  _subscribe_to_chatters_in_lobby()
  handle_lobby_updated()

func handle_lobby_updated() -> void:
  assert(false, "handle_lobby_updated should be overridden by game implementation")

func _subscribe_to_chatters_in_lobby() -> void:
  var user_sub_channels: Array[String] = []
  for peer in lobby.peers:
    user_sub_channels.append(peer.chatter_id)
  WSClient.subscribe(user_sub_channels)

func _check_game_ready() -> void:
  if peers_ready_fired:
    return
  for peer in lobby.peers:
    if peer.peer_id == MultiplayerClient.my_peer_id(): continue
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
      ready_peers[sender_id] = true
      peer_is_ready.emit(sender_id)
      if is_game_host:
        _check_game_ready()

func handle_peer_packet(sender_id: int, packet: Dictionary) -> void:
  
  # assert(false, "handle_peer_packet should be overridden by game implementation")

func start_animation(animation_name: String) -> void:
  MultiplayerClient.send_packet({
    "type": GlobalGameMessage.UpdateAnimation,
    "animation_name": "intro",
    "started_at": Time.get_unix_time_from_system(),
    "skipped": false
  }, true)