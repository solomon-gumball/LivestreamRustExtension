extends Button
class_name MarblesLeaderboardRow

@export var rank: int = 0
@export var username: String = ""

func _ready() -> void:
  text = str(rank) + ' - ' + username