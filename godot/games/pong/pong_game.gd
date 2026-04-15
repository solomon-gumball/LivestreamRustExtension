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
@onready var is_game_host: bool = lobby.host_chatter_id == Network.current_chatter.id

func _ready() -> void:
  Network.multiplayer_client.packet_received.connect(_handle_peer_packet)
  Network.multiplayer_client.send_packet({ "type": PongGameMessage.BallPosition })

  Network.chatter_updated.connect(_handle_chatter_updated)
  Network.subscribe(lobby.peers)

#   if is_game_host:
#     _setup_paddles({
#       "l_chatter": Network.current_chatter.id,
#       "r_chatter": lobby.peers[1],
#       "l_peer": Network.multiplayer_client.rtc_mp.get_unique_id()
#     })
#     pong_paddle_l.peer_id = Network.multiplayer_client.rtc_mp.get_unique_id()
#     pong_paddle_l.chatter_id = Network.current_chatter.id

# func _setup_paddles(paddle_ids: Dictionary) -> void:
#   for peer_id in lobby.peers:
#     var chatter_id = lobby.peers[peer_id]
#     var chatter = Network.get_chatter(chatter_id)
#     chatters[chatter_id] = chatter

#     if peer_id == Network.multiplayer_client.rtc_mp.get_unique_id():
#       pong_paddle_l.peer_id = peer_id
#       pong_paddle_l.chatter_id = chatter_id
#     else:
#       pong_paddle_r.peer_id = peer_id
#       pong_paddle_r.chatter_id = chatter_id

func _handle_chatter_updated(chatter: Chatter) -> void:
  if chatter.id == Network.current_chatter.id:
    chatters[chatter.id] = chatter

func _handle_peer_packet(id: int, packet: Dictionary) -> void:
  print("PONG GAME GOT PACKET: ", packet, " from ", id)
