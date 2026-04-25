@tool
extends Node3D
class_name MarblesSpinner

@onready var spinner1: MeshInstance3D = $MarbleSpinner
@onready var spinner2: MeshInstance3D = $MarbleSpinner2

var acc: float = 0
func _physics_process(delta: float) -> void:
  acc += delta * 90.0
  spinner1.rotation_degrees.y = acc
  spinner2.rotation_degrees.y = -acc
