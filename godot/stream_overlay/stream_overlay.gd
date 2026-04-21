extends Node3D
class_name OverlayScene

@onready var camera: Camera3D = %Camera
@onready var bot_spawn_location: Node3D = %BotSpawnLocation
@onready var game_root_node: Node3D = %GameRootNode
@onready var bot_walking_scene: Node3D = %BotWalkingScene

var spawned_bots = {}

func _ready():
  WSClient.authenticated_state.chat_message_received.connect(chat_message_received)
  WSClient.authenticated_state.store_data_received.connect(store_data_received)
  WSClient.authenticated_state.chatter_updated.connect(chatter_updated)
  WSClient.authenticated_state.emote_triggered.connect(emote_triggered)
  MultiplayerClient.current_lobby_updated.connect(_handle_lobby_updated)

  store_data_received()
  MultiplayerClient.start()
  # WSClient.state.changed.connect(_handle_ws_state_changed)

# func _handle_ws_state_changed(connection_state: WSClient.WSClientState) -> void:
#   if connection_state is WSClient.AuthenticatedState:
#     MultiplayerClient.start()

func emote_triggered(chatter: Chatter, emote: String):
  var bot := get_or_create_bot_for_user(chatter)
  bot.emote = emote

func chatter_updated(updated: Chatter):
  var bot := get_or_create_bot_for_user(updated)
  bot.chatter = updated

func store_data_received():
  for chatter in WSClient.authenticated_state.active_chatters:
    get_or_create_bot_for_user(chatter)

const gumbot_template: PackedScene = preload("res://stream_overlay/stream_overlay_gumbot.tscn")
const DEFAULT_BOT_SCALE = Vector3(0.6, 0.6, 0.6)
func get_or_create_bot_for_user(chatter: Chatter) -> GumBot:
  if spawned_bots.has(chatter.id):
    return spawned_bots[chatter.id]
  else:
    var bot: GumBot = gumbot_template.instantiate()
    spawned_bots[chatter.id] = bot

    add_child(bot)
    bot.chatter = chatter

    bot.global_position = bot_spawn_location.global_position + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-.5, .5))
    return bot

func bot_expired(bot: GumBot):
  bot.queue_free()
  spawned_bots.erase(bot.chatter.id)

func chat_message_received(message: Message.Chat):
  var bot := get_or_create_bot_for_user(message.chatter)
  bot.chatter = message.chatter

  print("Chat message received: ", message.message, " from ", message.chatter.display_name)

func _input(_event):
  if Input.is_action_just_pressed("StartLobby"):
    print(MultiplayerClient.state.current is MultiplayerClient.Disconnected)
    if MultiplayerClient.state.current is MultiplayerClient.Connected:
      MultiplayerClient.start_lobby()
    else:
      MultiplayerClient.join_lobby("")
    pass

var pong_game_template: PackedScene = preload("res://games/pong/pong_game.tscn")
var game_scene: PongGame = null
func _handle_lobby_updated(lobby: Lobby) -> void:
  print("Lobby updated: ", lobby)
  if lobby and lobby.started:
    bot_walking_scene.visible = false
    game_scene = pong_game_template.instantiate()
    game_scene.lobby = lobby
    print(lobby)
    game_root_node.add_child(game_scene)

#   if Input.is_action_just_pressed("tts_skip"):
#     tts_service.stop()

#   if Input.is_action_just_pressed("obs_scene_1"):
#     WSClient.toggle_obs_scene("StreamBasic")

#   if Input.is_action_just_pressed("debug_spawn_player"):
#     # chat_message_received(Message.Chat.FromData({ mes}.FromData({ id="test", display_name="test", login="test", color="red", emote="" }))
#     debug_bot_index += 1
