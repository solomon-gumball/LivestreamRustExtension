@tool
extends GameBase
class_name Carnage

enum CarnageGameMessage {
  ServerKartPunch,
}

@onready var spawn_center_node: Marker3D = %SpawnCenter
@onready var camera_boom: Node3D = %BoomNode

func _ready() -> void:
  super._ready()
  SessionSynchronizer.get_instance().notify_ready()

  chatter_loaded.connect(_handle_chatter_loaded)

  await get_tree().create_timer(2.0).timeout
  spawn_cars()

func _handle_chatter_loaded(chatter: Chatter) -> void:
  if MultiplayerClient.current_lobby == null: return
  var chatter_peer_id: int = MultiplayerClient.current_lobby.peer_from_chatter.get(chatter.id, -1)
  var owning_kart: KartBot = karts_by_peer_id.get(chatter_peer_id, null)
  if owning_kart:
    owning_kart.gumbot.chatter = chatter
    
var karts_by_peer_id: Dictionary[int, KartBot] = {}

const spawn_ring_size := 1.0
const car_template: PackedScene = preload("res://games/carnage/kart/kart_bot.tscn")
const physics_car_template: PackedScene = preload("res://games/carnage/kart/physics_kart.tscn")

func spawn_cars() -> void:
  var i := 0
  var spawn_center := spawn_center_node.global_position
  for peer in lobby.peers:
    var progress := float(i) / minf(2.0, lobby.peers.size())
    var pos_offset := Vector3(cos(progress * TAU), 0.0, sin(progress * TAU))
    var location := spawn_center + pos_offset * spawn_ring_size

    # var kart_inst := car_template.instantiate() as KartBot
    var kart_inst := physics_car_template.instantiate() as PhysicsKart
    add_child(kart_inst)
    kart_inst.physics_kart_movement_sync.owner_peer_id = peer.peer_id
    # kart_inst.kart_movement.owner_peer_id = peer.peer_id
    # var chatter: Chatter = chatters.get(peer.chatter_id, null)
    # if chatter:
    #   kart_inst.gumbot.chatter = chatter
    # karts_by_peer_id.set(peer.peer_id, kart_inst)
    kart_inst.global_position = location
    kart_inst.look_at(Vector3.ZERO, Vector3.UP, true)
    if peer.peer_id == MultiplayerClient.my_peer_id():
      print("cam target set")
      cam_target = kart_inst

    i += 1

func start_game() -> void:
  pass
  
var cam_target: Node3D = null

func _physics_process(delta: float) -> void:
  if cam_target:
    camera_boom.global_position = camera_boom.global_position.lerp(cam_target.global_position, 5.0 * delta)
