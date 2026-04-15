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

var info_tween: Tween
var current_lobby: Lobby:
  set(new_val):
    current_lobby = new_val
    if current_lobby:
      print(current_lobby.peers, " PEERS")
    center_info_label.text = _get_joining_text()

const LOOKING_TEXT = "[font_size=50]LOOKING FOR LOBBY...[/font_size]"

func _stat_line(label: String, base_dots: int, value: int) -> String:
  var dots = ".".repeat(base_dots - len(str(value)) + 1)
  return "[font_size=50]%s%s%d[/font_size]" % [label, dots, value]

func _get_joining_text() -> String:
  var player_count = current_lobby.peers.size() if current_lobby else 0
  return "\n".join([
    "[font_size=50]JOINING[/font_size]",
    "[font_size=120]PONG[/font_size]",
    "[font_size=50]\nSTAKES....[color=green]100 gum[/color][/font_size]",
    _stat_line("PLAYERS", 9, player_count),
    _stat_line("SPECTATORS", 6, 4),
  ])

enum GameState { LookingForLobby, JoiningLobby, InGame }
var game_state: GameState:
  set(new_value):
    game_state = new_value

    match new_value:
      GameState.LookingForLobby:
        _type_text(LOOKING_TEXT, 0.1, true)
      GameState.JoiningLobby, GameState.InGame:
        _type_text(_get_joining_text(), 0.1, false)

func _type_text(text: String, speed: float, repeat: bool) -> void:
  if info_tween:
    info_tween.kill()

  center_info_label.text = text
  center_info_label.visible_ratio = 0.0
  var duration := center_info_label.get_total_character_count() * speed
  info_tween = create_tween()
  info_tween.tween_property(center_info_label, "visible_ratio", 1.0, duration)
  if repeat:
    info_tween.tween_interval(2.0)
    info_tween.tween_callback(func(): _type_text(text, speed, repeat))

func _ready() -> void:
  center_info_label.visible = true
  lobby_info_panel.visible = false

  center_info_label.text = ""

  Network.chatter_updated.connect(_handle_chatter_updated)
  Network.multiplayer_client.lobby_joined.connect(_lobby_joined)
  Network.lobbies_updated.connect(_lobbies_updated)
  Network.send_socket_message({ "type": "rtc-fetch-lobbies" })

  # test_rpc_button.pressed.connect(test_rpc.rpc)
  _handle_chatter_updated(Network.current_chatter)
  test_rpc_button.pressed.connect(_host_game)

  game_state = game_state

func _exit_tree() -> void:
  if current_lobby:
    Network.send_socket_message({
      "type": "rtc-leave-lobby",
      "lobby_id": current_lobby.name
    })

# @rpc("any_peer", "call_local")
# func test_rpc() -> void:
#   debug_rect.visible = !debug_rect.visible

func _host_game() -> void:
  Network.multiplayer_client.join_lobby("")

func _lobbies_updated(lobbies: Array[Lobby]) -> void:
  if Network.current_chatter == null: return
  var new_lobby = lobbies[0] if lobbies.size() > 0 else null

  match game_state:
    GameState.LookingForLobby:
      if new_lobby:
        Network.multiplayer_client.join_lobby(new_lobby.name)
        game_state = GameState.JoiningLobby
      
    GameState.JoiningLobby:
      if new_lobby and new_lobby.peers.has(Network.current_chatter.id):
        game_state = GameState.InGame

  if new_lobby:
    current_lobby = new_lobby

func _lobby_joined(_lobby: String) -> void:
  lobby_name_label.text = "Lobby: %s" % _lobby
  client_id_label.text = "Client ID: %d" % Network.multiplayer_client.rtc_mp.get_unique_id()
  lobby_info_panel.visible = true
  print("Joined lobby: %s" % _lobby)

func _handle_chatter_updated(chatter: Chatter) -> void:
  if chatter:
    gumbot.chatter = chatter
