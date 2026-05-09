@tool
extends GameBase
class_name Carnage

enum CarnageGameMessage {
  ClientKartInputs,
  ServerKartState,
  PingNetTick,
  PongNetTick
}

@onready var spawn_center_node: Marker3D = %SpawnCenter

func _ready() -> void:
  super._ready()
  SessionSynchronizer.get_instance().notify_ready()

  await get_tree().create_timer(2.0).timeout
  spawn_cars()

const spawn_ring_size := 3.0
const car_template: PackedScene = preload("res://games/carnage/kart/kart_bot.tscn")
func spawn_cars() -> void:
  var i := 0
  var spawn_center := spawn_center_node.global_position
  for peer in lobby.peers:
    var progress := float(i) / minf(2.0, lobby.peers.size())
    var pos_offset := Vector3(cos(progress * TAU), 0.0, sin(progress * TAU))
    var location := spawn_center + pos_offset * spawn_ring_size
    var kart_inst := car_template.instantiate() as KartBot

    add_child(kart_inst)
    kart_inst.kart_movement.owner_peer_id = peer.peer_id
    kart_inst.global_position = location
    kart_inst.look_at(Vector3.ZERO, Vector3.UP, true)

    i += 1

func start_game() -> void:
  pass
  
