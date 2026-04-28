extends Node3D
class_name MarblesMap

@export var finish_area: Area3D
@export var out_of_bounds_area: Area3D
@export var spawn_path: Path3D
@export var animation_player: AnimationPlayer

@onready var progress_curve: Path3D = $ProgressCurve
@onready var camera: DebugCamera = %DebugCamera

signal username_visibility_toggled(new_visibility: bool)
var all_props: Array[Node] = []

func _ready() -> void:
  all_props = get_tree().get_nodes_in_group("marbles_prop")

func toggle_username_visibility(new_visibility: bool) -> void:
  username_visibility_toggled.emit(new_visibility)