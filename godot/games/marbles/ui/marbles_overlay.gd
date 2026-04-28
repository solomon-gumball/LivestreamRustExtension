extends CanvasLayer
class_name MarblesOverlay

@onready var focused_chatter_placement_label: RichTextLabel = %FocusedChatterPlacement
@onready var focused_chatter_name_label: RichTextLabel = %FocusedChatterNameLabel
@onready var leaderboard_list: VBoxContainer = $LeaderboardList
@onready var focused_chatter_header: Container = %FocusedChatterHeader
@onready var lower_place_button: Button = %LowerPlaceButton
@onready var higher_place_button: Button = %HigherPlaceButton

var bots_by_peer_id: Dictionary[int, MarbleBot] = {}
var map: MarblesMap
var num_of_entries_to_show = 10
var row_template = load("res://games/marbles/ui/marbles_leaderboard_row.tscn")

signal marble_selected(marble: MarbleBot)
signal placement_changed(index_delta: int)

func _ready() -> void:
  set_focused_bot(null)
  higher_place_button.pressed.connect(increment_focused_bot.bind(-1))
  lower_place_button.pressed.connect(increment_focused_bot.bind(1))

var _focused_bot: MarbleBot = null

func set_focused_bot(marble_bot: MarbleBot, placement: int = -1) -> void:
  if marble_bot == null or marble_bot.chatter == null:
    focused_chatter_header.visible = false
    return
  
  _focused_bot = marble_bot
  focused_chatter_header.visible = true
  focused_chatter_placement_label.text = placement_string(placement + 1)
  focused_chatter_name_label.text = marble_bot.chatter.display_name

func placement_string(placement: int) -> String:
  if placement == 1:
    return str(placement) + "st"
  elif placement == 2:
    return str(placement) + "nd"
  elif placement == 3:
    return str(placement) + "rd"
  else:
    return str(placement) + "th"

func increment_focused_bot(index_change: int) -> void:
  placement_changed.emit(index_change)

func refresh_leaderboard(placements: Array[MarbleBot]) -> void:
  var children = leaderboard_list.get_children()
  for child in children:
    if child is MarblesLeaderboardRow:
      child.queue_free()

  var marble_bots := placements.slice(0, num_of_entries_to_show)
  var rank: int = 0
  for marble in marble_bots:
    rank += 1
    var entry: MarblesLeaderboardRow = row_template.instantiate()
    if marble.chatter:
      entry.username = marble.chatter.display_name
      entry.rank = rank
      entry.pressed.connect(marble_selected.emit.bind(marble))
      leaderboard_list.add_child(entry)
  
  if _focused_bot:
    var placement := placements.find(_focused_bot)
    set_focused_bot(_focused_bot, placement)
