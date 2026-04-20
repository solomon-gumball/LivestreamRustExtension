extends Control
class_name ExtensionRoot

var current_chatter: Chatter

@export var active_page: Node
@onready var profile_button: CustomButton = %ProfileButton
@onready var game_button: CustomButton = %GameButton
@onready var page_container: Control = %PageContainer
@onready var alert_layer: AlertLayer = %AlertLayer

var profile_page_template: PackedScene = preload("res://pages/profile_page.tscn")
var game_page_template: PackedScene = preload("res://pages/game_page.tscn")
enum ExtensionPage { Profile, Game }

func _ready() -> void:
  if DebugScreenLayout.window_index == 0:
    WSClient.debug_chatter_id = '22445910' # Gumball
  else:
    WSClient.debug_chatter_id = '1273990990' # GumBOT
  WSClient.state.changed.connect(_handle_connection_status_changed)
  _handle_connection_status_changed(WSClient.state.current)

  game_button.pressed.connect(_navigate_to_page.bind(ExtensionPage.Game))
  profile_button.pressed.connect(_navigate_to_page.bind(ExtensionPage.Profile))

  _navigate_to_page(ExtensionPage.Game)

func _handle_connection_status_changed(state: WSClient.WSClientState) -> void:
  if state is WSClient.DisconnectedState:
    alert_layer.display_alert("No connection found!\nReconnecting...")
  else:
    alert_layer.hide_alert()

func _navigate_to_page(page: int) -> void:
  var new_page: Node
  match page:
    ExtensionPage.Profile:
      profile_button.selected = true
      game_button.selected = false
      new_page = profile_page_template.instantiate()
    ExtensionPage.Game:
      profile_button.selected = false
      game_button.selected = true
      new_page = game_page_template.instantiate()
    
  if active_page:
    page_container.remove_child(active_page)
    active_page.queue_free()

  active_page = new_page
  page_container.add_child(new_page)
