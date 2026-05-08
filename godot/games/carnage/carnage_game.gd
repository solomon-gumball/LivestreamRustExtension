@tool
extends GameBase
class_name Carnage

func _ready() -> void:
  super._ready()
  SessionSynchronizer.get_instance().notify_ready()
  spawn_cars()

const spawn_ring_size := 3.0
const car_template: PackedScene = preload("res://games/carnage/kart/kart_bot.tscn")
func spawn_cars() -> void:
  var i := 0
  var spawn_center := Vector3.ZERO
  for peer in lobby.peers:
    var progress := float(i) / minf(2.0, lobby.peers.size())
    var pos_offset := Vector3(cos(progress * TAU), 0.0, sin(progress * TAU))
    var location := spawn_center + pos_offset * spawn_ring_size
    var kart_inst := car_template.instantiate() as KartBot
    add_child(kart_inst)
    kart_inst.global_position = location

func start_game() -> void:
  pass
  
