@tool
extends Node3D
class_name MarblesSpinner

@onready var spinner1: MeshInstance3D = $MarbleSpinner
@onready var spinner2: MeshInstance3D = $MarbleSpinner2

var game_started_at: float = 0.0
func _physics_process(_delta: float) -> void:
  var time_since_game_start = Time.get_unix_time_from_system() - game_started_at
  spinner1.rotation_degrees.y = time_since_game_start * 30.0
  spinner2.rotation_degrees.y = -time_since_game_start * 30.0
