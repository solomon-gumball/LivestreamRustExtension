extends Button
class_name MarblesLeaderboardRow

@export var rank: int = 0:
  set(value):
    rank = value
    _update_text()

@export var username: String = "":
  set(value):
    username = value
    _update_text()

var focused: bool = false:
  set(value):
    focused = value
    if focused:
      modulate = Color(0.0, 1.0, 0.5)
    else:
      modulate = Color(1, 1, 1)

var marble_bot: MarbleBot = null

func _ready() -> void:
  _update_text()

func _update_text() -> void:
  if is_node_ready():
    text = str(rank) + ' - ' + username
