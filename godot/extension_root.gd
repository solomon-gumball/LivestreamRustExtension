extends Control
class_name ExtensionRoot

var current_chatter: Chatter

@export var active_page: Node
@onready var profile_button: Button = %ProfileButton
@onready var game_button: Button = %GameButton

var profile_page_template: PackedScene = preload("res://profile_page.tscn")
var game_page_template: PackedScene = preload("res://game_page.tscn")
enum ExtensionPage { Profile, Game }

func _ready() -> void:
  Network.chatter_updated.connect(_handle_chatter_updated)
  Network.store_data_received.connect(_store_data_received)
  profile_button.pressed.connect(_navigate_to_page.bind(ExtensionPage.Profile))
  game_button.pressed.connect(_navigate_to_page.bind(ExtensionPage.Game))
  _navigate_to_page(ExtensionPage.Game)

func _navigate_to_page(page: int) -> void:
  var new_page: Node
  match page:
    ExtensionPage.Profile:
      new_page = profile_page_template.instantiate()
    ExtensionPage.Game:
      new_page = game_page_template.instantiate()
    
  if active_page:
    remove_child(active_page)
    active_page.queue_free()

  active_page = new_page
  add_child(new_page)  

func _store_data_received() -> void:
  if DebugScreenLayout.window_index == 0:
    # Network.current_chatter_id = '22445910'
    Network.subscribe(['22445910', 'LOBBIES']) # solomongumbal1
  # elif DebugScreenLayout.window_index == 1:
  else:
    # Network.current_chatter_id = '1273990990'
    Network.subscribe(['1273990990', 'LOBBIES']) # solomongumbot

func _handle_chatter_updated(chatter: Chatter) -> void:
  current_chatter = chatter
  Network.current_chatter = chatter
