extends Control
class_name ExtensionRoot

var current_chatter: Chatter

@export var active_page: Node
@onready var page_container: Control = %PageContainer
@onready var start_menu: StartMenu = %StartMenu

var profile_page_template: PackedScene = preload("res://pages/profile_page.tscn")
var game_page_template: PackedScene = preload("res://pages/game_page.tscn")
var host_game_page_template: PackedScene = preload("res://pages/host_game_page.tscn")
var leaderboard_page_template: PackedScene = preload("res://pages/leaderboard_page.tscn")
var shop_page_template: PackedScene = preload("res://pages/shop_page.tscn")

func _ready() -> void:
  start_menu_visible = false

  WSClient.state.changed.connect(_handle_connection_status_changed)
  start_menu.trigger_navigate.connect(_navigate_to_page)
  _handle_connection_status_changed(WSClient.state.current)
  _navigate_to_page(StartMenu.ExtensionPage.Profile)

func _handle_connection_status_changed(state: WSClient.WSClientState) -> void:
  if state is WSClient.DisconnectedState:
    AlertLayer.display_alert("No connection found!\nReconnecting...")
  else:
    AlertLayer.hide_alert()
  
func _navigate_to_page(page: int) -> void:
  if active_page:
    active_page.queue_free()
  
  start_menu_visible = false
  match page:
    StartMenu.ExtensionPage.Learderboard:
      active_page = leaderboard_page_template.instantiate()
    StartMenu.ExtensionPage.Profile:
      active_page = profile_page_template.instantiate()
    StartMenu.ExtensionPage.Multiplayer:
      active_page = game_page_template.instantiate()
    StartMenu.ExtensionPage.Shop:
      active_page = shop_page_template.instantiate()
    StartMenu.ExtensionPage.Moderator:
      var host_game_scene: HostGamePage = host_game_page_template.instantiate()
      active_page = host_game_scene
      active_page.on_lobby_created.connect(_navigate_to_page.bind(StartMenu.ExtensionPage.Multiplayer))

  page_container.add_child(active_page)

var start_menu_visible: bool = false:
  set(new_value):
    start_menu_visible = new_value
    start_menu.visible = start_menu_visible

func _input(event: InputEvent) -> void:
  if Input.is_action_just_pressed("StartMenu"):
    start_menu_visible = !start_menu_visible