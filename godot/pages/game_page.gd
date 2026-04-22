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
@onready var overlay_subviewport_container: SubViewportContainer = %OverlaySubviewportContainer
@onready var loading: Loading = %Loading

var info_tween: Tween
const LOOKING_TEXT = "[font_size=50]LOOKING FOR LOBBY...[/font_size]"
var pong_game_template: PackedScene = preload("res://games/pong/pong_game.tscn")

var state := StateMachine.new()
var disconnected_state := DisconnectedState.new(self)
var looking_for_lobby_state := LookingForLobbyState.new(self)
var connected_idle_state := ConnectedIdleState.new(self)
var in_lobby_state := InLobbyState.new(self)
var loading_state := LoadingState.new(self)
var game_active_state := GameActiveState.new(self)

func _ready() -> void:
  add_child(state)
  state.add_child(disconnected_state)
  state.add_child(looking_for_lobby_state)
  state.add_child(connected_idle_state)
  state.add_child(in_lobby_state)
  state.add_child(loading_state)
  state.add_child(game_active_state)

  WSClient.authenticated_state.chatter_updated.connect(_handle_chatter_updated)
  WSClient.state.changed.connect(_handle_ws_state_changed)
  MultiplayerClient.state.changed.connect(_handle_multiplayer_state_changed)
  MultiplayerClient.current_lobby_updated.connect(_handle_lobby_updated)
  MultiplayerClient.connected_state.ping_check_completed.connect(_update_ping_label)

  host_game_button.pressed.connect(_host_game)
  close_lobby_button.pressed.connect(_close_lobby)
  start_game_button.pressed.connect(_start_game)

  loading_state.loading_complete.connect(state.change_state.bind(game_active_state))
  game_active_state.game_ended.connect(state.change_state.bind(looking_for_lobby_state))

  _handle_ws_state_changed(WSClient.state.current)
  _handle_chatter_updated(WSClient.my_chatter())
  _handle_multiplayer_state_changed(MultiplayerClient.state.current)
  if MultiplayerClient.current_lobby:
    _handle_lobby_updated(MultiplayerClient.current_lobby)

func _update_ping_label(msec_ping: float) -> void:
  ping_label.text = "PING: %sms" % int(msec_ping)

func _exit_tree() -> void:
  MultiplayerClient.stop()

func _close_lobby() -> void:
  MultiplayerClient.leave_lobby()

func _start_game() -> void:
  MultiplayerClient.start_lobby()

func _host_game() -> void:
  MultiplayerClient.join_lobby("")

func _handle_chatter_updated(chatter: Chatter) -> void:
  if chatter:
    gumbot.chatter = chatter

func _handle_ws_state_changed(connection_state: WSClient.WSClientState) -> void:
  if connection_state is WSClient.AuthenticatedState:
    MultiplayerClient.start()

func _handle_multiplayer_state_changed(mp_state: MultiplayerClient.MultiplayerClientState) -> void:
  if mp_state is MultiplayerClient.Disconnected:
    state.change_state(disconnected_state)
  elif mp_state is MultiplayerClient.LookingForLobby:
    state.change_state(looking_for_lobby_state)
  elif mp_state is MultiplayerClient.Connected:
    if not (state.current is LoadingState or state.current is GameActiveState or state.current is InLobbyState):
      state.change_state(connected_idle_state)

func _handle_lobby_updated(lobby: Lobby) -> void:
  if not lobby:
    return
  if lobby.started:
    if not (state.current is LoadingState or state.current is GameActiveState):
      state.change_state(loading_state)
  elif state.current is ConnectedIdleState or state.current is InLobbyState:
    state.change_state(in_lobby_state)

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

class GamePageState extends State:
  var page: GamePage
  func _init(_page: GamePage) -> void:
    self.page = _page

class DisconnectedState extends GamePageState:
  func enter_state(_prev: State) -> void:
    page.start_game_button.visible = false
    page.close_lobby_button.visible = false
    page.host_game_button.visible = false
    page.lobby_info_panel.visible = false
    page.game_subviewport_container.visible = false
    page.center_info_label.visible = true
    page.center_info_label.text = ""

class LookingForLobbyState extends GamePageState:
  func enter_state(_prev: State) -> void:
    page.start_game_button.visible = false
    page.close_lobby_button.visible = false
    page.host_game_button.visible = true
    page.center_info_label.visible = true
    page.lobby_info_panel.visible = false
    page.game_subviewport_container.visible = false
    page._type_text(GamePage.LOOKING_TEXT, 0.1, true)
    if page.loading.progress > 0:
      page.loading.transition_out()


class ConnectedIdleState extends GamePageState:
  func enter_state(_prev: State) -> void:
    page.start_game_button.visible = false
    page.close_lobby_button.visible = false
    page.host_game_button.visible = false
    page.game_subviewport_container.visible = false


class InLobbyState extends GamePageState:
  func enter_state(_prev: State) -> void:
    var is_host := MultiplayerClient.is_lobby_host()
    page.start_game_button.visible = is_host
    page.close_lobby_button.visible = is_host
    page.host_game_button.visible = false
    page.center_info_label.visible = true
    page.lobby_name_label.text = "Lobby: %s" % MultiplayerClient.current_lobby.name
    page.client_id_label.text = "Peer ID: %d" % MultiplayerClient.my_peer_id()
    page.lobby_info_panel.visible = true
    page._type_text(page._get_joining_text(MultiplayerClient.current_lobby), 0.1, false)

class LoadingState extends GamePageState:
  signal loading_complete

  func enter_state(_prev: State) -> void:
    page.start_game_button.visible = false
    page.close_lobby_button.visible = false
    page.host_game_button.visible = false
    page.center_info_label.visible = false
    page.lobby_info_panel.visible = false
    _transition()

  func _transition() -> void:
    await page.loading.transition_in()
    await page.get_tree().create_timer(1.0).timeout
    loading_complete.emit()

class GameActiveState extends GamePageState:
  signal game_ended
  var game_scene: PongGame = null

  func enter_state(_prev: State) -> void:
    page.overlay_subviewport_container.visible = false
    page.start_game_button.visible = false
    page.close_lobby_button.visible = MultiplayerClient.is_lobby_host()
    page.host_game_button.visible = false
    page.center_info_label.visible = false
    page.game_subviewport_container.visible = true

    game_scene = page.pong_game_template.instantiate()
    game_scene.lobby = MultiplayerClient.current_lobby
    page.game_root_node.add_child(game_scene)
    game_scene.game_finished.connect(_on_game_finished)

    page.loading.transition_out()

  func _on_game_finished() -> void:
    await page.loading.transition_in()
    game_ended.emit()

  func exit_state() -> void:
    page.overlay_subviewport_container.visible = true
    page.game_subviewport_container.visible = false
    if game_scene:
      game_scene.queue_free()
      game_scene = null
