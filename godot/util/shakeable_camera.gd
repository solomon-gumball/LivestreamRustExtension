@tool
extends Camera3D
class_name ShakeableCamera

@export var trauma_reduction_rate := 1.0

@export var max_x := 3.0
@export var max_y := 3.0
@export var max_z := 3.0

@export var noise : FastNoiseLite = FastNoiseLite.new()
@export var noise_speed := 100.0

var trauma := 0.0
var time := 0.0
var initial_rotation: Vector3

@export var debug_trigger_trauma: bool = false:
  set(new_value):
    add_trauma(1.0)

func _ready() -> void:
  initial_rotation = rotation_degrees

func _physics_process(delta: float):
  time += delta
  trauma = max(trauma - delta * trauma_reduction_rate, 0.0)
  
  rotation_degrees.x = initial_rotation.x + max_x * get_shake_intensity() * get_noise_from_seed(0)
  rotation_degrees.y = initial_rotation.y + max_y * get_shake_intensity() * get_noise_from_seed(1)
  rotation_degrees.z = initial_rotation.z + max_z * get_shake_intensity() * get_noise_from_seed(2)

func add_trauma(trauma_amount : float):
  trauma = clamp(trauma + trauma_amount, 0.0, 1.0)

func get_shake_intensity() -> float:
  return trauma * trauma

func get_noise_from_seed(_seed : int) -> float:
  noise.seed = _seed
  return noise.get_noise_1d(time * noise_speed)
