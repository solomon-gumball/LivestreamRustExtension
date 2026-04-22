@tool
extends Button
class_name CustomButton

@export var selected := false:
  set(new_value):
    selected = new_value
    self_modulate = selected_color if selected else default_color
    if selected_theme:
      theme = selected_theme if selected else default_theme

func _ready() -> void:
  selected = selected

@export var selected_color: Color = Color.WHITE
@export var default_color: Color = Color(1.0, 1.0, 1.0, 0.6)
@export var selected_theme: Theme = null
@export var default_theme: Theme = null
