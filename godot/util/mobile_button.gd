@tool
class_name MobileButton
extends BaseButton

@export var text: String = "":
  set(v):
    text = v
    if _label:
      _label.text = v

@export var background_color: Color = Color(0.2, 0.2, 0.2, 0.8):
  set(v):
    background_color = v
    queue_redraw()

@export var border_color: Color = Color.WHITE:
  set(v):
    border_color = v
    queue_redraw()

@export var border_width: int = 2:
  set(v):
    border_width = v
    queue_redraw()

var _touch_ids: Array[int] = []
var _label: Label = null

func _ready() -> void:
  # Disable GUI routing so BaseButton's internal handler never fires.
  # We drive button_down / button_up entirely from raw screen touch events.
  mouse_filter = Control.MOUSE_FILTER_IGNORE

  _label = Label.new()
  _label.text = text
  _label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  _label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  _label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
  _label.mouse_filter = Control.MOUSE_FILTER_IGNORE
  add_child(_label)

func _draw() -> void:
  draw_rect(Rect2(Vector2.ZERO, size), background_color)
  if border_width > 0:
    var inset := border_width / 2.0
    draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset * 2, inset * 2)), border_color, false, border_width)

func _input(event: InputEvent) -> void:
  if not is_visible_in_tree():
    return

  if event is InputEventScreenTouch:
    var touch: InputEventScreenTouch = event
    if touch.pressed:
      if get_global_rect().has_point(touch.position) and touch.index not in _touch_ids:
        _touch_ids.append(touch.index)
        if _touch_ids.size() == 1:
          set_pressed_no_signal(true)
          button_down.emit()
        get_viewport().set_input_as_handled()
    else:
      if touch.index in _touch_ids:
        _touch_ids.erase(touch.index)
        if _touch_ids.is_empty():
          set_pressed_no_signal(false)
          button_up.emit()
        get_viewport().set_input_as_handled()

  elif event is InputEventScreenDrag:
    var drag: InputEventScreenDrag = event
    if drag.index in _touch_ids and not get_global_rect().has_point(drag.position):
      _touch_ids.erase(drag.index)
      if _touch_ids.is_empty():
        set_pressed_no_signal(false)
        button_up.emit()
