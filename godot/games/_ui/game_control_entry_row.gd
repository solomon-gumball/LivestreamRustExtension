@tool
class_name GameControlEntryRow
extends HBoxContainer

var entry: GameControlsEntry

@onready var description_label: Label = %DescriptionLabel
@onready var control_icon: TextureRect = %ControlIcon

func _ready() -> void:
  description_label.text = entry.description
  control_icon.texture = entry.icon