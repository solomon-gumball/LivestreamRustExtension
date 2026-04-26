extends Node3D
class_name MarblesMap

@export var finish_area: Area3D
@export var out_of_bounds_area: Area3D
@export var spawn_path: Path3D

@onready var progress_curve: Path3D = $ProgressCurve
@onready var camera: DebugCamera = %DebugCamera
