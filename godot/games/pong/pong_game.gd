@tool
extends Node3D
class_name PongGame

enum PongGameMessage {
  BallMove,
  RoundComplete,
  PaddleMove,
  Initialize,
  StartRound
}

var lobby: Lobby
var pong_paddles_by_peer_id: Dictionary[int, PongPaddle] = {}
var pong_paddles_by_chatter_id: Dictionary[String, PongPaddle] = {}

@onready var pong_paddle_l: PongPaddle = %PongPaddleL
@onready var pong_paddle_r: PongPaddle = %PongPaddleR
@onready var camera: Camera3D = %Camera
@onready var is_game_host: bool = lobby.host_chatter_id == Network.current_chatter.id
@onready var pong_spawn_location: Marker3D = %PongSpawnLocation
@onready var score_region_l: Area3D = %ScoreRegionL
@onready var score_region_r: Area3D = %ScoreRegionR

@export var paddle_start_distance: float = 2.0:
  set(start_distance):
    paddle_start_distance = start_distance
    if Engine.is_editor_hint():
      pong_paddle_l.position.z = -paddle_start_distance
      pong_paddle_r.position.z = paddle_start_distance

func _ready() -> void:
  if Engine.is_editor_hint():
    return

  Network.multiplayer_client.packet_received.connect(_handle_peer_packet)
  Network.chatter_updated.connect(_handle_chatter_updated)

  pong_paddles_by_peer_id[lobby.peers[0].peer_id] = pong_paddle_l
  pong_paddles_by_chatter_id[lobby.peers[0].chatter_id] = pong_paddle_l
  pong_paddle_l.has_authority = lobby.peers[0].chatter_id == Network.current_chatter.id

  pong_paddles_by_peer_id[lobby.peers[1].peer_id] = pong_paddle_r
  pong_paddles_by_chatter_id[lobby.peers[1].chatter_id] = pong_paddle_r
  pong_paddle_r.has_authority = lobby.peers[1].chatter_id == Network.current_chatter.id

  var sub_channels: Array[String] = []
  for peer in lobby.peers:
    sub_channels.append(peer.chatter_id)

  Network.subscribe(sub_channels)

  _handle_chatter_updated(Network.current_chatter)

  print("IS AUTHORITY? ", Network.multiplayer_client.is_authority())

  if Network.multiplayer_client.is_authority():
    Network.multiplayer_client.rtc_peer_ready.connect(_on_player_joined)

    await get_tree().create_timer(1.0).timeout
    score_region_l.body_entered.connect(_area_entered)
    score_region_r.body_entered.connect(_area_entered)
    _start_round()

func _on_player_joined(peer_id: int) -> void:
  print("PEER IS READY => ", peer_id)
    # send_refresh_state(peer_id)  # target that specific peer only

func _area_entered(candidate: Node) -> void:
  if candidate == ball:
    ball.is_finished = true

  Network.multiplayer_client.send_packet({
    "type": PongGame.PongGameMessage.RoundComplete
  })
  await get_tree().create_timer(1.0).timeout
  _start_round()

var ball: PongBall = null
var ball_template: PackedScene = preload("res://games/pong/pong_ball.tscn")
func _start_round() -> void:
  if ball:
    ball.queue_free()
  ball = ball_template.instantiate()
  add_child(ball)
  ball.global_position = pong_spawn_location.global_position

  if Network.multiplayer_client.is_authority():
    Network.multiplayer_client.send_packet(
      { "type": PongGameMessage.StartRound },
      MultiplayerPeer.TARGET_PEER_BROADCAST,
      MultiplayerPeer.TRANSFER_MODE_RELIABLE
    )
    ball.has_authority = true
    ball.start()
  else:
    ball.has_authority = false

func _handle_chatter_updated(chatter: Chatter) -> void:
  var paddle = pong_paddles_by_chatter_id[chatter.id]
  if paddle:
    paddle.chatter = chatter
  
func _physics_process(_delta: float) -> void:
  if Engine.is_editor_hint():
    return
  if !Network.multiplayer_client.is_net_connected(): return

  var my_player_paddle: PongPaddle = pong_paddles_by_peer_id.get(Network.multiplayer_client.rtc_mp.get_unique_id())
  if my_player_paddle == null: return

  if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
      my_player_paddle.add_movement_input(Vector2(0, 1))
  if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
      my_player_paddle.add_movement_input(Vector2(0, -1))

func _handle_peer_packet(sender_id: int, packet: Dictionary) -> void:
  match packet.type:
    PongGameMessage.RoundComplete:
      if ball:
        ball.is_finished = true
    PongGameMessage.BallMove:
      if ball:
        ball.sync_position = packet.get("position", Vector3.ZERO)
        ball.sync_velocity = packet.get("velocity", Vector3.ZERO)
    PongGameMessage.StartRound:
      _start_round()
    PongGameMessage.PaddleMove:
      if pong_paddles_by_peer_id.get(sender_id):
        var paddle_to_move := pong_paddles_by_peer_id[sender_id]
        paddle_to_move.sync_position = packet.get("position", Vector3.ZERO)
        paddle_to_move.sync_velocity = packet.get("velocity", Vector3.ZERO)
