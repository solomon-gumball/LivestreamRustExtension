extends Control
class_name HostGamePage

@onready var game_grid: GridContainer = %GameGrid 

var game_detail_template: PackedScene = preload("res://pages/host_game_detail_panel.tscn")

func _ready() -> void:
  _load_games()

func _on_game_selected(_metadata: GameMetadata) -> void:
  MultiplayerClient.join_lobby("")

func _load_games() -> void:
  for child in game_grid.get_children():
    child.queue_free()

  var request = AwaitableHTTPRequest.new()
  add_child(request)
  var response := await request.async_request(WSClient.get_database_server_url("games"))
  request.queue_free()

  if response.success() and response.status_ok():
    var games := response.body_as_json() as Array
    for game in games:
      var metadata := GameMetadata.FromData(game)
      var game_detail_panel := game_detail_template.instantiate() as HostGameDetailPanel
      game_detail_panel.metadata = metadata
      game_grid.add_child(game_detail_panel)
      game_detail_panel.on_selected.connect(_on_game_selected)
  else:
    print(response._error)