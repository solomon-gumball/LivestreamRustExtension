extends PanelContainer
class_name MarblesLeaderboardRow

@export var rank: int = 0
@export var username: String = ""

@onready var placement_label: Label = $MarginContainer/HBoxContainer/PlacementLabel
@onready var username_label: Label = $MarginContainer/HBoxContainer/UsernameLabel

func _ready() -> void:
  placement_label.text = str(rank)
  username_label.text = username