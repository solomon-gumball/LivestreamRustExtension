class_name GamePage
extends Control

@onready var gumbot: GumBot = %GumBot
@onready var lobby_name_label: Label = %LobbyNameLabel
@onready var client_id_label: Label = %ClientIdLabel
@onready var lobby_info_panel: Control = %LobbyInfoPanel

@onready var center_info_label: RichTextLabel = %CenterInfoLabel

@onready var start_game_button: Button = %StartGameButton
@onready var close_lobby_button: Button = %CloseLobbyButton
@onready var host_game_button: Button = %HostGameButton
@onready var game_root_node: Node3D = %GameRootNode
@onready var ping_label: Label = %PingLabel
@onready var game_subviewport_container: SubViewportContainer = %GameSubviewportContainer
@onready var bot_initial_pos := gumbot.position
@onready var overlay_subviewport_container: SubViewportContainer = %OverlaySubviewportContainer
  
var info_tween: Tween

const LOOKING_TEXT = "[font_size=50]LOOKING FOR LOBBY...[/font_size]"

func _stat_line(label: String, base_dots: int, value: int) -> String:
  var dots = ".".repeat(base_dots - len(str(value)) + 1)
  return "[font_size=50]%s%s%d[/font_size]" % [label, dots, value]

func _get_joining_text(lobby: Lobby) -> String:
  var player_count = lobby.peers.size() if lobby else 0
  return "\n".join([
    "[font_size=50]JOINING[/font_size]",
    "[font_size=120]PONG[/font_size]",
    "[font_size=50]\nSTAKES....[color=green]100 gum[/color][/font_size]",
    _stat_line("PLAYERS", 9, player_count),
    _stat_line("SPECTATORS", 6, 4),
  ])

var pong_game_template: PackedScene = preload("res://games/pong/pong_game.tscn")
var game_scene: PongGame = null

func _ready() -> void:
  start_game_button.visible = false
  close_lobby_button.visible = false
  host_game_button.visible = false
  center_info_label.visible = true
  lobby_info_panel.visible = false
  center_info_label.text = ""

  WSClient.authenticated_state.chatter_updated.connect(_handle_chatter_updated)
  WSClient.state.changed.connect(_handle_ws_state_changed)

  MultiplayerClient.state.changed.connect(
    func (_connection_state: MultiplayerClient.MultiplayerClientState) -> void: _update()
  )
  MultiplayerClient.current_lobby_updated.connect(
    func (_lobby: Lobby) -> void: _update()
  )
  MultiplayerClient.connected_state.ping_check_completed.connect(_update_ping_label)

  host_game_button.pressed.connect(_host_game)
  close_lobby_button.pressed.connect(_close_lobby)
  start_game_button.pressed.connect(_start_game)

  _handle_ws_state_changed(WSClient.state.current)
  _handle_chatter_updated(WSClient.my_chatter())
  _update()
  
func _update_ping_label(msec_ping: float) -> void:
  ping_label.text = "PING: %sms" % int(msec_ping)

func _exit_tree() -> void:
  if MultiplayerClient.state.current is not MultiplayerClient.Connected:
    return

  if MultiplayerClient.is_lobby_host():
    MultiplayerClient.leave_lobby()
  MultiplayerClient.stop()

func _close_lobby() -> void:
  MultiplayerClient.leave_lobby()

func _start_game() -> void:
  if MultiplayerClient.current_lobby:
    WSClient.send_socket_message({
      "type": "rtc-start-game",
      "lobby_id": MultiplayerClient.current_lobby.name
    })

func _host_game() -> void:
  MultiplayerClient.join_lobby("")

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

func _handle_chatter_updated(chatter: Chatter) -> void:
  if chatter:
    gumbot.chatter = chatter

func _handle_ws_state_changed(connection_state: WSClient.WSClientState) -> void:
  if connection_state is WSClient.AuthenticatedState:
    MultiplayerClient.start()

func _update() -> void:
  game_subviewport_container.visible = false

  if MultiplayerClient.state.current is MultiplayerClient.LookingForLobby:
    _free_game_scene()
    start_game_button.visible = false
    close_lobby_button.visible = false
    host_game_button.visible = true
    center_info_label.visible = true
    lobby_info_panel.visible = false
    _type_text(LOOKING_TEXT, 0.1, true)
  elif MultiplayerClient.state.current is MultiplayerClient.Connected:
    game_subviewport_container.visible = false
    host_game_button.visible = false
    if MultiplayerClient.current_lobby:
      _handle_connected_state()
  elif MultiplayerClient.state.current is MultiplayerClient.Disconnected:
    _free_game_scene()
    start_game_button.visible = false
    close_lobby_button.visible = false
    host_game_button.visible = false
    lobby_info_panel.visible = false
    game_subviewport_container.visible = false

func _free_game_scene() -> void:
  if game_scene:
    game_scene.queue_free()
    game_scene = null

# func load_minigame(name: String, pck_path: String) -> void:
#   ProjectSettings.load_resource_pack(pck_path)
#   var entry = ResourceLoader.load("res://minigames/%s/main.tscn" % name)
#   add_child(entry.instantiate())

func _handle_connected_state() -> void:
  var is_lobby_host := MultiplayerClient.is_lobby_host()

  if MultiplayerClient.current_lobby.started:
    start_game_button.visible = false
    close_lobby_button.visible = is_lobby_host
    host_game_button.visible = false
    center_info_label.visible = false
    game_subviewport_container.visible = true

    if not game_scene:
      game_scene = pong_game_template.instantiate()
      game_scene.lobby = MultiplayerClient.current_lobby
      game_root_node.add_child(game_scene)
      overlay_subviewport_container.visible = false
      var tween := get_tree().create_tween()
      tween\
        .tween_property(gumbot, "position", gumbot.position - Vector3(0, 1, 0), 1.0)\
        .set_ease(Tween.EASE_IN)\
        .set_trans(Tween.TRANS_CUBIC)

  else:
    start_game_button.visible = is_lobby_host
    close_lobby_button.visible = is_lobby_host
    host_game_button.visible = false
    center_info_label.visible = true

    lobby_name_label.text = "Lobby: %s" % MultiplayerClient.current_lobby.name
    client_id_label.text = "Peer ID: %d" % MultiplayerClient.my_peer_id()
    lobby_info_panel.visible = true
    _type_text(_get_joining_text(MultiplayerClient.current_lobby), 0.1, false)
