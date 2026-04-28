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
  UpdateAnimation
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

  if is_offline_mode:
    is_game_host = true
    var mock_game_data := GameMetadata.new()
    var mock_data := MockData.generate_mock_game_lobby(5, 3, 5, 5, mock_game_data)
    lobby = mock_data.get("lobby")
    MultiplayerClient.packet_received.connect(_base_handle_peer_packet)

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
    GlobalGameMessage.UpdateAnimation:
      game_state.animation_state = AnimationState.new()
      game_state.animation_state.started_at = packet.get("started_at", 0)
      game_state.animation_state.animation_name = packet.get("animation_name", "")
      game_state.animation_state.skipped = packet.get("skipped", false)

  if game_state.animation_state:
    if !game_state.animation_state.equals(local_anim_state):
      _sync_animation_state()

signal animation_finished

var local_anim_state: AnimationState
func _sync_animation_state() -> void:
  local_anim_state = game_state.animation_state
  var animation_to_play := anim_player.get_animation(local_anim_state.animation_name)

  if animation_to_play == null:
    assert(false, "Attempted to play nonexistent animation %s" % local_anim_state.animation_name)

  var anim_elapsed_time: float = animation_to_play.length\
    if local_anim_state.skipped\
    else Time.get_unix_time_from_system() - game_state.animation_state.started_at
  print("SYNCING ANIMATION STATE ", local_anim_state.animation_name, " ", anim_elapsed_time)

  anim_player.play(local_anim_state.animation_name)
  anim_player.seek(anim_elapsed_time, true)
  if anim_elapsed_time >= animation_to_play.length:
    animation_finished.emit(local_anim_state.animation_name)

@abstract
func handle_anim_finished(finished_anim_name) -> void

func authority_skip_current_animation() -> void:
  if !is_game_host:
    assert(false, "ERROR: Non-host player called authority_skip_current_animation()!")  

  if local_anim_state and !local_anim_state.skipped:
    MultiplayerClient.send_packet(
      {
        "type": GlobalGameMessage.UpdateAnimation,
        "animation_name": local_anim_state.animation_name,
        "started_at": local_anim_state.started_at,
        "skipped": true
      },
      MultiplayerPeer.TARGET_PEER_BROADCAST,
      MultiplayerPeer.TRANSFER_MODE_RELIABLE,
      true
    )

func authority_play_animation(animation_name: String) -> void:
  if !is_game_host:
    assert(false, "ERROR: Non-host player called authority_play_animation()!")

  MultiplayerClient.send_packet(
    {
      "type": GlobalGameMessage.UpdateAnimation,
      "animation_name": animation_name,
      "started_at": Time.get_unix_time_from_system(),
      "skipped": false
    },
    MultiplayerPeer.TARGET_PEER_BROADCAST,
    MultiplayerPeer.TRANSFER_MODE_RELIABLE,
    true
  )

func _unhandled_input(_event: InputEvent) -> void:
  if MultiplayerClient.is_authority():
    if Input.is_key_pressed(KEY_ENTER):
      authority_skip_current_animation()
