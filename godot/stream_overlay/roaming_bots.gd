extends Node3D
class_name RoamingBots

@onready var camera: Camera3D = %Camera
@onready var bot_spawn_location: Node3D = %BotSpawnLocation
@onready var gamba_action_handler: GambaActionHandler = %GambaActionHandler
@onready var tts_action_handler: TTSActionHandler = %TTSActionHandler
@onready var action_queue_manager: ActionQueueManager = %ActionQueueManager

@onready var change_role_button: Button = %ChangeRoleButton
@onready var close_lobby_button: Button = %CloseLobbyButton
@onready var start_game_button: Button = %StartGameButton

var spawned_bots = {}

func _ready():
  WSClient.authenticated_state.chat_message_received.connect(chat_message_received)
  WSClient.authenticated_state.store_data_received.connect(store_data_received)
  WSClient.authenticated_state.chatter_updated.connect(chatter_updated)
  WSClient.authenticated_state.emote_triggered.connect(emote_triggered)

  MultiplayerClient.connected_state.lobby_updated.connect(_lobby_updated)
  MultiplayerClient.state.changed.connect(_multiplayer_state_changed)

  start_game_button.pressed.connect(_handle_start_game)

  _handle_update()
  store_data_received()
  _poll_action_queue()

  close_lobby_button.pressed.connect(_close_lobby)

func _handle_start_game() -> void:
  MultiplayerClient.start_lobby()

func _close_lobby() -> void:
  MultiplayerClient.leave_lobby()

func _change_role(is_player: bool) -> void:
  MultiplayerClient.set_role(is_player)

func _lobby_updated() -> void:
  _handle_update()

func _multiplayer_state_changed(_state: MultiplayerClient.MultiplayerClientState) -> void:
  _handle_update()

func _handle_update():
  var lobby = MultiplayerClient.current_lobby
  if MultiplayerClient.state.current is MultiplayerClient.Disconnected or lobby == null:
    change_role_button.visible = false
    close_lobby_button.visible = false
    start_game_button.visible = false
    return

  var my_peer := _find_my_peer()
  if !lobby.started and my_peer:
    change_role_button.visible = true
    for c in change_role_button.pressed.get_connections():
        change_role_button.pressed.disconnect(c.callable)
    
    start_game_button.visible = true
    start_game_button.disabled = !lobby.can_be_started(my_peer.peer_id)
    change_role_button.pressed.connect(_change_role.bind(!my_peer.is_player))
    change_role_button.text = "PLAYING" if my_peer.is_player else "SPECTATING"
    close_lobby_button.visible = MultiplayerClient.is_lobby_host()
  else:
    start_game_button.visible = false
    change_role_button.visible = false
    close_lobby_button.visible = false

func _find_my_peer() -> Lobby.PeerData:
  var my_chatter_id := WSClient.my_chatter().id
  var lobby := MultiplayerClient.current_lobby
  if lobby == null: return
  for peer in lobby.peers:
    if peer.chatter_id == my_chatter_id:
      return peer
  return null

func _poll_action_queue() -> void:
  while is_inside_tree():
    await get_tree().create_timer(1.0).timeout
    var action = action_queue_manager.get_next_valid_action()
    if action == null:
      continue
    if action is Message.SlotsRequest:
      action_queue_manager.complete_action(action)
      await gamba_action_handler.handle_action(action, action_queue_manager)
    elif action is Message.TTSRequest:
      action_queue_manager.complete_action(action)
      await tts_action_handler.handle_action(action)

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
