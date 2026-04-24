class_name GamePage
extends Control

@onready var gumbot: GumBot = %GumBot
@onready var lobby_name_label: Label = %LobbyNameLabel
@onready var client_id_label: Label = %ClientIdLabel
@onready var lobby_info_panel: Control = %LobbyInfoPanel
@onready var center_info_label: RichTextLabel = %CenterInfoLabel
@onready var start_game_button: Button = %StartGameButton
@onready var rejoin_lobby_button: Button = %RejoinLobbyButton

@onready var join_as_spectator_button: Button = %JoinAsSpectatorButton
@onready var join_as_player_button: Button = %JoinAsPlayerButton
@onready var change_role_button: Button = %ChangeRoleButton

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
var game_active_state := GameActiveState.new(self)

func _ready() -> void:
  add_child(state)
  state.add_child(disconnected_state)
  state.add_child(looking_for_lobby_state)
  state.add_child(lobby_detail_state)
  state.add_child(game_active_state)

  WSClient.authenticated_state.chatter_updated.connect(_handle_chatter_updated)
  WSClient.state.changed.connect(_handle_ws_state_changed)
  WSClient.authenticated_state.message_received.connect(_handle_ws_message)
  MultiplayerClient.state.changed.connect(_handle_mp_state_changed)
  MultiplayerClient.connected_state.ping_check_completed.connect(_update_ping_label)

  close_lobby_button.pressed.connect(_close_lobby)
  start_game_button.pressed.connect(_start_game)

  game_active_state.game_ended.connect(_handle_game_ended)

  _handle_chatter_updated(WSClient.my_chatter())

  _handle_websocket_connection_changed(WSClient.state.current)
  WSClient.state.changed.connect(_handle_websocket_connection_changed)

  _handle_updates()

func _handle_websocket_connection_changed(connection_state: WSClient.WSClientState) -> void:
  if connection_state is WSClient.AuthenticatedState:
    WSClient.send_socket_message({ "type": "rtc-fetch-lobbies" })

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

  if WSClient.state.current is WSClient.DisconnectedState:
    state.change_state(disconnected_state)
    return

  if MultiplayerClient.state.current is MultiplayerClient.Connected:
    print('we are still connected???')
    if MultiplayerClient.current_lobby.started:
      state.change_state(game_active_state)
    else:
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

func _handle_ws_state_changed(_s) -> void:
  _handle_updates()

func _handle_mp_state_changed(_s) -> void:
  _handle_updates()

func _handle_game_ended() -> void:
  MultiplayerClient.leave_lobby()
  _handle_updates()

func _exit_tree() -> void:
  WSClient.authenticated_state.chatter_updated.disconnect(_handle_chatter_updated)
  WSClient.state.changed.disconnect(_handle_ws_state_changed)
  WSClient.authenticated_state.message_received.disconnect(_handle_ws_message)
  MultiplayerClient.state.changed.disconnect(_handle_mp_state_changed)
  MultiplayerClient.connected_state.ping_check_completed.disconnect(_update_ping_label)
  WSClient.state.changed.disconnect(_handle_websocket_connection_changed)

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
  var player_count = lobby.players.size() if lobby else 0
  var spectator_count = lobby.spectators.size() if lobby else 0
  return "\n".join([
    "[font_size=50]JOINING[/font_size]",
    "[font_size=120]PONG[/font_size]",
    "[font_size=50]\nSTAKES....[color=green]100 gum[/color][/font_size]",
    _stat_line("PLAYERS", 9, player_count),
    _stat_line("SPECTATORS", 6, spectator_count),
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
    page.rejoin_lobby_button.visible = false
    page.join_as_player_button.visible = false
    page.join_as_spectator_button.visible = false
    page.change_role_button.visible = false

class LookingForLobbyState extends GamePageState:
  func enter_state(_prev: State) -> void:
    page.start_game_button.visible = false
    page.close_lobby_button.visible = false
    page.center_info_label.visible = true
    page.rejoin_lobby_button.visible = false
    page.lobby_info_panel.visible = false
    page.join_as_player_button.visible = false
    page.join_as_spectator_button.visible = false
    page.change_role_button.visible = false
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
    page.join_as_player_button.pressed.connect(_handle_join_as_player_pressed)
    page.join_as_spectator_button.pressed.connect(_handle_join_as_spectator_pressed)
    page.rejoin_lobby_button.pressed.connect(_handle_rejoin_pressed)
    page.change_role_button.pressed.connect(_handle_change_role_pressed)
    _refresh_buttons()

  func exit_state() -> void:
    page.join_as_player_button.pressed.disconnect(_handle_join_as_player_pressed)
    page.join_as_spectator_button.pressed.disconnect(_handle_join_as_spectator_pressed)
    page.rejoin_lobby_button.pressed.disconnect(_handle_rejoin_pressed)
    page.change_role_button.pressed.disconnect(_handle_change_role_pressed)

  func _find_my_peer() -> Lobby.PeerData:
    var my_chatter_id := WSClient.my_chatter().id
    for peer in lobby.peers:
      if peer.chatter_id == my_chatter_id:
        return peer
    return null

  func _refresh_buttons() -> void:
    if not lobby:
      return

    page.center_info_label.text = page._get_joining_text(lobby)
    page.lobby_name_label.text = "Lobby: %s" % lobby.name
    page.client_id_label.text = "Peer ID: %d" % MultiplayerClient.my_peer_id()

    var my_peer := _find_my_peer()
    var my_chatter_id := WSClient.my_chatter().id
    var is_host := lobby.host_chatter_id == my_chatter_id

    # Default all managed buttons to hidden; selectively show below.
    page.join_as_player_button.visible = false
    page.join_as_player_button.disabled = false
    page.join_as_spectator_button.visible = false
    page.start_game_button.disabled = false
    page.rejoin_lobby_button.visible = false
    page.change_role_button.visible = false
    page.start_game_button.visible = false
    page.close_lobby_button.visible = false

    var players_full: bool = lobby.players.size() >= lobby.game.max_players

    if my_peer == null:
      # Not in the lobby yet — disable join as player if slots are full.
      page.join_as_player_button.visible = true
      page.join_as_player_button.disabled = players_full
      page.join_as_spectator_button.visible = true
    elif not my_peer.connected:
      # In the lobby but WS dropped — single rejoin button, role is preserved server-side.
      page.rejoin_lobby_button.visible = true
    else:
      # Connected and in the lobby.
      page.close_lobby_button.text = "CLOSE LOBBY" if is_host else "LEAVE LOBBY"
      page.close_lobby_button.visible = true
      page.start_game_button.visible = is_host
      page.start_game_button.disabled = lobby.players.size() < lobby.game.min_players
      # Role toggle: label reflects what the switch would do.
      # Hide the "become player" direction if the lobby is already full.
      var can_become_player: bool = my_peer.is_player or not players_full
      page.change_role_button.text = "BECOME SPECTATOR" if my_peer.is_player else "BECOME PLAYER"
      page.change_role_button.visible = can_become_player

  func _handle_join_as_player_pressed() -> void:
    WSClient.send_socket_message({ "type": "rtc-join-lobby", "lobby_name": lobby.name, "is_player": true })

  func _handle_join_as_spectator_pressed() -> void:
    WSClient.send_socket_message({ "type": "rtc-join-lobby", "lobby_name": lobby.name, "is_player": false })

  func _handle_rejoin_pressed() -> void:
    WSClient.send_socket_message({ "type": "rtc-join-lobby", "lobby_name": lobby.name })

  func _handle_change_role_pressed() -> void:
    var my_peer := _find_my_peer()
    if my_peer:
      MultiplayerClient.set_role(not my_peer.is_player)

class GameActiveState extends GamePageState:
  signal game_ended
  var game_scene: PongGame = null

  func enter_state(_prev: State) -> void:
    if _prev is LobbyDetailState:
      await page.loading.transition_in()

    page.overlay_subviewport_container.visible = false
    page.start_game_button.visible = false
    page.close_lobby_button.visible = false
    page.center_info_label.visible = false
    page.game_subviewport_container.visible = true
    page.rejoin_lobby_button.visible = false

    game_scene = page.pong_game_template.instantiate()
    game_scene.lobby = MultiplayerClient.current_lobby
    page.game_root_node.add_child(game_scene)
    game_scene.game_finished.connect(_on_game_finished)

    if _prev is LobbyDetailState:
      await page.loading.transition_out()

  func _on_game_finished() -> void:
    await page.loading.transition_in()
    game_ended.emit()

  func exit_state() -> void:
    page.overlay_subviewport_container.visible = true
    page.game_subviewport_container.visible = false
    if game_scene:
      game_scene.queue_free()
      game_scene = null
