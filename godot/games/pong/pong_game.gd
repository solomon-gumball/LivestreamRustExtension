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
const NUM_ROUNDS = 5

var pong_state: PongGameState = null:
  set(new_state):
    pong_state = new_state
    game_state = new_state

var ball: PongBall = null
var ball_template: PackedScene = preload("res://games/pong/pong_ball.tscn")
var nodes_by_peer_id: Dictionary[int, Dictionary] = {}

@onready var pong_paddle_l: PongPaddle = %PongPaddleL
@onready var pong_paddle_r: PongPaddle = %PongPaddleR
@onready var camera: ShakeableCamera = %Camera
@onready var pong_spawn_location: Marker3D = %PongSpawnLocation
@onready var score_region_l: Area3D = %ScoreRegionL
@onready var score_region_r: Area3D = %ScoreRegionR
@onready var paddle_l_score: Label3D = %PaddleLScore
@onready var paddle_r_score: Label3D = %PaddleRScore
@onready var cam_boom: Node3D = %CamBoom
@onready var anim_sync: AnimationSynchronizer = %AnimationSynchronizer
@onready var success_audio_player: AudioStreamPlayer = %SuccessAudioPlayer
@onready var winner_text_block: RichTextLabel = %WinnerText

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
    paddle_l_score.modulate.a = new_value
    paddle_r_score.modulate.a = new_value

func _ready() -> void:
  super._ready()

  if Engine.is_editor_hint():
    return

  anim_player = %AnimationPlayer
  anim_sync.animation_player = anim_player

  dotted_line_alpha = dotted_line_alpha
  is_game_host = lobby.host_chatter_id == WSClient.my_chatter().id

  visible = false
  MultiplayerClient.connected_state.left_lobby.connect(_left_lobby)
  MultiplayerClient.packet_received.connect(_handle_peer_packet)
  chatter_loaded.connect(_handle_chatter_loaded)

  var sub_channels: Array[String] = []
  for peer in lobby.peers:
    sub_channels.append(peer.chatter_id)

  nodes_by_peer_id[lobby.players[0].peer_id] = {
    "paddle": pong_paddle_l,
    "score": paddle_l_score
  }
  nodes_by_peer_id[lobby.players[1].peer_id] = {
    "paddle": pong_paddle_r,
    "score": paddle_r_score
  }

  # This must be at the end so the paddle by id is ready
  _handle_chatter_loaded(WSClient.my_chatter())

func start_game() -> void:
  if not MultiplayerClient.is_lobby_host():
    return
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
  SessionSynchronizer.get_instance().peer_is_ready.connect(_send_refresh_state)

func _exit_tree() -> void:
  if Engine.is_editor_hint():
    return
  if MultiplayerClient.connected_state:
    MultiplayerClient.connected_state.left_lobby.disconnect(_left_lobby)
  MultiplayerClient.packet_received.disconnect(_handle_peer_packet)

func trigger_ending_character_anims() -> void:
  if lobby == null: return
  var winning_peer: Lobby.PeerData = null
  if game_state.paddle_l_state.score > game_state.paddle_r_state.score:
    winning_peer = lobby.players.get(0)
    pong_paddle_l.gumbot_animation_state = PongPaddle.GumbotAnimState.Taunt
  else:
    winning_peer = lobby.players.get(1)
    pong_paddle_r.gumbot_animation_state = PongPaddle.GumbotAnimState.Taunt
  
  if winning_peer:
    var winning_chatter: Chatter = chatters.get(winning_peer.chatter_id, null)
    if winning_chatter:
      winner_text_block.text = "[wave][color=pink]%s[/color][/wave]\n[wave][color=green]wins![/color]" % winning_chatter.display_name

# Authority only function
func _anim_finished(anim_name: String) -> void:
  if anim_name == "intro":
    _start_round()
  if anim_name == "outro":
    game_finished.emit()

func _left_lobby() -> void:
  return
  # game_finished.emit()

func _send_refresh_state(peer_id: int) -> void:
  MultiplayerClient.send_packet(
    {
      "type": PongGameMessage.StateRefresh,
      "state": game_state
    },
    peer_id,
    MultiplayerPeer.TRANSFER_MODE_RELIABLE,
  )

func handle_lobby_updated() -> void:
  pass

func spawn_score_fx(spawn_position: Vector3, spawn_normal: Vector3) -> void:
  var success_fx: GPUParticles3D = pong_score_template.instantiate()
  add_child(success_fx)
  success_fx.global_position = spawn_position
  success_fx.emitting = true
  success_fx.look_at(success_fx.global_position + spawn_normal, Vector3.UP, true)

  await success_fx.finished
  success_fx.queue_free()

var pong_score_template: PackedScene = preload("res://games/pong/pong_score_fx.tscn")
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
    await get_tree().create_timer(2.0).timeout
    # camera.max_x = 3.0
    # camera.max_z = 3.0
    # camera.trauma_reduction_rate = 1.0
    _start_round()

func _start_round() -> void:
  var direction := Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, randf_range(0, TAU))
  MultiplayerClient.send_packet(
    {
      "type": PongGameMessage.StartRound,
      "started_at": Time.get_unix_time_from_system(),
      "direction": direction,
    },
    MultiplayerPeer.TARGET_PEER_BROADCAST,
    MultiplayerPeer.TRANSFER_MODE_RELIABLE,
    MultiplayerClient.PacketSelfMode.SelfIncluded
  )

func _handle_chatter_loaded(chatter: Chatter) -> void:
  if lobby.peer_from_chatter.has(chatter.id):
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

func paddle_state_for_peer(peer_id: int) -> PongGameState.PongEntity:
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
      var winning_peer = packet.get("winning_peer")
      var paddle_state := paddle_state_for_peer(winning_peer)
      paddle_state.score += 1

      success_audio_player.play()
      camera.max_x = 6.0
      camera.max_z = 6.0
      camera.trauma_reduction_rate = 0.6
      camera.add_trauma(1.0)

      var is_left_player: bool = lobby.players[0].peer_id == winning_peer

      if ball:
        spawn_score_fx(ball.global_position, Vector3(0, 0, -1 if is_left_player else 1))
    PongGameMessage.BallMove:
      pong_state.ball_state = PongGameState.PongEntity.new()
      pong_state.ball_state.position = packet.get("position", Vector3.ZERO)
      pong_state.ball_state.velocity = packet.get("velocity", Vector3.ZERO)
      pong_state.ball_state.sent_at = packet.get("sent_at", 0.0)
      if MultiplayerClient.my_peer_id() != sender_id:
        var date_string := Time.get_datetime_string_from_unix_time(pong_state.ball_state.sent_at)
        print("(%s) RECIEVED BALL MOVE FROM PEER=%d pos=%s vel=%s" % [date_string, sender_id, pong_state.ball_state.position, pong_state.ball_state.velocity])

    PongGameMessage.StartRound:
      camera.max_x = 6.0
      camera.max_z = 6.0
      camera.trauma_reduction_rate = 0.6

      var direction: Vector3 = packet.get("direction", Vector3(1, 0, 0))
      pong_state.ball_state = PongGameState.PongEntity.new()
      pong_state.ball_state.owner = 1
      pong_state.ball_state.position = pong_spawn_location.global_position
      pong_state.ball_state.velocity = direction.normalized() * PongBall.BASE_SPEED
      pong_state.ball_state.sent_at = packet.get("started_at", 0.0)
      pong_state.phase = PongGameState.Phase.Playing
      pong_state.phase_started_at = packet.get("started_at", 0.0)
    PongGameMessage.PaddleMove:
      var paddle_state := paddle_state_for_peer(sender_id)
      paddle_state.position = packet.get("position", Vector3.ZERO)
      paddle_state.velocity = packet.get("velocity", Vector3.ZERO)
  _apply_game_state()

func _ball_bounced(did_hit_paddle: bool) -> void:
  camera.add_trauma(0.6 if did_hit_paddle else 0.2)

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
      ball.paddle_l = pong_paddle_l
      ball.paddle_r = pong_paddle_r
      ball.bounced.connect(_ball_bounced)
      add_child(ball)
    ball.sync_state = game_state.ball_state

  pong_paddle_l.round_started_at = pong_state.phase_started_at
  pong_paddle_r.round_started_at = pong_state.phase_started_at

  pong_paddle_l.sync_state = game_state.paddle_l_state
  pong_paddle_r.sync_state = game_state.paddle_r_state
