class_name GamePage
extends Control

@onready var gumbot: GumBot = %GumBot
@onready var lobby_name_label: Label = %LobbyNameLabel
@onready var client_id_label: Label = %ClientIdLabel
@onready var lobby_info_panel: Control = %LobbyInfoPanel
@onready var center_info_label: RichTextLabel = %CenterInfoLabel
@onready var start_game_button: Button = %StartGameButton
@onready var join_game_button: Button = %JoinLobbyButton
@onready var close_lobby_button: Button = %CloseLobbyButton
@onready var game_root_node: Node3D = %GameRootNode
@onready var ping_label: Label = %PingLabel
@onready var game_subviewport_container: SubViewportContainer = %GameSubviewportContainer
@onready var overlay_subviewport_container: SubViewportContainer = %OverlaySubviewportContainer
@onready var loading: Loading = %Loading
@onready var debug_square: ColorRect = %DebugSquare
@onready var join_lobby_tab: Control = %JoinLobbyTab

var info_tween: Tween
const LOOKING_TEXT = "[font_size=50]LOOKING FOR LOBBY...[/font_size]"
var pong_game_template: PackedScene = preload("res://games/pong/pong_game.tscn")

var lobby_list: Array[Lobby] = []

var state := StateMachine.new()
var disconnected_state := DisconnectedState.new(self)
var looking_for_lobby_state := LookingForLobbyState.new(self)
var lobby_detail_state := LobbyDetailState.new(self)
var loading_state := LoadingState.new(self)
var game_active_state := GameActiveState.new(self)

func _ready() -> void:
  add_child(state)
  state.add_child(disconnected_state)
  state.add_child(looking_for_lobby_state)
  state.add_child(lobby_detail_state)
  state.add_child(loading_state)
  state.add_child(game_active_state)

  WSClient.authenticated_state.chatter_updated.connect(_handle_chatter_updated)
  WSClient.state.changed.connect(func(_s): _handle_updates())
  WSClient.authenticated_state.message_received.connect(_handle_ws_message)
  MultiplayerClient.state.changed.connect(func(_s): _handle_updates())
  MultiplayerClient.connected_state.ping_check_completed.connect(_update_ping_label)

  close_lobby_button.pressed.connect(_close_lobby)
  start_game_button.pressed.connect(_start_game)

  loading_state.loading_complete.connect(state.change_state.bind(game_active_state))
  game_active_state.game_ended.connect(func():
    MultiplayerClient.leave_lobby()
  )

  _handle_chatter_updated(WSClient.my_chatter())

  if WSClient.state.current is WSClient.AuthenticatedState:
    WSClient.send_socket_message({ "type": "rtc-fetch-lobbies" })

  _handle_updates()

func _handle_ws_message(parsed: Variant) -> void:
  if typeof(parsed) != TYPE_DICTIONARY:
    return
  var msg: Dictionary = parsed
  if msg.get("type", "") == "rtc-lobbies-updated":
    var lobbies: Array[Lobby] = []
    for lobby_data in msg.get("lobbies", []):
      lobbies.append(Lobby.from_data(lobby_data))
    lobby_list = lobbies
    _handle_updates()

func _handle_updates() -> void:
  if state.current is LoadingState or state.current is GameActiveState:
    return

  if WSClient.state.current is WSClient.DisconnectedState:
    state.change_state(disconnected_state)
    return

  if MultiplayerClient.state.current is MultiplayerClient.Connected:
    lobby_detail_state.lobby = MultiplayerClient.current_lobby
    state.change_state(lobby_detail_state)
    return

  if lobby_list.is_empty():
    state.change_state(looking_for_lobby_state)
  else:
    lobby_detail_state.lobby = lobby_list[0]
    state.change_state(lobby_detail_state)

func _update_ping_label(msec_ping: float) -> void:
  ping_label.text = "PING: %sms" % int(msec_ping)

func _exit_tree() -> void:
  MultiplayerClient.stop()

func _close_lobby() -> void:
  MultiplayerClient.leave_lobby()

func _start_game() -> void:
  MultiplayerClient.start_lobby()

func _handle_chatter_updated(chatter: Chatter) -> void:
  if chatter:
    gumbot.chatter = chatter

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
    page.lobby_info_panel.visible = false
    page.game_subviewport_container.visible = false
    page.center_info_label.visible = true
    page.center_info_label.text = ""
    page.join_game_button.visible = false

class LookingForLobbyState extends GamePageState:
  func enter_state(_prev: State) -> void:
    page.start_game_button.visible = false
    page.close_lobby_button.visible = false
    page.center_info_label.visible = true
    page.join_game_button.visible = false
    page.lobby_info_panel.visible = false
    page.game_subviewport_container.visible = false
    page._type_text(GamePage.LOOKING_TEXT, 0.1, true)

    if page.loading.progress > 0:
      page.loading.transition_out()

class LobbyDetailState extends GamePageState:
  var lobby: Lobby = null:
    set(val):
      lobby = val
      if sm and sm.current == self:
        _refresh_buttons()

  func enter_state(_prev: State) -> void:
    page.game_subviewport_container.visible = false
    page.center_info_label.visible = true
    page.lobby_info_panel.visible = true
    page._type_text(page._get_joining_text(lobby), 0.1, false)
    page.join_game_button.pressed.connect(_handle_join_pressed)
    _refresh_buttons()

  func exit_state() -> void:
    page.join_game_button.pressed.disconnect(_handle_join_pressed)

  func _refresh_buttons() -> void:
    if not lobby:
      return
    var my_chatter_id := WSClient.my_chatter().id
    var my_peer: Lobby.PeerData = null
    for peer in lobby.peers:
      if peer.chatter_id == my_chatter_id:
        my_peer = peer
        break
    
    page.center_info_label.text = page._get_joining_text(lobby)
    page.lobby_name_label.text = "Lobby: %s" % lobby.name
    page.client_id_label.text = "Peer ID: %d" % MultiplayerClient.my_peer_id()

    if my_peer != null:
      if not my_peer.connected:
        page.join_game_button.text = "REJOIN"
        page.join_game_button.visible = true
        page.start_game_button.visible = false
        page.close_lobby_button.visible = false
      else:
        var is_host := lobby.host_chatter_id == my_chatter_id
        page.join_game_button.visible = false
        page.start_game_button.visible = is_host
        page.close_lobby_button.visible = is_host
        if not is_host:
          page.close_lobby_button.visible = false
          page.start_game_button.visible = false
          page.join_game_button.text = "LEAVE"
          page.join_game_button.visible = true
    else:
      page.join_game_button.text = "JOIN"
      page.join_game_button.visible = true
      page.start_game_button.visible = false
      page.close_lobby_button.visible = false

  func _handle_join_pressed() -> void:
    var my_chatter_id := WSClient.my_chatter().id
    var my_peer: Lobby.PeerData = null
    for peer in lobby.peers:
      if peer.chatter_id == my_chatter_id:
        my_peer = peer
        break

    if my_peer != null and my_peer.connected:
      MultiplayerClient.leave_lobby()
    else:
      print("JOINING LOBBY!!")
      MultiplayerClient.join_lobby(lobby)

class LoadingState extends GamePageState:
  signal loading_complete

  func enter_state(_prev: State) -> void:
    page.start_game_button.visible = false
    page.close_lobby_button.visible = false
    page.center_info_label.visible = false
    page.lobby_info_panel.visible = false
    page.join_game_button.visible = false
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
    page.close_lobby_button.visible = false
    page.center_info_label.visible = false
    page.game_subviewport_container.visible = true
    page.join_game_button.visible = false

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
