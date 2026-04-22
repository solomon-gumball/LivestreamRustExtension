extends Control
class_name ExtensionRoot

var current_chatter: Chatter

@export var active_page: Node
@onready var profile_button: CustomButton = %ProfileButton
@onready var play_game_button: CustomButton = %PlayGameButton
@onready var host_game_button: CustomButton = %HostGameButton
@onready var page_container: Control = %PageContainer
@onready var alert_layer: AlertLayer = %AlertLayer

var profile_page_template: PackedScene = preload("res://pages/profile_page.tscn")
var game_page_template: PackedScene = preload("res://pages/game_page.tscn")
var host_game_page_template: PackedScene = preload("res://pages/host_game_page.tscn")

enum ExtensionPage { Profile, PlayGame, HostGame }

func _ready() -> void:
  WSClient.state.changed.connect(_handle_connection_status_changed)
  _handle_connection_status_changed(WSClient.state.current)

  play_game_button.pressed.connect(_navigate_to_page.bind(ExtensionPage.PlayGame))
  host_game_button.pressed.connect(_navigate_to_page.bind(ExtensionPage.HostGame))
  profile_button.pressed.connect(_navigate_to_page.bind(ExtensionPage.Profile))

  _navigate_to_page(ExtensionPage.PlayGame)

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
      play_game_button.selected = false
      host_game_button.selected = false
      new_page = profile_page_template.instantiate()
    ExtensionPage.PlayGame:
      profile_button.selected = false
      play_game_button.selected = true
      host_game_button.selected = false
      new_page = game_page_template.instantiate()
    ExtensionPage.HostGame:
      profile_button.selected = false
      play_game_button.selected = false
      host_game_button.selected = true
      new_page = host_game_page_template.instantiate()
    
  if active_page:
    page_container.remove_child(active_page)
    active_page.queue_free()

  active_page = new_page
  page_container.add_child(new_page)
