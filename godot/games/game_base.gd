@tool
extends Node3D
class_name GameBase

var lobby: Lobby

@warning_ignore("UNUSED_SIGNAL")
signal game_finished

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

func game_ready() -> void:
  print("Game is ready to start!")
  pass

func chatters_loaded() -> void:
  print("All chatters loaded!")
  pass

func _check_game_ready() -> void:
  for peer in lobby.peers:
    if not ready_peers.has(peer.peer_id):
      return
  game_ready()

func _handle_chatter_updated(chatter: Chatter) -> void:
  chatters[chatter.id] = chatter
  for peer in lobby.peers:
    if not chatters.has(peer.chatter_id):
      return
  _check_game_ready()

func _base_handle_peer_packet(sender_id: int, packet: Dictionary) -> void:
  match packet.type:
    GlobalGameMessage.ClientReady:
      ready_peers[sender_id] = true
      if is_game_host:
        _check_game_ready()