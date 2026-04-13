@tool
extends Control
class_name ScreenSquare

signal on_selected(value: String)

@onready var tex_rect: TextureRect = %TextureRect
@onready var icon: TextureRect = %Icon
@onready var border: TextureRect = %Border
@onready var container: Button = %Container
@onready var anim_player: AnimationPlayer = %AnimationPlayer

@export var value: String = ""

@export var show_border: bool = false:
  set(v): show_border = v; _update_layout()

@export var icon_size: float = 80.0:
  set(v): icon_size = v; _update_layout()

@export var icon_texture: Texture2D = preload("res://ui/Headgear_icon.svg"):
  set(v): icon_texture = v; _update_layout()

@export var width: float = 80.0:
  set(v): width = v; _update_layout()

@export var padding: float = -5.0:
  set(v): padding = v; _update_layout()

@export_range(-360.0, 360.0, 2.0) var angle = 0.0:
  set(v): angle = v; _update_layout()

@export_range(-360, 360.0, 2.0) var icon_angle = 0.0:
  set(v): icon_angle = v; _update_layout()

@export_range(-20.0, 20.0, 1.0) var y_offset = 0.0:
  set(v): y_offset = v; _update_layout()

@export var background_color: Color = Color.WHITE:
  set(v): background_color = v; _update_layout()

@export var border_color: Color = Color.BLACK:
  set(v): border_color = v; _update_layout()

@export var icon_color: Color = Color.BLACK:
  set(v): icon_color = v; _update_layout()

func _ready() -> void:
  _update_layout()
  tex_rect.mouse_entered.connect(_handle_hover.bind(true))
  tex_rect.mouse_exited.connect(_handle_hover.bind(false))
  container.pressed.connect(func (): on_selected.emit(value))

var container_scale_tween : Tween
func _handle_hover(hover: bool) -> void:
  if container_scale_tween:
    container_scale_tween.kill()
  container_scale_tween = get_tree().create_tween()
  var target_scale := 1.2 if hover else 1.0
  var duration := 0.3 if hover else 0.05
  container_scale_tween\
    .tween_property(container, 'scale', Vector2(target_scale, target_scale), duration)\
    .set_ease(Tween.EASE_OUT if hover else Tween.EASE_IN)\
    .set_trans(Tween.TRANS_ELASTIC if hover else Tween.TRANS_QUAD)

func _update_layout() -> void:
  if not is_node_ready(): return

  border.visible = show_border

  tex_rect.custom_minimum_size = Vector2(width, width)
  tex_rect.size = Vector2.ZERO
  tex_rect.position = Vector2.ZERO

  var icon_vec := Vector2(icon_size, icon_size)
  icon.texture = icon_texture
  icon.custom_minimum_size = icon_vec
  icon.size = Vector2.ZERO
  icon.position = (tex_rect.size - icon_vec) / 2.0
  icon.pivot_offset = icon.size / 2.0
  icon.rotation_degrees = 5.0
  icon.self_modulate = icon_color

  border.custom_minimum_size = Vector2(width, width)
  border.size = Vector2.ZERO
  border.position = Vector2.ZERO

  container.position = Vector2(0.0, y_offset)
  container.pivot_offset = tex_rect.size / 2.0
  container.rotation_degrees = angle
  container.custom_minimum_size = tex_rect.size
  container.size = Vector2.ZERO

  custom_minimum_size = Vector2(width + padding, width + padding)
  size = Vector2.ZERO

  tex_rect.self_modulate = background_color
  border.self_modulate = border_color
