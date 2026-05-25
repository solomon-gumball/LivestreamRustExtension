class_name LeaderboardPage
extends Control

@onready var leaderboard_list: VBoxContainer = %LeaderboardList
@onready var most_gumbucks_btn: Button = %GumbucksListButton
@onready var most_game_wins_btn: Button = %GameWinsListButton

const LEADERBOARD_ROW = preload("res://pages/leaderboard_row.tscn")
const POLL_INTERVAL := 10.0

enum LeaderboardType {
  MostGumbucks,
  MostGameWins
}

var _current_tab: LeaderboardType:
  set(new_tab):
    _current_tab = new_tab
    most_gumbucks_btn.selected = _current_tab == LeaderboardType.MostGumbucks
    most_game_wins_btn.selected = _current_tab == LeaderboardType.MostGameWins
    _poll_timer = 0.0
    if _current_tab == LeaderboardType.MostGumbucks:
      _fetch_leaderboard()
    else:
      _clear_rows()

var _poll_timer := 0.0

func _ready() -> void:
  most_gumbucks_btn.pressed.connect(func(): _current_tab = LeaderboardType.MostGumbucks)
  most_game_wins_btn.pressed.connect(func(): _current_tab = LeaderboardType.MostGameWins)
  _current_tab = LeaderboardType.MostGumbucks

func _process(delta: float) -> void:
  _poll_timer += delta
  if _poll_timer >= POLL_INTERVAL:
    _poll_timer = 0.0
    if _current_tab == LeaderboardType.MostGumbucks:
      _fetch_leaderboard()

func _fetch_leaderboard() -> void:
  var request := AwaitableHTTPRequest.new()
  add_child(request)
  var response := await request.async_request(WSClient.get_database_server_url("leaderboard"))
  request.queue_free()

  if not response.success() or not response.status_ok():
    return

  var chatters := response.body_as_json() as Array
  _populate_rows(chatters)

func _clear_rows() -> void:
  for child in leaderboard_list.get_children():
    child.queue_free()

func _populate_rows(chatters: Array) -> void:
  _clear_rows()
  for i in chatters.size():
    var data: Dictionary = chatters[i]
    var row: LeaderboardRow = LEADERBOARD_ROW.instantiate()
    leaderboard_list.add_child(row)
    row.background_color = Color("#5e81f6")
    row.max_rotation_degrees = 0
    var chatter := Chatter.FromData(data)
    row.left_label.text = "%d %s" % [i + 1, chatter.display_name]
    row.right_label.text = "%s GUM" % _format_number(chatter.balance)

func _format_number(n: int) -> String:
  var s := str(n)
  var result := ""
  var count := 0
  for i in range(s.length() - 1, -1, -1):
    if count > 0 and count % 3 == 0:
      result = "," + result
    result = s[i] + result
    count += 1
  return result
