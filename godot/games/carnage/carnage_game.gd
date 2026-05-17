@tool
extends GameBase
class_name Carnage

enum CarnageGameMessage {
  ServerKartPunch,
}

@onready var spawn_center_node: Marker3D = %SpawnCenter
@onready var camera_boom: Node3D = %BoomNode
@onready var camera: Camera3D = %Camera2
@onready var debug_camera: DebugCamera = %DebugCamera
@onready var game_state: KartGameStateSynchronizer = %KartGameStateSynchronizer
@onready var spawn_path: Path3D = %SpawnPath
@onready var out_of_bounds_area: Area3D = %OutOfBoundsArea
@onready var in_bounds_area: Area3D = %InBoundsArea
@onready var winner_text: RichTextLabel = %WinnerText

var checkpoints: Array[RaceCheckpoint] = []

func _ready() -> void:
  super._ready()
  if Engine.is_editor_hint(): return

  _setup_checkpoints()

  chatter_loaded.connect(_handle_chatter_loaded)
  game_state.state_updated.connect(_apply_state)
  out_of_bounds_area.body_entered.connect(_out_of_bounds_area_entered)
  in_bounds_area.body_exited.connect(_in_bounds_area_exited)
  await get_tree().create_timer(2.0).timeout
  spawn_cars()
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
  for child in get_children():
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
      debug_camera.enter_free_mode()

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
  var join_index := lobby.peers.map(func(p): return p.peer_id).find(peer_id)
  var last_checkpoint: int = game_state.get_last_reached_checkpoint(peer_id)
  if last_checkpoint >= 0 and last_checkpoint < checkpoints.size():
    var checkpoint: RaceCheckpoint = checkpoints[last_checkpoint]
    var checkpoint_transform: Transform3D = checkpoint.global_transform
    var spawn_margins := 0.4
    var total_spawn_width := checkpoint.width - spawn_margins * 2.0
    checkpoint_transform = checkpoint_transform.translated(Vector3(-total_spawn_width * 0.5 + join_index * total_spawn_width, 0, 0))
    return checkpoint_transform

  var spawn_path_length = spawn_path.curve.get_baked_length()
  var spawn_path_offset = spawn_path_length / lobby.players.size() * join_index
  var spawn_transform = spawn_path.global_transform * spawn_path.curve.sample_baked_with_rotation(spawn_path_offset)
  return spawn_transform

func spawn_cars() -> void:
  for peer in lobby.peers:
    var kart_inst := physics_car_template.instantiate() as PhysicsKart
    add_child(kart_inst)

    var spawn_transform := get_spawn_transform(peer.peer_id)
    kart_inst.global_transform = spawn_transform
    kart_inst.physics_kart_movement_sync.owner_peer_id = peer.peer_id
    kart_inst.physics_kart_movement_sync.kart_flipped.connect(respawn_kart.bind(peer.peer_id))
    karts_by_peer_id[peer.peer_id] = kart_inst

    if peer.peer_id == MultiplayerClient.my_peer_id():
      debug_camera._follow_state.move_lerp = 5.0
      debug_camera.set_default_orbit_distance(5.5)
      debug_camera.enter_follow_mode(kart_inst, deg_to_rad(35.0))

func start_game() -> void:
  pass
# func handle_anim_finished(_anim_name: String) -> void:
#   if _anim_name == "Intro":
#     var anim_camera := get_viewport().get_camera_3d()
#     current_map.camera.snap_to_camera(anim_camera)
#     current_map.actual_camera.current = true
