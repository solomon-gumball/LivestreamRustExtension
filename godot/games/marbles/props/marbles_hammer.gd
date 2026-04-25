@tool
extends Node3D

@onready var hammer_mesh: MeshInstance3D = $Hammer
@export var sequence_offset: float = 0.0

func _ready() -> void:
  pass

var speed = 1.0
func _process(delta: float) -> void:
  var time = Time.get_unix_time_from_system()

  if hammer_mesh != null:
    var offset: float = sequence_offset * 2.0 * PI
    hammer_mesh.rotation.x = sin(time * 2.0 + offset) * 0.5 * PI
  pass