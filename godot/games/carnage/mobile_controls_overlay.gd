class_name MobileControlsOverlay
extends CanvasLayer

static var _instance: MobileControlsOverlay = null

static func get_instance() -> MobileControlsOverlay:
  if _instance == null:
    assert(false, "MobileControlsOverlay instance not found! Make sure to add it to the scene tree.")
  return _instance

## Each entry pairs an action name with a button node path (relative to this node).
## Set these up in the scene inspector or via register_button() in code.
@export var bindings: Array[MobileButtonBinding] = []

var _held: Dictionary = {}
var _just_pressed: Dictionary = {}

func _init() -> void:
  _instance = self

func _ready() -> void:
  for binding in bindings:
    if binding.action_name == "" or binding.button_path.is_empty():
      continue
    var button := get_node_or_null(binding.button_path) as BaseButton
    if button:
      register_button(button, binding.action_name)
    else:
      push_warning("MobileControlsOverlay: could not find button at path '%s'" % binding.button_path)
  
  is_active = DisplayServer.is_touchscreen_available()

var is_active: bool = false:
  set(v):
    is_active = v
    visible = v

## Wire a button to an action at runtime (alternative to the inspector bindings array).
func register_button(button: BaseButton, action: String) -> void:
  _held[action] = false
  _just_pressed[action] = false
  button.button_down.connect(_on_button_down.bind(action))
  button.button_up.connect(_on_button_up.bind(action))

func _on_button_down(action: String) -> void:
  _held[action] = true
  _just_pressed[action] = true

func _on_button_up(action: String) -> void:
  _held[action] = false

func is_action_pressed(action: String) -> bool:
  return _held.get(action, false)

## True once per press; clears on read — matches Input.is_action_just_pressed semantics.
func is_action_just_pressed(action: String) -> bool:
  var v: bool = _just_pressed.get(action, false)
  if v:
    _just_pressed[action] = false
  return v

## Mirrors Input.get_vector — pass the four action names in the same order.
func get_vector(negative_x: String, positive_x: String, negative_y: String, positive_y: String) -> Vector2:
  var x := float(is_action_pressed(positive_x)) - float(is_action_pressed(negative_x))
  var y := float(is_action_pressed(positive_y)) - float(is_action_pressed(negative_y))
  var v := Vector2(x, y)
  return v.normalized() if v.length_squared() > 1.0 else v
