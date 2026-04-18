@tool
extends Node3D
class_name PongGame

enum PongGameMessage {
  BallMove,
  RoundComplete,
  PaddleMove,
  StateRefresh,
  StartRound
}

var lobby: Lobby
var game_state: PongGameState = null
var ball: PongBall = null
var ball_template: PackedScene = preload("res://games/pong/pong_ball.tscn")
var paddle_by_peer_id: Dictionary[int, PongPaddle] = {}

@onready var pong_paddle_l: PongPaddle = %PongPaddleL
@onready var pong_paddle_r: PongPaddle = %PongPaddleR
@onready var camera: Camera3D = %Camera
@onready var is_game_host: bool = lobby.host_chatter_id == Network.my_chatter().id
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

  Network.multiplayer_client.current_lobby_updated.connect(_lobby_updated)
  Network.multiplayer_client.packet_received.connect(_handle_peer_packet)
  Network.authenticated_state.chatter_updated.connect(_handle_chatter_updated)

  var sub_channels: Array[String] = []
  for peer in lobby.peers:
    sub_channels.append(peer.chatter_id)

  Network.subscribe(sub_channels)

  if Network.multiplayer_client.is_authority():
    var new_game_state = PongGameState.new()
    new_game_state.paddle_l_state.owner = 1
    new_game_state.paddle_r_state.owner = lobby.peers[1].peer_id

    new_game_state.paddle_l_state.position = pong_paddle_l.position
    new_game_state.paddle_r_state.position = pong_paddle_r.position

    #
    # Handle new state locally, remotely, and set up automatic
    # state initialization for newly connected peers
    #
    _handle_peer_packet(1, {
      "type": PongGameMessage.StateRefresh,
      "state": new_game_state
    })
    _send_refresh_state(MultiplayerPeer.TARGET_PEER_BROADCAST)
    Network.multiplayer_client.rtc_peer_ready.connect(_send_refresh_state)

    await get_tree().create_timer(1.0).timeout
    score_region_l.body_entered.connect(_area_entered.bind(lobby.peers[1].peer_id))
    score_region_r.body_entered.connect(_area_entered.bind(1))
    _start_round()

  # This must be at the end so the paddle by id is ready  
  _handle_chatter_updated(Network.my_chatter())

func _lobby_updated(new_lobby: Lobby) -> void:
  lobby = new_lobby

func _send_refresh_state(peer_id: int) -> void:
  Network.multiplayer_client.send_packet(
    {
      "type": PongGameMessage.StateRefresh,
      "state": game_state
    },
    peer_id,
    MultiplayerPeer.TRANSFER_MODE_RELIABLE,
  )

func _area_entered(candidate: Node, winning_peer: int) -> void:
  if candidate != ball:
    return

  var message: Dictionary = {
    "type": PongGame.PongGameMessage.RoundComplete,
    "winning_peer": winning_peer
  }
  _handle_peer_packet(1, message)
  Network.multiplayer_client.send_packet(message)

  await get_tree().create_timer(1.0).timeout
  _start_round()

func _start_round() -> void:
  var message := { "type": PongGameMessage.StartRound }
  Network.multiplayer_client.send_packet(
    message,
    MultiplayerPeer.TARGET_PEER_BROADCAST,
    MultiplayerPeer.TRANSFER_MODE_RELIABLE
  )
  _handle_peer_packet(1, message)

func _handle_chatter_updated(chatter: Chatter) -> void:
  var peer_id := lobby.peer_from_chatter[chatter.id]
  var paddle = paddle_by_peer_id.get(peer_id)
  if paddle:
    paddle.chatter = chatter
  
func _physics_process(_delta: float) -> void:
  if Engine.is_editor_hint():
    return
  if !Network.multiplayer_client.is_net_connected(): return

  var my_player_paddle: PongPaddle = paddle_by_peer_id.get(Network.multiplayer_client.rtc_mp.get_unique_id())
  if my_player_paddle == null: return

  if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
      my_player_paddle.add_movement_input(Vector2(0, 1))
  if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
      my_player_paddle.add_movement_input(Vector2(0, -1))

func paddle_state_for_peer(peer_id: int) -> PongEntity:
  return game_state.paddle_l_state\
    if game_state.paddle_l_state.owner == peer_id\
    else game_state.paddle_r_state

func _handle_peer_packet(sender_id: int, packet: Dictionary) -> void:
  if game_state == null and packet.type != PongGameMessage.StateRefresh:
    return

  match packet.type:
    PongGameMessage.StateRefresh:
      game_state = packet.get("state") as PongGameState
      paddle_by_peer_id = {}
      paddle_by_peer_id[game_state.paddle_l_state.owner] = pong_paddle_l
      paddle_by_peer_id[game_state.paddle_r_state.owner] = pong_paddle_r
    PongGameMessage.RoundComplete:
      game_state.ball_state = null
      game_state.round_state = PongGameState.RoundState.RoundComplete
      var paddle_state := paddle_state_for_peer(packet.get("winning_peer"))
      paddle_state.score += 1
    PongGameMessage.BallMove:
      if game_state.ball_state:
        game_state.ball_state.position = packet.get("position", Vector3.ZERO)
        game_state.ball_state.velocity = packet.get("velocity", Vector3.ZERO)
    PongGameMessage.StartRound:
      game_state.ball_state = PongEntity.new()
      game_state.ball_state.owner = 1
      game_state.ball_state.position = pong_spawn_location.global_position
      game_state.round_state = 0
    PongGameMessage.PaddleMove:
      var paddle_state := paddle_state_for_peer(sender_id)
      paddle_state.position = packet.get("position", Vector3.ZERO)
      paddle_state.velocity = packet.get("velocity", Vector3.ZERO)
  _apply_game_state()

func _apply_game_state() -> void:
  if game_state.ball_state == null:
    if ball:
      ball.queue_free()
      ball = null
  else:
    if ball == null:
      ball = ball_template.instantiate()
      ball.sync_state = game_state.ball_state
      add_child(ball)
    ball.sync_state = game_state.ball_state

  pong_paddle_l.sync_state = game_state.paddle_l_state  
  pong_paddle_r.sync_state = game_state.paddle_r_state
