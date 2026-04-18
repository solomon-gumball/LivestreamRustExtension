extends Control
class_name ExtensionRoot

var current_chatter: Chatter

@export var active_page: Node
@onready var profile_button: Button = %ProfileButton
@onready var game_button: Button = %GameButton
@onready var page_container: Control = %PageContainer
@onready var alert_layer: AlertLayer = %AlertLayer

var profile_page_template: PackedScene = preload("res://pages/profile_page.tscn")
var game_page_template: PackedScene = preload("res://pages/game_page.tscn")
enum ExtensionPage { Profile, Game }

func _ready() -> void:
  if DebugScreenLayout.window_index == 0:
    Network.debug_chatter_id = '22445910' # Gumball
  else:
    Network.debug_chatter_id = '1273990990' # GumBOT
  Network.connection_state.changed.connect(_handle_connection_status_changed)
  _handle_connection_status_changed(Network.connection_state.current)

  game_button.pressed.connect(_navigate_to_page.bind(ExtensionPage.Game))
  profile_button.pressed.connect(_navigate_to_page.bind(ExtensionPage.Profile))

  _navigate_to_page(ExtensionPage.Game)

func _handle_connection_status_changed(state: Network.NetworkConnectionState) -> void:
  if state is Network.DisconnectedState:
    alert_layer.display_alert("No connection found!\nReconnecting...")
  else:
    alert_layer.hide_alert()

func _navigate_to_page(page: int) -> void:
  var new_page: Node
  match page:
    ExtensionPage.Profile:
      new_page = profile_page_template.instantiate()
    ExtensionPage.Game:
      new_page = game_page_template.instantiate()
    
  if active_page:
    page_container.remove_child(active_page)
    active_page.queue_free()

  active_page = new_page
  page_container.add_child(new_page)
