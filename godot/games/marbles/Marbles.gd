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

signal leaderboard_updated

var _sync_accumulator: float = 0.0
const SYNC_RATE: float = 1.0 / 20.0

func _ready() -> void:
  super._ready()
  if Engine.is_editor_hint():
    return
  
  var update_timer = Timer.new()
  add_child(update_timer)
  update_timer.wait_time = 2.0
  update_timer.one_shot = false
  update_timer.start()
  update_timer.timeout.connect(refresh_leaderboard)

  var map_scene = map[0]
  current_map = map_scene.instantiate()
  add_child(current_map)

  marbles_overlay.map = current_map
  marbles_overlay.marble_selected.connect(func (marble: MarbleBot) -> void:
    focused_marble = marble
  )
  marbles_overlay.placement_selected.connect(_placement_selected)

  current_map.camera.did_enter_free_cam.connect(func() -> void:
    focused_marble = null
  )
  MultiplayerClient.connected_state.left_lobby.connect(_left_lobby)
  MultiplayerClient.packet_received.connect(_handle_peer_packet)

  _bind_inputs()

  if is_game_host:
    current_map.out_of_bounds_area.body_entered.connect(_authority_handle_marble_out_of_bounds)
    peer_is_ready.connect(_peer_is_ready)
    all_peers_loaded_in.connect(server_only_start_game)
    chatter_loaded.connect(_on_loaded_chatter_data)
    var new_state := MarblesGameState.new()
    MultiplayerClient.rtc_peer_ready.connect(_peer_is_ready)
    _handle_peer_packet(1, { "type": MarblesMessage.StateRefresh, "state": new_state })
    _send_refresh_state(MultiplayerPeer.TARGET_PEER_BROADCAST)

func _authority_handle_marble_out_of_bounds(body: Node) -> void:
  if body is MarbleBot:
    var marble_bot: MarbleBot = body as MarbleBot
    print("Marble %s went out of bounds, resetting position" % body.chatter.display_name)
    marble_bot.global_position = _get_random_spawn_position(0) # TODO: This should probably be based on the marble's original spawn position or something instead of always using the first spawn point
    marble_bot.linear_velocity = Vector3.ZERO

func _bind_inputs() -> void:
  InputMap.add_action("next_placement")
  InputMap.add_action("previous_placement")

  var next_placement_event := InputEventKey.new()
  next_placement_event.physical_keycode = KEY_RIGHT
  InputMap.action_add_event("next_placement", next_placement_event)

  var previous_placement_event := InputEventKey.new()
  previous_placement_event.physical_keycode = KEY_LEFT
  InputMap.action_add_event("previous_placement", previous_placement_event)

func _placement_selected(placement: int) -> void:
  if leaderboard.get(placement):
    var marble = leaderboard[placement]
    focused_marble = marble

var focused_marble: MarbleBot = null:
  set(new_value):
    if new_value != null:
      current_map.camera.enter_follow_mode(new_value)
      marbles_overlay.set_focused_bot(new_value, leaderboard.find(new_value))
    else:
      marbles_overlay.set_focused_bot(null)
    focused_marble = new_value

func _peer_is_ready(peer_id: int) -> void:
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

func _input(event: InputEvent) -> void:
  if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
    _try_follow_marble_at_cursor(event.position)
  if Input.is_action_just_pressed("next_placement"):
    increment_focused_bot(-1)
  if Input.is_action_just_pressed("previous_placement"):
    increment_focused_bot(1)

func increment_focused_bot(index_change: int) -> void:
  if focused_marble == null:
    return
  var current_index := leaderboard.find(focused_marble)
  var new_index := current_index + index_change
  if new_index >= 0 and new_index < leaderboard.size():
    focused_marble = leaderboard[new_index]

func _try_follow_marble_at_cursor(screen_pos: Vector2) -> void:
  var origin := current_map.camera.camera.project_ray_origin(screen_pos)
  var direction := current_map.camera.camera.project_ray_normal(screen_pos)
  var space := get_world_3d().direct_space_state
  var shape := SphereShape3D.new()
  shape.radius = 0.4
  var query := PhysicsShapeQueryParameters3D.new()
  query.shape = shape
  query.transform = Transform3D(Basis.IDENTITY, origin)
  query.motion = direction * 1000.0
  query.collision_mask = 2
  var result := space.cast_motion(query)
  if result[0] < 1.0:
    var hit_pos := origin + direction * 1000.0 * result[1]
    var shape_query := PhysicsShapeQueryParameters3D.new()
    shape_query.shape = shape
    shape_query.transform = Transform3D(Basis.IDENTITY, hit_pos)
    shape_query.collision_mask = 2
    var hits := space.intersect_shape(shape_query)
    if hits.size() > 0 and hits[0].collider is Node3D:
      var selected_marble := hits[0].collider as MarbleBot
      focused_marble = selected_marble

func _get_random_spawn_position(join_index: int) -> Vector3:
  var spawn_path_length = current_map.spawn_path.curve.get_baked_length()
  var spawn_path_offset = spawn_path_length / lobby.peers.size() * join_index
  var spawn_transform = current_map.spawn_path.global_transform * current_map.spawn_path.curve.sample_baked_with_rotation(spawn_path_offset)
  var random_position_offset := Vector3(randf_range(-.2, .2), 0.0, randf_range(-.2, .2))
  return spawn_transform.origin + random_position_offset

var started := false
func server_only_start_game() -> void:
  if started: return # TODO: Allow late joins?
  started = true

  marbles_overlay.bots_by_peer_id = bots_by_peer_id
  current_map.finish_area.body_entered.connect(on_finish_area_entered)

  var join_index: int = 0
  for peer in lobby.peers:
    var marble_state := MarblesGameState.MarbleState.new()

    marble_state.position = _get_random_spawn_position(join_index)
    marble_state.rotation = Vector3.ZERO

    game_state.marbles_by_peer_id.set(peer.peer_id, marble_state)
    var marble := get_or_create_bot_for_peer(peer.peer_id)
    # marble.freeze = true
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

var leaderboard: Array[MarbleBot] = []
func refresh_leaderboard() -> void:
  leaderboard.clear()
  leaderboard.assign(bots_by_peer_id.values())

  var curve := current_map.progress_curve.curve
  leaderboard.sort_custom(func(a: MarbleBot, b: MarbleBot) -> bool:
    return curve.get_closest_offset(a.global_position) > curve.get_closest_offset(b.global_position)
  )

  marbles_overlay.refresh_leaderboard(leaderboard)
