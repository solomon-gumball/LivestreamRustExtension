@tool
extends GameBase
class_name Marbles

var spawned_bots: Dictionary[String, MarbleBot] = {}
var placements: Array[Chatter] = []
var MarbleBotScene: PackedScene = ResourceLoader.load("res://games/marbles/MarbleBot.tscn")

@onready var marbles_overlay: MarblesOverlay = $MarblesOverlay

var map: Array[PackedScene] = [
  preload("res://games/marbles/marbles_map1.tscn"),
]

var current_map: MarblesMap

enum GameState { Waiting, Playing, Ended }

var game_state: GameState = GameState.Waiting

func _ready() -> void:
  super._ready()

  assert(lobby != null, "Lobby should never be null in a GameBase instance")

  var map_scene = map[0]
  current_map = map_scene.instantiate()
  add_child(current_map)

  marbles_overlay.spawned_bots = spawned_bots

  # Network.chat_message_received.connect(chat_message_received)
  current_map.out_of_bounds_area.body_entered.connect(on_out_of_bounds_area_entered)
  current_map.finish_area.body_entered.connect(on_finish_area_entered)

  var join_index: int = 0
  for peer in lobby.peers:
    var spawn_path_length = current_map.spawn_path.curve.get_baked_length()
    var spawn_path_offset = spawn_path_length / lobby.peers.size() * join_index
    var spawn_transform = current_map.spawn_path.global_transform * current_map.spawn_path.curve.sample_baked_with_rotation(spawn_path_offset)
    var bot = get_or_create_bot_for_user(peer.chatter, spawn_transform)
    bot.scale = Vector3(1.0, 1.0, 1.0)
    bot.position += Vector3(randf_range(-.2, .2), 0.0, randf_range(-.2, .2))
    bot.frozen = true
    join_index += 1
  
  await get_tree().create_timer(3.0).timeout
  game_state = GameState.Playing
  for bot in spawned_bots.values():
    bot.frozen = false

func chat_message_received(message: String, chatter: Chatter):
  if chatter_is_participant(chatter):
    var bot = get_or_create_bot_for_user(chatter)
    bot.chatter = chatter
    bot.update_message(message)

func chatter_is_participant(chatter: Chatter) -> bool:
  return lobby.peers.filter(func (peer): return chatter.id == peer.chatter.id).size() > 0

var eliminated_players: Array[Chatter] = []
func on_out_of_bounds_area_entered(body: PhysicsBody3D) -> void:
  if body is MarbleBot:
    if !eliminated_players.has(body.chatter):
      eliminated_players.append(body.chatter)
      body.frozen = true
      body.visible = false
      check_completed()

func check_completed() -> void:
  if placements.size() > 0:
    var winner: Chatter = placements[0]
    var bot = get_or_create_bot_for_user(winner)
    bot.frozen = true
    # Overlay.show_activity_winner(winner, activity)
    game_state = GameState.Ended

func on_finish_area_entered(body: PhysicsBody3D) -> void:
  if body is MarbleBot:
    if !placements.has(body.chatter):
      placements.append(body.chatter)
      check_completed()

func get_or_create_bot_for_user(chatter: Chatter, spawn_transform: Transform3D = Transform3D.IDENTITY) -> MarbleBot:
  if spawned_bots.has(chatter.id):
    return spawned_bots[chatter.id]
  else:
    var bot: MarbleBot = MarbleBotScene.instantiate()
    spawned_bots[chatter.id] = bot
    bot.global_transform = spawn_transform
    add_child(bot)
    bot.chatter = chatter
    return bot
