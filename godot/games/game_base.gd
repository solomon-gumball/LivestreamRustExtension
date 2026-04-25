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
  CamFollow
}

var chatters: Dictionary[String, Chatter] = {}
var ready_peers: Dictionary[int, bool] = {}
var is_game_host: bool = false

func _ready() -> void:
  is_game_host = lobby.host_chatter_id == WSClient.my_chatter().id

  var user_sub_channels: Array[String] = []
  for peer in lobby.peers:
    user_sub_channels.append(peer.chatter_id)

  if !is_game_host:
    MultiplayerClient.send_packet(
      { "type": GlobalGameMessage.ClientReady },
      MultiplayerPeer.TARGET_PEER_SERVER,
      MultiplayerPeer.TRANSFER_MODE_RELIABLE,
      true
    )


  WSClient.subscribe(user_sub_channels)
  WSClient.authenticated_state.chatter_updated.connect(_handle_chatter_updated)
  MultiplayerClient.packet_received.connect(_base_handle_peer_packet)

  _check_game_ready()

func _check_game_ready() -> void:
  for peer in lobby.peers:
    if peer.peer_id == MultiplayerClient.my_peer_id(): continue
    if not ready_peers.has(peer.peer_id):
      return
  all_peers_loaded_in.emit()

func _handle_chatter_updated(chatter: Chatter) -> void:
  chatters[chatter.id] = chatter
  chatter_loaded.emit(chatter)

  for peer in lobby.peers:
    if not chatters.has(peer.chatter_id):
      return
  all_chatters_loaded_locally.emit()

func _base_handle_peer_packet(sender_id: int, packet: Dictionary) -> void:
  match packet.type:
    GlobalGameMessage.ClientReady:
      ready_peers[sender_id] = true
      peer_is_ready.emit(sender_id)
      if is_game_host:
        _check_game_ready()
