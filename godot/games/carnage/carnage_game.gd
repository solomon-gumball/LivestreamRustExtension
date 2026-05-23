@tool
extends GameBase
class_name Carnage

enum CarnageGameMessage {
  TriggerPunch,
  ServerKartPunch,
  HandleKartPunched
}

@onready var game_state: KartGameStateSynchronizer = %KartGameStateSynchronizer
@onready var winner_text: RichTextLabel = %WinnerText
@onready var countdown_label: RichTextLabel = %CountDownLabel
@onready var end_game_button: Button = %EndGameButton

var map: KartRaceMap = null
var checkpoints: Array[RaceCheckpoint] = []
var loading_check_timer: Timer = null

func load_map(map_name: String) -> KartRaceMap:
  if map:
    map.queue_free()

  var map_path := "res://games/carnage/maps/%s.tscn" % map_name
  var map_packed := load(map_path) as PackedScene
  map = map_packed.instantiate() as KartRaceMap
  return map

func _ready() -> void:
  super._ready()
  if Engine.is_editor_hint(): return

  end_game_button.visible = MultiplayerClient.is_lobby_host()
  end_game_button.pressed.connect(_on_end_game_button_pressed)

  # map = load_map("kart_race_joony1")
  map = load_map("kart_race_joony1")
  add_child(map)

  _setup_checkpoints()

  spawn_cars()
  chatter_loaded.connect(_handle_chatter_loaded)
  game_state.state_updated.connect(_apply_state)
  map.out_of_bounds_area.body_entered.connect(_out_of_bounds_area_entered)
  map.in_bounds_area.body_exited.connect(_in_bounds_area_exited)
  map.animation_synchronizer.animation_finished.connect(_animation_finished)

  # Force a render pass with the scene fully visible so the GPU pre-warms
  # all shaders and mesh uploads before the intro animation begins.
  # Without this, models popping into the camera's view during the pan cause
  # a one-frame GPU stall that shows as a visible framerate hiccup.
  map.animation_camera.current = true
  await RenderingServer.frame_post_draw
  await RenderingServer.frame_post_draw

  SessionSynchronizer.get_instance().notify_ready()

  loading_check_timer = Timer.new()
  add_child(loading_check_timer)
  loading_check_timer.timeout.connect(_check_loaded)
  loading_check_timer.one_shot = false
  loading_check_timer.start(1.0)

func _on_end_game_button_pressed() -> void:
  if !is_game_host: return
  game_finished.emit()

func _check_loaded() -> void:
  for peer_id in karts_by_peer_id:
    var kart := karts_by_peer_id[peer_id]
    if !kart.gumbot.is_outfit_loaded:
      return

  loading_check_timer.stop()
  SessionSynchronizer.get_instance().notify_ready()

func _out_of_bounds_area_entered(body: Node) -> void:
  if !is_game_host: return

  if body is PhysicsKart:
    var kart_bot: PhysicsKart = body as PhysicsKart
    respawn_kart(kart_bot.physics_kart_movement_sync.owner_peer_id)

func respawn_kart(peer_id: int) -> void:
  if !is_game_host: return
  var kart_bot: PhysicsKart = karts_by_peer_id.get(peer_id, null)
  if kart_bot == null: return

  var spawn_transform: Transform3D = get_spawn_transform(peer_id)

  kart_bot.physics_kart_movement_sync.authority_teleport({
    "position": spawn_transform.origin,
    "rotation": Quaternion(spawn_transform.basis),
    "linear_velocity": Vector3.ZERO,
    "angular_velocity": Vector3.ZERO,
    "wheel_turn": 0.0,
  })

func _in_bounds_area_exited(body: Node) -> void:
  if !is_game_host: return

  if body is PhysicsKart:
    var kart: PhysicsKart = body as PhysicsKart
    respawn_kart(kart.physics_kart_movement_sync.owner_peer_id)

func _setup_checkpoints() -> void:
  var checkpoint_index: int = 0
  for child in map.get_children():
    if child is RaceCheckpoint:
      var checkpoint := child as RaceCheckpoint
      checkpoints.append(child)
      if is_game_host:
        var callback: Callable = game_state.authority_checkpoint_reached.bind(checkpoint_index)
        checkpoint.checkpoint_reached.connect(callback)
      checkpoint_index += 1
  game_state.total_checkpoints_count = checkpoints.size()

func _apply_state() -> void:
  var my_peer_id := MultiplayerClient.my_peer_id()
  var last_reached_checkpoint: int = game_state.get_last_reached_checkpoint(my_peer_id)

  var index := 0
  for checkpoint in checkpoints:
    checkpoint.reached = last_reached_checkpoint >= index
    index += 1

  # Show winner text when 1st place finishes
  if game_state.game_state.results.size() > 0:
    var race_winner: KartGameStateSynchronizer.RaceResult = game_state.game_state.results.get(0)
    if race_winner:
      winner_text.text = format_winner_text(race_winner.peer_id)
      winner_text.visible = true
      var winning_kart := karts_by_peer_id[race_winner.peer_id]
      winning_kart.gumbot.enter_state("Win")
    else:
      winner_text.visible = false
  
  # Disable controls before and after race gameplay
  for peer_id in karts_by_peer_id:
    var kart := karts_by_peer_id[peer_id]
    var game_not_yet_started := game_state.game_state.start_time == -1
    var game_finished_for_player := game_state.game_state.results.find_custom(
      func (result: KartGameStateSynchronizer.RaceResult):
        return result.peer_id == peer_id
    ) != -1
    kart.physics_kart_movement_sync.inputs_disabled = game_not_yet_started or game_finished_for_player

    # If i have finished allow free cam
    if game_finished_for_player:
      map.debug_camera.enter_free_mode()

func format_winner_text(peer_id: int) -> String:
  var chatter: Chatter = get_chatter_for_peer_id(peer_id)
  var chatter_name: String = chatter.display_name if chatter else str(peer_id)
  return "\n".join([
    "[wave][color=pink]%s[/color][/wave]" % chatter_name,
    "[wave][color=green]wins![/color]",
  ])

func _handle_chatter_loaded(chatter: Chatter) -> void:
  if MultiplayerClient.current_lobby == null: return
  var chatter_peer_id: int = MultiplayerClient.current_lobby.peer_from_chatter.get(chatter.id, -1)
  var owning_kart: PhysicsKart = karts_by_peer_id.get(chatter_peer_id, null)
  if owning_kart:
    owning_kart.gumbot.chatter = chatter
    
var karts_by_peer_id: Dictionary[int, PhysicsKart] = {}

const spawn_ring_size := 1.0
const car_template: PackedScene = preload("res://games/carnage/kart/kart_bot.tscn")
const physics_car_template: PackedScene = preload("res://games/carnage/kart/physics_kart.tscn")

func get_spawn_transform(peer_id: int) -> Transform3D:
  var join_index := lobby.players.map(func(p): return p.peer_id).find(peer_id)
  var last_checkpoint: int = game_state.get_last_reached_checkpoint(peer_id)
  if last_checkpoint >= 0 and last_checkpoint < checkpoints.size():
    var checkpoint: RaceCheckpoint = checkpoints[last_checkpoint]
    var checkpoint_transform: Transform3D = checkpoint.global_transform
    checkpoint_transform.origin += Vector3.UP * 0.5

    if lobby.players.size() == 1:
      return checkpoint_transform

    var spawn_margins := 0.4
    var total_spawn_width := minf(checkpoint.width - spawn_margins * 2.0, 0.5 * float(lobby.players.size() - 1))
    var car_margins := total_spawn_width / float(lobby.players.size() - 1)
    var lateral_offset := -total_spawn_width * 0.5 + join_index * car_margins
    checkpoint_transform.origin += checkpoint_transform.basis.x * lateral_offset
    return checkpoint_transform

  return Transform3D.IDENTITY

func spawn_cars() -> void:
  for peer in lobby.players:
    var kart_inst := physics_car_template.instantiate() as PhysicsKart
    add_child(kart_inst)

    var spawn_transform := get_spawn_transform(peer.peer_id)
    kart_inst.global_transform = spawn_transform
    kart_inst.physics_kart_movement_sync.owner_peer_id = peer.peer_id
    kart_inst.physics_kart_movement_sync.kart_flipped.connect(respawn_kart.bind(peer.peer_id))
    karts_by_peer_id[peer.peer_id] = kart_inst

func _animation_finished(animation_name: String) -> void:
  if animation_name == "Intro":
    var kart: PhysicsKart = karts_by_peer_id.get(MultiplayerClient.my_peer_id(), null)
    map.debug_camera.snap_to_camera(map.animation_camera)
    # map.debug_camera._follow_state.move_lerp = 5.0
    map.debug_camera.set_default_orbit_distance(2.0)
    map.debug_camera.enter_follow_mode(kart, deg_to_rad(25.0), Vector3(0, 0.261, 0))
    map.debug_camera._follow_state.prevent_wall_clip = true
    map.debug_camera.allow_free_cam = !lobby.is_player(MultiplayerClient.my_peer_id())
    map.debug_camera._free_state.mouse_sensitivity = .001
    await get_tree().process_frame
    map.debug_inner_cam.current = true

func start_game() -> void:
  if !is_game_host: return
  map.animation_synchronizer.authority_play_animation("Intro")
  await map.animation_synchronizer.animation_finished
  game_state.authority_start_game()

func handle_lobby_updated() -> void:
  pass
