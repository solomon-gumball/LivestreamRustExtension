@tool
class_name GameControls
extends Control

@onready var controls_list: Control = %ControlsList
@export var controls: Array[GameControlsEntry]:
  set(new_value):
    controls = new_value

var row_template: PackedScene = preload("res://games/_ui/game_control_entry_row.tscn")
func render_controls() -> void:
  if !is_inside_tree(): return

  for child in controls_list.get_children():
    child.queue_free()
    controls_list.remove_child(child)
  
  for entry in controls:
    if entry:
      var row: GameControlEntryRow = row_template.instantiate()
      row.entry = entry
      controls_list.add_child(row)

func _ready() -> void:
  render_controls()