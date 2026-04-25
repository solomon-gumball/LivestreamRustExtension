@tool
extends Node3D
class_name MarblesFan

@export var fan_mesh: MeshInstance3D
@export var sequence_offset: float = 0.0

var speed = 3.0
var time: float = 0.0
func _process(delta: float) -> void:
  # var time = Time.get_unix_time_from_system()
  time += delta * speed
  fan_mesh.rotation.x = time + ((sequence_offset * 2.0 * PI) / speed)
  #   fan_mesh.rotation.x = time * speed + sequence_offset

    # var offset: float = sequence_offset * 2.0 * PI
  # pass
