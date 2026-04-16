extends Node3D
class_name PongGame

enum PongGameMessage {
  BallPosition,
  PaddlePosition,
  Initialize,
}

var lobby: Lobby
var chatters: Dictionary[String, Chatter] = {}

@onready var pong_paddle_l: PongPaddle = %PongPaddleL
@onready var pong_paddle_r: PongPaddle = %PongPaddleR
@onready var camera: Camera3D = %Camera3D
@onready var is_game_host: bool = lobby.host_chatter_id == Network.current_chatter.id

func _ready() -> void:
  Network.multiplayer_client.packet_received.connect(_handle_peer_packet)
  Network.multiplayer_client.send_packet({ "type": PongGameMessage.BallPosition })

  pong_paddle_l.peer_id = lobby.peers[0].peer_id
  pong_paddle_l.chatter_id = lobby.peers[0].chatter_id

  pong_paddle_r.peer_id = lobby.peers[1].peer_id
  pong_paddle_r.chatter_id = lobby.peers[1].chatter_id

  Network.chatter_updated.connect(_handle_chatter_updated)
  var sub_channels: Array[String] = []
  for peer in lobby.peers:
    sub_channels.append(peer.chatter_id)
  Network.subscribe(sub_channels)

  # if is_game_host:
    # _setup_paddles({
    #   "l_chatter": Network.current_chatter.id,
    #   "r_chatter": lobby.peers[1],
    #   "l_peer": Network.multiplayer_client.rtc_mp.get_unique_id()
    # })
  
  _handle_chatter_updated(Network.current_chatter)

func _handle_chatter_updated(chatter: Chatter) -> void:
  chatters[chatter.id] = chatter

  if chatters.has(pong_paddle_l.chatter_id):
    pong_paddle_l.chatter = chatters[pong_paddle_l.chatter_id]
  if chatters.has(pong_paddle_r.chatter_id):
    pong_paddle_r.chatter = chatters[pong_paddle_r.chatter_id]

func _handle_peer_packet(id: int, packet: Dictionary) -> void:
  print("PONG GAME GOT PACKET: ", packet, " from ", id)
