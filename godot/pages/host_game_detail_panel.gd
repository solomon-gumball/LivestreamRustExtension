extends PanelContainer
class_name HostGameDetailPanel

@onready var game_name_label: RichTextLabel = %GameName
@onready var game_player_count_label: RichTextLabel = %GamePlayerCount
@onready var game_cost_label: RichTextLabel = %GameCostGumbucks
@onready var game_thumbnail: TextureRect = %GameThumbnail

var metadata: GameMetadata

signal on_selected(metadata: GameMetadata)

func _ready() -> void:
  if metadata:
    game_name_label.text = metadata.title
    game_player_count_label.text = str(metadata.min_players) + " Players"
    game_cost_label.text = str(metadata.cost) + " GUM"
    ImageLoader.load_image(
      WSClient.get_database_server_url(metadata.thumbnail_url),
      func (image: ImageTexture, _url: String) -> void:
        if image:
          game_thumbnail.texture = image
        else:
          print("no image found for ", _url)
    )
    gui_input.connect(_on_gui_input)

func _on_gui_input(event: InputEvent):
  if event is InputEventMouseButton:
    if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
      on_selected.emit(metadata)