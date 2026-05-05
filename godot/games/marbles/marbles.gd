@tool
extends GameBase
class_name Marbles

var bots_by_peer_id: Dictionary[int, MarbleBot] = {}
var placements: Array[Chatter] = []
var marble_bot_template: PackedScene = ResourceLoader.load("res://games/marbles/marbles_bot/marbles_bot.tscn")

@onready var animation_synchronizer: AnimationSynchronizer = %AnimationSynchronizer
@onready var marbles_overlay: MarblesOverlay = $MarblesOverlay

var map: Array[PackedScene] = [
  preload("res://games/marbles/maps/marbles_map1.tscn"),
]

var current_map: MarblesMap
var marbles_game_state: MarblesGameState = null:
  set(new_state):
    marbles_game_state = new_state
    game_state = new_state

enum MarblesMessage {
  StateRefresh,
  MarblesUpdate,
  UpdateGamePhase,
  UsernameVisibility,
  SetGameWinner
}

signal leaderboard_updated

var _sync_accumulator: float = 0.0
const SYNC_RATE: float = 1.0 / 30.0
var leaderboard_update_timer = Timer.new()

func _ready() -> void:
  super._ready()
  if Engine.is_editor_hint():
    return
  
  add_child(leaderboard_update_timer)
  leaderboard_update_timer.wait_time = 1.0
  leaderboard_update_timer.one_shot = false
  leaderboard_update_timer.start()
  leaderboard_update_timer.timeout.connect(refresh_leaderboard)

  var map_scene = map[0]
  current_map = map_scene.instantiate()
  current_map.username_visibility_toggled.connect(toggle_username_visibility)
  animation_synchronizer.animation_player = current_map.animation_player
  add_child(current_map)

  marbles_overlay.map = current_map
  marbles_overlay.marble_selected.connect(func (marble: MarbleBot) -> void:
    focused_marble = marble
  )
  marbles_overlay.placement_changed.connect(increment_focused_bot)
  current_map.camera.did_enter_free_cam.connect(func() -> void:
    focused_marble = null
  )
  MultiplayerClient.connected_state.left_lobby.connect(_left_lobby)
  MultiplayerClient.packet_received.connect(_handle_peer_packet)

  animation_synchronizer.animation_finished.connect(handle_anim_finished)
  chatter_loaded.connect(_on_loaded_chatter_data)

  # Get all nodes in a group for the current map
  _bind_inputs()
  if is_game_host:
    SessionSynchronizer.get_instance().peer_is_ready.connect(_peer_is_ready)
    SessionSynchronizer.get_instance().all_peers_ready.connect(server_only_start_game)

    current_map.finish_area.body_entered.connect(on_finish_area_entered)
    current_map.out_of_bounds_area.body_entered.connect(_authority_handle_marble_out_of_bounds)

    var new_state := MarblesGameState.new()
    new_state.started_at = Time.get_unix_time_from_system()

    _handle_peer_packet(1, { "type": MarblesMessage.StateRefresh, "state": new_state })
    _send_refresh_state(MultiplayerPeer.TARGET_PEER_BROADCAST)

func toggle_username_visibility(new_visibility: bool) -> void:
  _handle_peer_packet(1, { "type": MarblesMessage.UsernameVisibility, "visibility": new_visibility })

func handle_lobby_updated() -> void:
  if MultiplayerClient.is_lobby_host():
    _server_spawn_all_new_players()

func _authority_handle_marble_out_of_bounds(body: Node) -> void:
  if body is MarbleBot:
    var marble_bot: MarbleBot = body as MarbleBot
    marble_bot.global_position = _get_random_spawn_position(0) # TODO: This should probably be based on the marble's original spawn position or something instead of always using the first spawn point
    marble_bot.linear_velocity = Vector3.ZERO

func _bind_inputs() -> void:
  if InputMap.has_action("next_placement"):
    return
  InputMap.add_action("next_placement")
  InputMap.add_action("previous_placement")

  var next_placement_event := InputEventKey.new()
  next_placement_event.physical_keycode = KEY_UP
  InputMap.action_add_event("next_placement", next_placement_event)

  var previous_placement_event := InputEventKey.new()
  previous_placement_event.physical_keycode = KEY_DOWN
  InputMap.action_add_event("previous_placement", previous_placement_event)

func handle_anim_finished(_anim_name: String) -> void:
  if _anim_name == "Intro":
    var anim_camera := get_viewport().get_camera_3d()
    current_map.camera.snap_to_camera(anim_camera)
    current_map.camera.camera.current = true

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
  for action in ["next_placement", "previous_placement"]:
    if InputMap.has_action(action):
      InputMap.erase_action(action)
  if Engine.is_editor_hint():
    return
  if MultiplayerClient.connected_state:
    MultiplayerClient.connected_state.left_lobby.disconnect(_left_lobby)
  MultiplayerClient.packet_received.disconnect(_handle_peer_packet)

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
  refresh_leaderboard()

  leaderboard_update_timer.start(0)
  if focused_marble == null:
    return
  var current_index := leaderboard.find(focused_marble)
  var new_index := (current_index + index_change) % leaderboard.size()
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

## Extra Y offset added on top of the raycast ground hit, so marbles spawn above the surface.
## Set this to the marble's radius to avoid spawning inside geometry.
@export var spawn_ground_offset: float = 0.15

func _get_random_spawn_position(join_index: int) -> Vector3:
  var spawn_path_length = current_map.spawn_path.curve.get_baked_length()
  var spawn_path_offset = spawn_path_length / lobby.peers.size() * join_index
  var spawn_transform = current_map.spawn_path.global_transform * current_map.spawn_path.curve.sample_baked_with_rotation(spawn_path_offset)
  var random_position_offset := Vector3(randf_range(-.2, .2), 0.0, randf_range(-.2, .2))
  var base_position: Vector3 = spawn_transform.origin + random_position_offset

  var space := get_world_3d().direct_space_state
  var ray := PhysicsRayQueryParameters3D.create(
    base_position + Vector3.UP * 2.0,
    base_position + Vector3.DOWN * 10.0
  )
  ray.collision_mask = 1
  var hit := space.intersect_ray(ray)
  if hit:
    return hit.position + Vector3.UP * spawn_ground_offset

  return base_position

func _server_spawn_all_new_players() -> void:
  marbles_overlay.bots_by_peer_id = bots_by_peer_id

  var join_index: int = 0
  for peer in lobby.peers:
    # Only spawn a marble for this peer if they don't already have one (e.g. from a previous game or from joining late)
    if game_state.marbles_by_peer_id.has(peer.peer_id):
      continue

    var marble_state := MarblesGameState.MarbleState.new()
    marble_state.position = _get_random_spawn_position(join_index)
    marble_state.rotation = Vector3.ZERO
    marble_state.frozen = game_state.game_state != MarblesGameState.GameState.Playing
    game_state.marbles_by_peer_id.set(peer.peer_id, marble_state)
    var marble := get_or_create_bot_for_peer(peer.peer_id)
    marble.global_position = marble_state.position
    marble.global_rotation = marble_state.rotation
    marble.sync_state = marble_state
    print("SERVER is spawning peer marble ", peer.peer_id, " frozen =>  ", marble_state.frozen)

    join_index += 1

var started = false
func server_only_start_game() -> void:
  if started:
    assert(false, "server_only_start_game called multiple times, this should never happen")
  started = true

  _server_spawn_all_new_players()
  _send_refresh_state(MultiplayerPeer.TARGET_PEER_BROADCAST)
  _apply_game_state()

  if is_game_host:
    animation_synchronizer.authority_play_animation("Intro")
    await animation_synchronizer.animation_finished

    MultiplayerClient.send_packet(
      { "type": MarblesMessage.UpdateGamePhase, "phase": MarblesGameState.GameState.Playing },
      MultiplayerPeer.TARGET_PEER_BROADCAST,
      MultiplayerPeer.TRANSFER_MODE_RELIABLE,
      MultiplayerClient.PacketSelfMode.SelfIncluded
    )

func _on_loaded_chatter_data(chatter: Chatter) -> void:
  var peer_id: int = lobby.peer_from_chatter.get(chatter.id, -1)
  if peer_id == -1:
    print("Warning: Received loaded chatter data for chatter %s with no associated peer_id" % chatter.id)
    return
  # if !MultiplayerClient.is_lobby_host():
  #   print("loaded chatter on non-host!! ", chatter.login)

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
  return bot

var game_is_finished := false
func on_finish_area_entered(body: PhysicsBody3D) -> void:
  if game_is_finished or !MultiplayerClient.is_lobby_host():
    return

  if body is MarbleBot:
    if not placements.has(body.chatter):
      placements.append(body.chatter)
      game_is_finished = true
      MultiplayerClient.send_packet(
        { "type": MarblesMessage.UpdateGamePhase, "phase": MarblesGameState.GameState.Slowmo },
        MultiplayerPeer.TARGET_PEER_BROADCAST,
        MultiplayerPeer.TRANSFER_MODE_RELIABLE,
        MultiplayerClient.PacketSelfMode.SelfIncluded
      )
      await get_tree().create_timer(.15).timeout
      MultiplayerClient.send_packet(
        { "type": MarblesMessage.SetGameWinner, "chatter": body.chatter.id if body.chatter != null else -1 },
        MultiplayerPeer.TARGET_PEER_BROADCAST,
        MultiplayerPeer.TRANSFER_MODE_RELIABLE,
        MultiplayerClient.PacketSelfMode.SelfIncluded
      )
      await get_tree().create_timer(.15).timeout
      MultiplayerClient.send_packet(
        { "type": MarblesMessage.UpdateGamePhase, "phase": MarblesGameState.GameState.Ended },
        MultiplayerPeer.TARGET_PEER_BROADCAST,
        MultiplayerPeer.TRANSFER_MODE_RELIABLE,
        MultiplayerClient.PacketSelfMode.SelfIncluded
      )
      await get_tree().create_timer(5.0).timeout
      game_finished.emit()

func _handle_peer_packet(sender_id: int, packet: Dictionary) -> void:
  if game_state == null and packet.type != MarblesMessage.StateRefresh:
    return

  match packet.type:
    SessionSynchronizer.GlobalGameMessage.ClientReady:
      _send_refresh_state(sender_id)
    MarblesMessage.SetGameWinner:
      var winner_id: String = packet.get("chatter", "")
      print("winner_id ", winner_id)
      marbles_game_state.winning_chatter = winner_id
    MarblesMessage.StateRefresh:
      var incoming = packet.get("state")
      if incoming is MarblesGameState:
        marbles_game_state = incoming
    MarblesMessage.UpdateGamePhase:
      if marbles_game_state:
        marbles_game_state.game_state = packet.get("phase", MarblesGameState.GameState.Waiting)
        for game_state_marble in marbles_game_state.marbles_by_peer_id.values():
          game_state_marble.frozen = false
    MarblesMessage.MarblesUpdate:
      var updates: Dictionary = packet.get("marbles", {})
      for peer_id: int in updates:
        var data: Dictionary = updates[peer_id]
        if not marbles_game_state.marbles_by_peer_id.has(peer_id):
          marbles_game_state.marbles_by_peer_id[peer_id] = MarblesGameState.MarbleState.new()
        var marble_state := marbles_game_state.marbles_by_peer_id[peer_id]
        marble_state.position = data.get("position", Vector3.ZERO)
        marble_state.rotation = data.get("rotation", Vector3.ZERO)
        marble_state.linear_velocity = data.get("linear_velocity", Vector3.ZERO)
    MarblesMessage.UsernameVisibility:
      marbles_game_state.username_visibility = packet.get("visibility", false)
  _apply_game_state()

func _apply_game_state() -> void:
  if game_state == null:
    return
  for peer_id in game_state.marbles_by_peer_id:
    var marble: MarbleBot = get_or_create_bot_for_peer(peer_id)
    var marble_state: MarblesGameState.MarbleState = game_state.marbles_by_peer_id[peer_id]
    marble.sync_state = marble_state
    marble.show_username = game_state.username_visibility
  for prop in current_map.all_props:
    prop.game_started_at = game_state.started_at

  if marbles_game_state.game_state == MarblesGameState.GameState.Slowmo:
    Engine.time_scale = 0.1
  else:
    Engine.time_scale = 1.0
  
  var winning_chatter = chatters.get(marbles_game_state.winning_chatter)\
    if chatters.has(marbles_game_state.winning_chatter)\
    else null
  marbles_overlay.winning_chatter = winning_chatter
  marbles_overlay.hud_hidden = marbles_game_state.game_state != MarblesGameState.GameState.Playing

func _physics_process(delta: float) -> void:
  if Engine.is_editor_hint(): return
  if not MultiplayerClient.is_lobby_host(): return
  if game_state == null: return

  _sync_accumulator += delta / Engine.time_scale
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
      var s := marbles_game_state.marbles_by_peer_id[peer_id]
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
