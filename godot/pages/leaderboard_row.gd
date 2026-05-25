@tool
extends MarginContainer
class_name LeaderboardRow

@export var background_color: Color = Color(0.2, 0.2, 0.8, 1.0)
@export var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.5)
@export var shadow_offset: Vector2 = Vector2(6.0, 6.0)
@export var max_rotation_degrees: float = 0.5

@onready var left_label: RichTextLabel = %LeftLabel
@onready var right_label: RichTextLabel = %RightLabel

var chatter: Chatter:
  set(new_chatter):
    chatter = new_chatter

var _rotation_rad: float = 0.0

func _ready() -> void:
  _rotation_rad = deg_to_rad(randf_range(-max_rotation_degrees, max_rotation_degrees))
  queue_redraw()

func _draw() -> void:
  var rect := Rect2(Vector2.ZERO, size)
  var center := rect.get_center()
  var half := rect.size / 2.0
  var corners := [
    Vector2(-half.x, -half.y),
    Vector2( half.x, -half.y),
    Vector2( half.x,  half.y),
    Vector2(-half.x,  half.y),
  ]
  var cos_r := cos(_rotation_rad)
  var sin_r := sin(_rotation_rad)
  var rotated: PackedVector2Array = []
  for c in corners:
    rotated.append(center + Vector2(c.x * cos_r - c.y * sin_r, c.x * sin_r + c.y * cos_r))
  var shadow: PackedVector2Array = []
  for v in rotated:
    shadow.append(v + shadow_offset)
  draw_colored_polygon(shadow, shadow_color)
  var shadow_closed := shadow
  shadow_closed.append(shadow[0])
  draw_polyline(shadow_closed, shadow_color, 1.0, true)
  draw_colored_polygon(rotated, background_color)
  var closed := rotated
  closed.append(rotated[0])
  draw_polyline(closed, background_color, 1.0, true)
