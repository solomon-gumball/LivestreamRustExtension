extends CanvasLayer
class_name MarblesOverlay

@onready var focused_chatter_placement_label: RichTextLabel = %FocusedChatterPlacement
@onready var focused_chatter_name_label: RichTextLabel = %FocusedChatterNameLabel
@onready var leaderboard_list: VBoxContainer = %LeaderboardList
@onready var focused_chatter_header: Container = %FocusedChatterHeader
@onready var lower_place_button: Button = %LowerPlaceButton
@onready var higher_place_button: Button = %HigherPlaceButton
@onready var page_container: Control = %PageContainer

var bots_by_peer_id: Dictionary[int, MarbleBot] = {}
var map: MarblesMap
const NUM_OF_PLACEMENTS_TO_SHOW = 10
var row_template = load("res://games/marbles/ui/marbles_leaderboard_row.tscn")
var _leaderboard_rows: Array[MarblesLeaderboardRow] = []
var _last_placements: Array[MarbleBot] = []
var hidden: bool = false:
  set(new_hidden):
    if !new_hidden and hidden:
      print("animating in", new_hidden, hidden)
      page_container.modulate.a = 0.0
      var tween := create_tween()
      tween.tween_property(page_container, "modulate:a", 1.0, 1.0)
    hidden = new_hidden

signal marble_selected(marble: MarbleBot)
signal placement_changed(index_delta: int)

func _ready() -> void:
  set_focused_bot(null)
  higher_place_button.pressed.connect(increment_focused_bot.bind(-1))
  lower_place_button.pressed.connect(increment_focused_bot.bind(1))

  for child in leaderboard_list.get_children():
    child.queue_free()
  for i in NUM_OF_PLACEMENTS_TO_SHOW:
    var row: MarblesLeaderboardRow = row_template.instantiate()
    row.visible = false
    leaderboard_list.add_child(row)
    _leaderboard_rows.append(row)

var _focused_bot: MarbleBot = null

func set_focused_bot(marble_bot: MarbleBot, placement: int = -1) -> void:
  if marble_bot == null or marble_bot.chatter == null:
    focused_chatter_header.visible = false
    return

  _focused_bot = marble_bot
  focused_chatter_header.visible = true
  focused_chatter_placement_label.text = placement_string(placement + 1)
  focused_chatter_name_label.text = marble_bot.chatter.display_name
  if _last_placements:
    refresh_leaderboard(_last_placements)

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
  _last_placements = placements
  var marble_bots := placements.slice(0, NUM_OF_PLACEMENTS_TO_SHOW)

  for i in NUM_OF_PLACEMENTS_TO_SHOW:
    var row := _leaderboard_rows[i]
    if i < marble_bots.size() and marble_bots[i].chatter:
      var marble: MarbleBot = marble_bots[i]
      row.rank = i + 1
      row.username = marble.chatter.display_name
      row.focused = marble == _focused_bot
      for conn in row.pressed.get_connections():
        row.pressed.disconnect(conn["callable"])
      row.pressed.connect(marble_selected.emit.bind(marble))
      row.visible = true
    else:
      row.focused = false
      row.visible = false
