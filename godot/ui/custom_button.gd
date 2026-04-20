extends Button
class_name CustomButton

var selected := false:
  set(new_value):
    selected = new_value
    self_modulate = selected_color if selected else default_color

var selected_color: Color = Color.WHITE
var default_color: Color = Color(1.0, 1.0, 1.0, 0.6)

