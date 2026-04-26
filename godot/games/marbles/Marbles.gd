@tool
extends GameBase
class_name Marbles

var bots_by_peer_id: Dictionary[int, MarbleBot] = {}
var placements: Array[Chatter] = []
var marble_bot_template: PackedScene = ResourceLoader.load("res://games/marbles/marbles_bot/marbles_bot.tscn")

@onready var marbles_overlay: MarblesOverlay = $MarblesOverlay

var map: Array[PackedScene] = [
  preload("res://games/marbles/maps/marbles_map1.tscn"),
]

var current_map: MarblesMap
var game_state: MarblesGameState = null

enum MarblesMessage {
  StateRefresh,
  MarblesUpdate,
  GameStart,
}

var _sync_accumulator: float = 0.0
const SYNC_RATE: float = 1.0 / 20.0

func _ready() -> void:
  super._ready()
  if Engine.is_editor_hint():
    return

  var map_scene = map[0]
  current_map = map_scene.instantiate()
  add_child(current_map)

  marbles_overlay.map = current_map
  marbles_overlay.marble_selected.connect(follow_marble)
  MultiplayerClient.connected_state.left_lobby.connect(_left_lobby)
  MultiplayerClient.packet_received.connect(_handle_peer_packet)

  if is_game_host:
    peer_is_ready.connect(_peer_is_ready)
    all_peers_loaded_in.connect(server_only_start_game)
    chatter_loaded.connect(_on_loaded_chatter_data)
    var new_state := MarblesGameState.new()
    MultiplayerClient.rtc_peer_ready.connect(_peer_is_ready)
    _handle_peer_packet(1, { "type": MarblesMessage.StateRefresh, "state": new_state })
    _send_refresh_state(MultiplayerPeer.TARGET_PEER_BROADCAST)

func follow_marble(marble: MarbleBot) -> void:
  current_map.camera.enter_follow_mode(marble)

func _peer_is_ready(peer_id: int) -> void:
  print("PEER IS READY")
  _send_refresh_state(peer_id)

func _exit_tree() -> void:
  if Engine.is_editor_hint():
    return
  if MultiplayerClient.connected_state:
    MultiplayerClient.connected_state.left_lobby.disconnect(_left_lobby)
  MultiplayerClient.packet_received.disconnect(_handle_peer_packet)
  if is_game_host:
    MultiplayerClient.rtc_peer_ready.disconnect(_send_refresh_state)

func _left_lobby() -> void:
  game_finished.emit()

func _send_refresh_state(peer_id: int) -> void:
  MultiplayerClient.send_packet(
    { "type": MarblesMessage.StateRefresh, "state": game_state },
    peer_id,
    MultiplayerPeer.TRANSFER_MODE_RELIABLE
  )

var started := false
func server_only_start_game() -> void:
  if started: return # TODO: Allow late joins?
  started = true

  marbles_overlay.bots_by_peer_id = bots_by_peer_id
  current_map.finish_area.body_entered.connect(on_finish_area_entered)

  var join_index: int = 0
  for peer in lobby.peers:
    var marble_state := MarblesGameState.MarbleState.new()
    var spawn_path_length = current_map.spawn_path.curve.get_baked_length()
    var spawn_path_offset = spawn_path_length / lobby.peers.size() * join_index
    var spawn_transform = current_map.spawn_path.global_transform * current_map.spawn_path.curve.sample_baked_with_rotation(spawn_path_offset)
    var random_position_offset := Vector3(randf_range(-.2, .2), 0.0, randf_range(-.2, .2))
    marble_state.position = spawn_transform.origin + random_position_offset
    marble_state.rotation = spawn_transform.basis.get_euler()

    game_state.marbles_by_peer_id.set(peer.peer_id, marble_state)
    var marble := get_or_create_bot_for_peer(peer.peer_id)
    marble.global_position = marble_state.position
    marble.global_rotation = marble_state.rotation

    join_index += 1

  _send_refresh_state(MultiplayerPeer.TARGET_PEER_BROADCAST)
  _apply_game_state()

  if is_game_host:
    await get_tree().create_timer(3.0).timeout
    MultiplayerClient.send_packet(
      { "type": MarblesMessage.GameStart },
      MultiplayerPeer.TARGET_PEER_BROADCAST,
      MultiplayerPeer.TRANSFER_MODE_RELIABLE,
      true
    )

func _on_loaded_chatter_data(chatter: Chatter) -> void:
  var peer_id: int = lobby.peer_from_chatter.get(chatter.id, -1)
  if peer_id == -1:
    print("Warning: Received loaded chatter data for chatter %d with no associated peer_id" % chatter.id)
    return
  var marble := get_or_create_bot_for_peer(peer_id)
  marble.chatter = chatter

func get_or_create_bot_for_peer(peer_id: int) -> MarbleBot:
  # Return cached bot if it exists
  if bots_by_peer_id.has(peer_id):
    return bots_by_peer_id[peer_id]

  var bot: MarbleBot = marble_bot_template.instantiate()
  add_child(bot)

  bots_by_peer_id.set(peer_id, bot)

  var chatter_id: String = lobby.chatter_from_peer.get(peer_id, -1)
  var chatter: Chatter = chatters.get(chatter_id)
  if chatter != null:
    bot.chatter = chatter

  if not is_game_host:
    bot.freeze = true
  return bot

func on_finish_area_entered(body: PhysicsBody3D) -> void:
  if body is MarbleBot:
    if not placements.has(body.chatter):
      placements.append(body.chatter)

func _handle_peer_packet(sender_id: int, packet: Dictionary) -> void:
  if game_state == null and packet.type != MarblesMessage.StateRefresh:
    return

  match packet.type:
    GlobalGameMessage.ClientReady:
      _send_refresh_state(sender_id)
    MarblesMessage.StateRefresh:
      var incoming = packet.get("state")
      if incoming is MarblesGameState:
        game_state = incoming
    MarblesMessage.GameStart:
      if game_state:
        game_state.game_state = MarblesGameState.GameState.Playing
      for bot in bots_by_peer_id.values():
        bot.frozen = false
    MarblesMessage.MarblesUpdate:
      var updates: Dictionary = packet.get("marbles", {})
      for peer_id: int in updates:
        var data: Dictionary = updates[peer_id]
        if not game_state.marbles_by_peer_id.has(peer_id):
          game_state.marbles_by_peer_id[peer_id] = MarblesGameState.MarbleState.new()
        var marble_state := game_state.marbles_by_peer_id[peer_id]
        marble_state.position = data.get("position", Vector3.ZERO)
        marble_state.rotation = data.get("rotation", Vector3.ZERO)
        marble_state.linear_velocity = data.get("linear_velocity", Vector3.ZERO)

  _apply_game_state()

func _apply_game_state() -> void:
  if game_state == null:
    return
  for peer_id in game_state.marbles_by_peer_id:
    var marble: MarbleBot = get_or_create_bot_for_peer(peer_id)
    var marble_state: MarblesGameState.MarbleState = game_state.marbles_by_peer_id[peer_id]
    marble.sync_state = marble_state

func _physics_process(delta: float) -> void:
  if Engine.is_editor_hint(): return
  if not is_game_host: return
  if game_state == null or game_state.game_state != MarblesGameState.GameState.Playing: return

  _sync_accumulator += delta
  if _sync_accumulator >= SYNC_RATE:
    _sync_accumulator -= SYNC_RATE
    _broadcast_marble_states()

func _broadcast_marble_states() -> void:
  var marbles: Dictionary = {}
  for peer_id in bots_by_peer_id:
    var bot: MarbleBot = bots_by_peer_id[peer_id]
    marbles[peer_id] = {
      "position": bot.global_position,
      "rotation": bot.rotation,
      "linear_velocity": bot.linear_velocity,
    }
    if game_state.marbles_by_peer_id.has(peer_id):
      var s := game_state.marbles_by_peer_id[peer_id]
      s.position = bot.global_position
      s.rotation = bot.rotation
      s.linear_velocity = bot.linear_velocity
    else:
      print("Warning: No marble state found for peer_id %d when broadcasting updates" % peer_id)

  MultiplayerClient.send_packet(
    { "type": MarblesMessage.MarblesUpdate, "marbles": marbles },
    MultiplayerPeer.TARGET_PEER_BROADCAST,
    MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
  )
