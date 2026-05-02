@tool
@abstract
extends Node3D
class_name GameBase

var lobby: Lobby

@warning_ignore("UNUSED_SIGNAL")
signal game_finished
signal chatter_loaded(chatter: Chatter)
signal all_chatters_loaded_locally()

var chatters: Dictionary[String, Chatter] = {}

var is_game_host: bool = false
var is_offline_mode: bool = true

var chatters_loaded_fired: bool = false

var game_state: BaseGameState = null
var anim_player: AnimationPlayer = null

func _ready() -> void:
  if Engine.is_editor_hint():
    return

  assert(lobby != null, "Lobby should never be null in a GameBase instance")

  is_game_host = MultiplayerClient.is_lobby_host()

  var user_sub_channels: Array[String] = []
  for peer in lobby.peers:
    user_sub_channels.append(peer.chatter_id)

  WSClient.subscribe(user_sub_channels)
  WSClient.authenticated_state.chatter_updated.connect(_handle_chatter_updated)
  MultiplayerClient.connected_state.lobby_updated.connect(_lobby_was_updated)

  if MultiplayerClient.state.current is MultiplayerClient.Disconnected:
    all_chatters_loaded_locally.emit()

func start_game() -> void:
  pass

func _lobby_was_updated() -> void:
  lobby = MultiplayerClient.current_lobby
  if lobby == null:
    game_finished.emit()
    return
  _subscribe_to_chatters_in_lobby()
  handle_lobby_updated()

func handle_lobby_updated() -> void:
  assert(false, "handle_lobby_updated should be overridden by game implementation")

func _subscribe_to_chatters_in_lobby() -> void:
  if lobby == null: return
  var user_sub_channels: Array[String] = []
  for peer in lobby.peers:
    user_sub_channels.append(peer.chatter_id)
  WSClient.subscribe(user_sub_channels)

func _handle_chatter_updated(chatter: Chatter) -> void:
  chatters[chatter.id] = chatter
  chatter_loaded.emit(chatter)

  for peer in lobby.peers:
    if not chatters.has(peer.chatter_id):
      return

  if chatters_loaded_fired: return

  chatters_loaded_fired = true
  all_chatters_loaded_locally.emit()
