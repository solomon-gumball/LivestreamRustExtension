@tool
class_name Loading
extends Control

@export var transition_material: ShaderMaterial
@export_range(0.0, 1.0) var progress: float = 0.0:
  set(value):
    progress = value
    transition_material.set_shader_parameter("progress", progress)

func transition_in() -> void:
  progress = 0.0
  visible = true
  transition_material.set_shader_parameter("reverse", false)
  var tween := get_tree().create_tween().tween_property(self, "progress", 1.0, 1.0)
  await tween.finished

func transition_out() -> void:
  transition_material.set_shader_parameter("reverse", true)
  var tween := get_tree().create_tween().tween_property(self, "progress", 0.0, 1.0)
  await tween.finished
  visible = false