extends Node3D
class_name RoamingBots

@onready var camera: Camera3D = %Camera
@onready var bot_spawn_location: Node3D = %BotSpawnLocation
@onready var gamba_action_handler: GambaActionHandler = %GambaActionHandler
@onready var action_queue_manager: ActionQueueManager = %ActionQueueManager

var spawned_bots = {}

func _ready():
  WSClient.authenticated_state.chat_message_received.connect(chat_message_received)
  WSClient.authenticated_state.store_data_received.connect(store_data_received)
  WSClient.authenticated_state.chatter_updated.connect(chatter_updated)
  WSClient.authenticated_state.emote_triggered.connect(emote_triggered)

  store_data_received()
  _poll_action_queue()

func _poll_action_queue() -> void:
  while is_inside_tree():
    await get_tree().create_timer(1.0).timeout
    if gamba_action_handler.is_busy():
      continue
    var action = action_queue_manager.get_next_valid_action()
    if action == null:
      continue
    if action is Message.SlotsRequest:
      action_queue_manager.complete_action(action)
      gamba_action_handler.handle_action(action, action_queue_manager)

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
