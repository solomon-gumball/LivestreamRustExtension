extends CharacterBody3D
class_name DebugCamera

@export var move_speed: float = 10.0
@export var fast_move_speed: float = 50.0
@export var mouse_sensitivity: float = 0.003
@onready var camera: Camera3D = $Camera

var _yaw: float = 0.0
var _pitch: float = 0.0

func _ready() -> void:
  _init_input_actions()

func _input(event: InputEvent) -> void:
  print("Input event: ", event)
  if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
    print("Right mouse button pressed: ", event.pressed)
    if event.pressed:
      Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    else:
      Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

  if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
    _yaw -= event.relative.x * mouse_sensitivity
    _pitch -= event.relative.y * mouse_sensitivity
    _pitch = clamp(_pitch, deg_to_rad(-89.0), deg_to_rad(89.0))

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

func _init_input_actions() -> void:
  InputMap.add_action("move_forward")
  InputMap.add_action("move_back")
  InputMap.add_action("move_right")
  InputMap.add_action("move_left")

  # Add keyboard W key
  var move_forward_event := InputEventKey.new()
  move_forward_event.physical_keycode = KEY_W
  InputMap.action_add_event("move_forward", move_forward_event)

  # # Add joystick axis (left stick up is typically negative on axis 1)
  var joy_forward_event := InputEventJoypadMotion.new()
  joy_forward_event.axis = JOY_AXIS_LEFT_Y  # usually axis 1
  joy_forward_event.axis_value = -1.0       # forward is negative on Y axis
  InputMap.action_add_event("move_forward", joy_forward_event)

  var right_move_event := InputEventKey.new()
  right_move_event.physical_keycode = KEY_A
  InputMap.action_add_event("move_left", right_move_event)

  # Add joystick axis (left stick up is typically negative on axis 1)
  var joy_left_event := InputEventJoypadMotion.new()
  joy_left_event.axis = JOY_AXIS_LEFT_X  # usually axis 1
  joy_left_event.axis_value = -1.0       # forward is negative on Y axis
  InputMap.action_add_event("move_left", joy_left_event)

  var move_back_event := InputEventKey.new()
  move_back_event.physical_keycode = KEY_S
  InputMap.action_add_event("move_back", move_back_event)

  # Add joystick axis (left stick up is typically negative on axis 1)
  var joy_back_event := InputEventJoypadMotion.new()
  joy_back_event.axis = JOY_AXIS_LEFT_Y  # usually axis 1
  joy_back_event.axis_value = 1.0       # forward is negative on Y axis
  InputMap.action_add_event("move_back", joy_back_event)

  var move_right_event := InputEventKey.new()
  move_right_event.physical_keycode = KEY_D
  InputMap.action_add_event("move_right", move_right_event)

  # Add joystick axis (left stick up is typically negative on axis 1)
  var joy_right_event := InputEventJoypadMotion.new()
  joy_right_event.axis = JOY_AXIS_LEFT_X  # usually axis 1
  joy_right_event.axis_value = 1.0       # forward is negative on Y axis
  InputMap.action_add_event("move_right", joy_right_event)
