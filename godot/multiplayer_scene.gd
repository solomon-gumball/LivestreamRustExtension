extends Node3D

@export var gumbot: GumBot
@onready var lobby_name_label: Label = %LobbyNameLabel
@onready var client_id_label: Label = %ClientIdLabel
@onready var lobby_info_panel: Control = %LobbyInfoPanel
@onready var lobby_id_input: LineEdit = %LobbyIdInput
@onready var join_game_button: Button = %JoinGameButton
@onready var lobby_list_container: VBoxContainer = %LobbyListContainer
@onready var test_rpc_button: Button = %TestRPCButton
@onready var debug_rect: Control = %DebugRect

func _ready() -> void:
  lobby_info_panel.visible = false
  Network.chatter_updated.connect(_handle_chatter_updated)
  Network.multiplayer_client.lobby_joined.connect(_lobby_joined)
  Network.store_data_received.connect(_store_data_received)

  test_rpc_button.pressed.connect(test_rpc.rpc)

@rpc("any_peer", "call_local")
func test_rpc() -> void:
  debug_rect.visible = !debug_rect.visible

func _store_data_received() -> void:
  if DebugScreenLayout.window_index == 0:
    Network.subscribe(['SIMULATION', '22445910']) # solomongumbal1
  # elif DebugScreenLayout.window_index == 1:
  else:
    Network.subscribe(['SIMULATION', '1273990990']) # solomongumbot

func _lobby_joined(_lobby: String) -> void:
  lobby_name_label.text = "Lobby: %s" % _lobby
  client_id_label.text = "Client ID: %d" % Network.multiplayer_client.rtc_mp.get_unique_id()
  lobby_info_panel.visible = true
  lobby_list_container.visible = false
  print("Joined lobby: %s" % _lobby)

func _join_game_button_pressed() -> void:
  var lobby_id = lobby_id_input.text.strip_edges()
  Network.multiplayer_client.join_lobby(lobby_id)

func _handle_chatter_updated(chatter: Chatter) -> void:
  gumbot.chatter = chatter
  join_game_button.pressed.connect(_join_game_button_pressed)
