@tool
extends GameBase
class_name PongGame

enum PongGameMessage {
  BallMove,
  RoundComplete,
  PaddleMove,
  StateRefresh,
  ClientReady,
  StartRound,
}

var pong_state: PongGameState = null:
  set(new_state):
    pong_state = new_state
    game_state = new_state

var ball: PongBall = null
var ball_template: PackedScene = preload("res://games/pong/pong_ball.tscn")
var nodes_by_peer_id: Dictionary[int, Dictionary] = {}

@onready var pong_paddle_l: PongPaddle = %PongPaddleL
@onready var pong_paddle_r: PongPaddle = %PongPaddleR
@onready var camera: Camera3D = %Camera
@onready var pong_spawn_location: Marker3D = %PongSpawnLocation
@onready var score_region_l: Area3D = %ScoreRegionL
@onready var score_region_r: Area3D = %ScoreRegionR
@onready var paddle_l_score: Label3D = %PaddleLScore
@onready var paddle_r_score: Label3D = %PaddleRScore
@onready var cam_boom: Node3D = %CamBoom
@onready var anim_sync: AnimationSynchronizer = %AnimationSynchronizer

var saved_pong_l_position: Vector3 = Vector3.ZERO
var saved_pong_r_position: Vector3 = Vector3.ZERO
func save_paddle_positions() -> void:
  saved_pong_l_position = pong_paddle_l.position
  saved_pong_r_position = pong_paddle_r.position

@export_range(0.0, 1.0) var players_distance_from_center: float = 0.0:
  set(new_value):
    players_distance_from_center = new_value
    if not is_node_ready():
      return
    if game_state:
      pong_paddle_l.position = lerp(game_state.paddle_l_state.position, Vector3(0, 0, -0.3), 1.0 - new_value)
      pong_paddle_r.position = lerp(game_state.paddle_r_state.position, Vector3(0, 0, 0.3), 1.0 - new_value)
    elif Engine.is_editor_hint():
      pong_paddle_l.position = lerp(Vector3(0, 0, -paddle_start_distance), Vector3(0, 0, -0.3), 1.0 - new_value)
      pong_paddle_r.position = lerp(Vector3(0, 0, paddle_start_distance), Vector3(0, 0, 0.3), 1.0 - new_value)

@export var paddle_start_distance: float = 3.2:
  set(start_distance):
    paddle_start_distance = start_distance
    if Engine.is_editor_hint():
      pong_paddle_l.position.z = -paddle_start_distance
      pong_paddle_r.position.z = paddle_start_distance

@export var dotted_line_mat: StandardMaterial3D
@export var dotted_line_alpha := 1.0:
  set(new_value):
    dotted_line_alpha = new_value
    dotted_line_mat.albedo_color.a = new_value

func _ready() -> void:
  if Engine.is_editor_hint():
    return

  anim_player = %AnimationPlayer
  anim_sync.animation_player = anim_player

  dotted_line_alpha = dotted_line_alpha
  is_game_host = lobby.host_chatter_id == WSClient.my_chatter().id

  visible = false
  MultiplayerClient.connected_state.left_lobby.connect(_left_lobby)
  MultiplayerClient.packet_received.connect(_handle_peer_packet)
  WSClient.authenticated_state.chatter_updated.connect(_handle_chatter_updated)

  var sub_channels: Array[String] = []
  for peer in lobby.peers:
    sub_channels.append(peer.chatter_id)

  WSClient.subscribe(sub_channels)

  nodes_by_peer_id[lobby.players[0].peer_id] = {
    "paddle": pong_paddle_l,
    "score": paddle_l_score
  }
  nodes_by_peer_id[lobby.players[1].peer_id] = {
    "paddle": pong_paddle_r,
    "score": paddle_r_score
  }

  if MultiplayerClient.is_authority():
    var new_game_state = PongGameState.new()
    new_game_state.phase_started_at = Time.get_unix_time_from_system()
    new_game_state.paddle_l_state.owner = lobby.players[0].peer_id
    new_game_state.paddle_r_state.owner = lobby.players[1].peer_id

    new_game_state.paddle_l_state.position = Vector3(0, 0, -paddle_start_distance)
    new_game_state.paddle_r_state.position = Vector3(0, 0, paddle_start_distance)

    score_region_l.body_entered.connect(_score_area_hit.bind(lobby.players[1].peer_id))
    score_region_r.body_entered.connect(_score_area_hit.bind(lobby.players[0].peer_id))

    anim_sync.animation_finished.connect(_anim_finished)

    _handle_peer_packet(1, {
      "type": PongGameMessage.StateRefresh,
      "state": new_game_state
    })
    anim_sync.authority_play_animation("intro")
    _send_refresh_state(MultiplayerPeer.TARGET_PEER_BROADCAST)
    MultiplayerClient.rtc_peer_ready.connect(_send_refresh_state)
  else:
    MultiplayerClient.send_packet(
      {
        "type": PongGameMessage.ClientReady,
      },
      MultiplayerPeer.TARGET_PEER_SERVER,
      MultiplayerPeer.TRANSFER_MODE_RELIABLE
    )

  # This must be at the end so the paddle by id is ready
  _handle_chatter_updated(WSClient.my_chatter())

func _exit_tree() -> void:
  if Engine.is_editor_hint():
    return
  if MultiplayerClient.connected_state:
    MultiplayerClient.connected_state.left_lobby.disconnect(_left_lobby)
  MultiplayerClient.packet_received.disconnect(_handle_peer_packet)
  WSClient.authenticated_state.chatter_updated.disconnect(_handle_chatter_updated)
  if MultiplayerClient.is_authority():
    MultiplayerClient.rtc_peer_ready.disconnect(_send_refresh_state)

func trigger_ending_character_anims() -> void:
  if game_state.paddle_l_state.score > game_state.paddle_r_state.score:
    pong_paddle_l.gumbot_animation_state = PongPaddle.GumbotAnimState.Taunt
  else:
    pong_paddle_r.gumbot_animation_state = PongPaddle.GumbotAnimState.Taunt

# Authority only function
func _anim_finished(anim_name: String) -> void:
  if anim_name == "intro":
    _start_round()
  if anim_name == "outro":
    game_finished.emit()

func _left_lobby() -> void:
  game_finished.emit()

func _send_refresh_state(peer_id: int) -> void:
  MultiplayerClient.send_packet(
    {
      "type": PongGameMessage.StateRefresh,
      "state": game_state
    },
    peer_id,
    MultiplayerPeer.TRANSFER_MODE_RELIABLE,
  )

const NUM_ROUNDS = 3
func _score_area_hit(candidate: Node, winning_peer: int) -> void:
  if candidate != ball:
    return

  var message: Dictionary = {
    "type": PongGame.PongGameMessage.RoundComplete,
    "winning_peer": winning_peer
  }
  _handle_peer_packet(1, message)
  MultiplayerClient.send_packet(message)

  if game_state.paddle_l_state.score >= NUM_ROUNDS or\
    game_state.paddle_r_state.score >= NUM_ROUNDS:
      anim_sync.authority_play_animation("outro")
  else:
    await get_tree().create_timer(1.0).timeout
    _start_round()

func _start_round() -> void:
  MultiplayerClient.send_packet(
    { "type": PongGameMessage.StartRound, "started_at": Time.get_unix_time_from_system() },
    MultiplayerPeer.TARGET_PEER_BROADCAST,
    MultiplayerPeer.TRANSFER_MODE_RELIABLE,
    true
  )

func _handle_chatter_updated(chatter: Chatter) -> void:
  var peer_id := lobby.peer_from_chatter[chatter.id]
  var paddle = nodes_by_peer_id.get(peer_id, {}).get("paddle")
  if paddle:
    paddle.chatter = chatter

func _physics_process(_delta: float) -> void:
  if Engine.is_editor_hint(): return
  if !MultiplayerClient.is_net_connected(): return
  if anim_player.is_playing(): return

  var my_player_paddle: PongPaddle = nodes_by_peer_id.get(MultiplayerClient.rtc_mp.get_unique_id(), {}).get("paddle")
  if my_player_paddle == null: return

  if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
      my_player_paddle.add_movement_input(Vector2(0, 1))
  if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
      my_player_paddle.add_movement_input(Vector2(0, -1))

func paddle_state_for_peer(peer_id: int) -> PongEntity:
  # print("lookup peer=%d l_owner=%d r_owner=%d" % [peer_id, game_state.paddle_l_state.owner, game_state.paddle_r_state.owner])
  return game_state.paddle_l_state\
    if game_state.paddle_l_state.owner == peer_id\
    else game_state.paddle_r_state

func _handle_peer_packet(sender_id: int, packet: Dictionary) -> void:
  # print("Received packet type=%s from=%d on peer=%d" % [packet.type, sender_id, MultiplayerClient.my_peer_id()])
  if game_state == null and packet.type != PongGameMessage.StateRefresh:
    return

  match packet.type:
    PongGameMessage.ClientReady:
      _send_refresh_state(sender_id)
    PongGameMessage.StateRefresh:
      pong_state = packet.get("state") as PongGameState
    PongGameMessage.RoundComplete:
      pong_state.ball_state = null
      pong_state.phase = PongGameState.Phase.RoundComplete
      var paddle_state := paddle_state_for_peer(packet.get("winning_peer"))
      paddle_state.score += 1
    PongGameMessage.BallMove:
      if pong_state.ball_state:
        pong_state.ball_state.sent_at = packet.get("sent_at", 0)
        pong_state.ball_state.position = packet.get("position", Vector3.ZERO)
        pong_state.ball_state.velocity = packet.get("velocity", Vector3.ZERO)
    PongGameMessage.StartRound:
      pong_state.ball_state = PongEntity.new()
      pong_state.ball_state.owner = 1
      pong_state.ball_state.position = pong_spawn_location.global_position
      pong_state.phase = PongGameState.Phase.Playing
      pong_state.phase_started_at = packet.get("started_at", 0)
    PongGameMessage.PaddleMove:
      var paddle_state := paddle_state_for_peer(sender_id)
      paddle_state.position = packet.get("position", Vector3.ZERO)
      paddle_state.velocity = packet.get("velocity", Vector3.ZERO)
  _apply_game_state()

func _apply_game_state() -> void:
  if game_state:
    visible = true

  if paddle_l_score.text != str(game_state.paddle_l_state.score):
    paddle_l_score.text = str(game_state.paddle_l_state.score)
  if paddle_r_score.text != str(game_state.paddle_r_state.score):
    paddle_r_score.text = str(game_state.paddle_r_state.score)

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

  pong_paddle_l.round_started_at = pong_state.phase_started_at
  pong_paddle_r.round_started_at = pong_state.phase_started_at

  pong_paddle_l.sync_state = game_state.paddle_l_state
  pong_paddle_r.sync_state = game_state.paddle_r_state
