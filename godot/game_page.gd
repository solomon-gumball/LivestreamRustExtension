class_name GamePage
extends Node3D

@export var gumbot: GumBot
@onready var lobby_name_label: Label = %LobbyNameLabel
@onready var client_id_label: Label = %ClientIdLabel
@onready var lobby_info_panel: Control = %LobbyInfoPanel
@onready var lobby_list_container: VBoxContainer = %LobbyListContainer
@onready var test_rpc_button: Button = %TestRPCButton
@onready var debug_rect: Control = %DebugRect

@onready var center_info_label: RichTextLabel = %CenterInfoLabel

var looking_for_lobby_tween: Tween

enum GameState { LookingForLobby, JoiningLobby, InGame }
var game_state: GameState:
  set(new_value):
    game_state = new_value

    match new_value:
      GameState.LookingForLobby:
        _start_looking_for_lobby_loop()


func _start_looking_for_lobby_loop() -> void:
  if looking_for_lobby_tween:
    looking_for_lobby_tween.kill()

  center_info_label.text = "[font_size=50]LOOKING FOR LOBBY...[/font_size]"
  center_info_label.visible_ratio = 0.0
  looking_for_lobby_tween = create_tween()
  looking_for_lobby_tween.tween_property(center_info_label, "visible_ratio", 1.0, 1.5)
  looking_for_lobby_tween.tween_interval(2.0)
  looking_for_lobby_tween.tween_callback(_start_looking_for_lobby_loop)

func _ready() -> void:
  center_info_label.visible = true
  lobby_info_panel.visible = false

  center_info_label.text = ""

  Network.chatter_updated.connect(_handle_chatter_updated)
  Network.multiplayer_client.lobby_joined.connect(_lobby_joined)

  test_rpc_button.pressed.connect(test_rpc.rpc)
  _handle_chatter_updated(Network.current_chatter)

  game_state = game_state

@rpc("any_peer", "call_local")
func test_rpc() -> void:
  debug_rect.visible = !debug_rect.visible

func _lobby_joined(_lobby: String) -> void:
  lobby_name_label.text = "Lobby: %s" % _lobby
  client_id_label.text = "Client ID: %d" % Network.multiplayer_client.rtc_mp.get_unique_id()
  lobby_info_panel.visible = true
  lobby_list_container.visible = false
  print("Joined lobby: %s" % _lobby)

  # Network.multiplayer_client.join_lobby(lobby_id)

func _handle_chatter_updated(chatter: Chatter) -> void:
  if chatter:
    gumbot.chatter = chatter
