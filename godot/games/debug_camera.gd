extends CharacterBody3D
class_name DebugCamera

@export var move_speed: float = 10.0
@export var fast_move_speed: float = 50.0
@export var mouse_sensitivity: float = 0.003
@onready var camera: Camera3D = $Camera

var _yaw: float = 0.0
var _pitch: float = 0.0

func _ready() -> void:
  Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
  if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
    _yaw -= event.relative.x * mouse_sensitivity
    _pitch -= event.relative.y * mouse_sensitivity
    _pitch = clamp(_pitch, deg_to_rad(-89.0), deg_to_rad(89.0))

  if event.is_action_pressed("toggle_cursor"):
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE \
      if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
      else Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
  global_basis = Basis(Quaternion(Vector3.UP, _yaw) * Quaternion(Vector3.RIGHT, _pitch))

  var speed := 100.0
  var direction := Vector3.ZERO
  direction -= global_basis.z * float(Input.is_action_pressed("move_forward"))
  direction += global_basis.z * float(Input.is_action_pressed("move_back"))
  direction -= global_basis.x * float(Input.is_action_pressed("move_left"))
  direction += global_basis.x * float(Input.is_action_pressed("move_right"))
  direction += Vector3.UP * float(Input.is_key_pressed(KEY_E))
  direction -= Vector3.UP * float(Input.is_key_pressed(KEY_Q))

  if direction.length_squared() > 0.001:
    direction = direction.normalized()
    var acceleration := direction * speed * delta
    velocity += acceleration
  else:
    velocity = velocity.move_toward(Vector3.ZERO, 100.0 * delta)
  
  velocity = velocity.limit_length(20.0)
  move_and_slide()
