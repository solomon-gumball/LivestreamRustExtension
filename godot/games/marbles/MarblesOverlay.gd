extends CanvasLayer
class_name MarblesOverlay

@onready var leaderboard_list: VBoxContainer = $LeaderboardList
var spawned_bots: Dictionary[String, MarbleBot] = {}

func _ready() -> void:
  var update_timer = Timer.new()
  add_child(update_timer)
  update_timer.wait_time = 2.0
  update_timer.one_shot = false
  update_timer.start()
  update_timer.timeout.connect(refresh_leaderboard)

var num_of_entries_to_show = 10
var row_template = load("res://games/marbles/MarblesLeaderboardRow.tscn")
func refresh_leaderboard() -> void:
  var children = leaderboard_list.get_children()
  for child in children:
    if child is MarblesLeaderboardRow:
      child.queue_free()
  # print("Refreshing lea")

  var bots: Array[MarbleBot] = []
  bots.assign(spawned_bots.values())

  bots.sort_custom(func(a: MarbleBot, b: MarbleBot) -> bool: return a.position.y < b.position.y)
  bots = bots.slice(0, num_of_entries_to_show)
  var rank: int = 0
  for bot in bots:
    rank += 1
    var entry: MarblesLeaderboardRow = row_template.instantiate()
    entry.username = bot.chatter.display_name
    entry.rank = rank
    leaderboard_list.add_child(entry)
