extends PanelContainer
class_name HostGameDetailPanel

@onready var game_name_label: RichTextLabel = %GameName
@onready var game_player_count_label: RichTextLabel = %GamePlayerCount
@onready var game_cost_label: RichTextLabel = %GameCostGumbucks
@onready var game_thumbnail: TextureRect = %GameThumbnail
@onready var http_request: HTTPRequest = %HTTPRequest

var metadata: GameMetadata

signal on_selected(metadata: GameMetadata)

func _ready() -> void:
  if metadata:
    game_name_label.text = metadata.title
    game_player_count_label.text = str(metadata.min_players) + " Players"
    game_cost_label.text = str(metadata.cost) + " GUM"
    # http_request.request(WSClient.get_database_server_url(metadata.thumbnail_url), [], HTTPClient.METHOD_GET)
    # http_request.request_completed.connect(_on_thumbnail_loaded)
    gui_input.connect(_on_gui_input)

# func _on_thumbnail_loaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
  # if result == OK and response_code == 200:
  #   var image = Image.new()
  #   var err = image.load_png_from_buffer(body)
  #   if err == OK:
  #     var texture = ImageTexture.new()
  #     texture.create_from_image(image)
  #     game_thumbnail.texture = texture

func _on_gui_input(event: InputEvent):
  if event is InputEventMouseButton:
    if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
      on_selected.emit(metadata)