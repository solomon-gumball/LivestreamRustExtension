class_name GamePage
extends Control

@export var gumbot: GumBot
@onready var lobby_name_label: Label = %LobbyNameLabel
@onready var client_id_label: Label = %ClientIdLabel
@onready var lobby_info_panel: Control = %LobbyInfoPanel
@onready var debug_rect: Control = %DebugRect

@onready var center_info_label: RichTextLabel = %CenterInfoLabel

@onready var start_game_button: Button = %StartGameButton
@onready var close_lobby_button: Button = %CloseLobbyButton
@onready var host_game_button: Button = %HostGameButton
@onready var game_root_node: Node3D = %GameRootNode
@onready var ping_label: Label = %PingLabel

# @onready var state_machine: StateMachine = %StateMachine

var info_tween: Tween
var current_lobby: Lobby:
  set(new_val):
    current_lobby = new_val
    if current_lobby:
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

var pong_game_template: PackedScene = preload("res://games/pong/pong_game.tscn")
var game_scene: PongGame = null

enum GameState { None, LookingForLobby, JoiningLobby, InLobby, InGame }
var game_state: GameState:
  set(new_value):
    var old_value = game_state
    game_state = new_value

    # if current_lobby:
    #   print(current_lobby.started)

    # print('prev state -> ', old_value, ' new state -> ', new_value)
    if old_value != new_value:
      if game_scene:
        game_scene.queue_free()
        game_scene = null

      var is_lobby_host := false
      if current_lobby:
        is_lobby_host = current_lobby.host_chatter_id == Network.current_chatter.id

      match new_value:
        GameState.LookingForLobby:
          start_game_button.visible = false
          close_lobby_button.visible = false
          host_game_button.visible = true
          center_info_label.visible = true

          _type_text(LOOKING_TEXT, 0.1, true)
        GameState.JoiningLobby, GameState.InLobby:
          start_game_button.visible = is_lobby_host
          close_lobby_button.visible = is_lobby_host
          host_game_button.visible = false
          center_info_label.visible = true

          _type_text(_get_joining_text(), 0.1, false)
        GameState.InGame:
          start_game_button.visible = false
          close_lobby_button.visible = is_lobby_host
          host_game_button.visible = false
          center_info_label.visible = false

          game_scene = pong_game_template.instantiate()
          game_scene.lobby = current_lobby
          game_root_node.add_child(game_scene)

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
  Network.multiplayer_client.lobbies_updated.connect(_lobbies_updated)
  Network.store_data_received.connect(_store_data_received)
  if Network.current_chatter:
    Network.send_socket_message({ "type": "rtc-fetch-lobbies" })

  # test_rpc_button.pressed.connect(test_rpc.rpc)
  _handle_chatter_updated(Network.current_chatter)
  host_game_button.pressed.connect(_host_game)
  close_lobby_button.pressed.connect(_close_lobby)
  start_game_button.pressed.connect(_start_game)

  Network.multiplayer_client.ping_check_completed.connect(_update_ping_label)

  game_state = GameState.LookingForLobby
  Network.socket_connection_status_changed.connect(_handle_net_state_changed)

func _update_ping_label(msec_ping: float) -> void:
  ping_label.text = "PING: %sms" % int(msec_ping)

func _store_data_received() -> void:
  Network.send_socket_message({ "type": "rtc-fetch-lobbies" })

func _exit_tree() -> void:
  if current_lobby:
    Network.send_socket_message({
      "type": "rtc-leave-lobby",
      "lobby_id": current_lobby.name
    })

func _close_lobby() -> void:
  if current_lobby:
    Network.send_socket_message({
      "type": "rtc-leave-lobby",
      "lobby_id": current_lobby.name
    })

func _start_game() -> void:
  if current_lobby:
    Network.send_socket_message({
      "type": "rtc-start-game",
      "lobby_id": current_lobby.name
    })

func _host_game() -> void:
  Network.multiplayer_client.join_lobby("")

func _lobbies_updated(lobbies: Array[Lobby]) -> void:
  print('_lobbies_updated')

  if Network.current_chatter == null: return
  if lobbies.size() == 0:
    game_state = GameState.LookingForLobby
    if current_lobby:
      Network.multiplayer_client.stop()
    current_lobby = null
    return

  var new_lobby = lobbies[0]

  if new_lobby:
    current_lobby = new_lobby
  match game_state:
    GameState.LookingForLobby:
      if new_lobby:
        var is_already_in_lobby: bool = new_lobby.peers.any(func (peer):
          return peer.chatter_id == Network.current_chatter.id
        )
        print("is_in_lobby=", is_already_in_lobby, " started=", new_lobby.started)

        # Cases:
        #
        # - [Host who just created the lobby]: already in peer list and rtc_mp
        # initialized via rtc-peer-id — skip join, just advance state.
        # 
        # - [Reconnecting non-host]: already in peer list but rtc_mp was reset by stop(),
        # so fall through to join_lobby to re-initialize via a fresh rtc-peer-id.
        #
        # - [New non-host joining]: not in peer list yet, always calls join_lobby.
        #
        if is_already_in_lobby and Network.multiplayer_client.is_initialized():
          if new_lobby.started:
            game_state = GameState.InGame
          else:
            game_state = GameState.JoiningLobby
        else:
          Network.multiplayer_client.join_lobby(new_lobby.name)
      
    GameState.InLobby, GameState.JoiningLobby:
      var is_in_lobby: bool = new_lobby.peers.any(func (peer):
        return peer.chatter_id == Network.current_chatter.id
      )
      # print("is_in_lobby=", is_in_lobby, " started=", new_lobby.started)
      if is_in_lobby:
        if new_lobby.started:
          game_state = GameState.InGame
        else:
          game_state = GameState.InLobby
    # GameState.InGame:
    #   if new_lobby:
    #     var is_in_lobby: bool = new_lobby.peers.any(func (peer):
    #       return peer.chatter_id == Network.current_chatter.id
    #     )
    #     if not is_in_lobby:
    #       Network.multiplayer_client.join_lobby(new_lobby.name)

func _lobby_joined(_lobby: String) -> void:
  lobby_name_label.text = "Lobby: %s" % _lobby
  client_id_label.text = "Peer ID: %d" % Network.multiplayer_client.my_peer_id()
  lobby_info_panel.visible = true

func _handle_chatter_updated(chatter: Chatter) -> void:
  if chatter:
    gumbot.chatter = chatter

func _handle_net_state_changed(connected: bool) -> void:
  if !connected:
    current_lobby = null
    game_state = GameState.LookingForLobby
  else:
    current_lobby = null
    Network.send_socket_message({ "type": "rtc-fetch-lobbies" })
  # if connected and current_lobby:
  #   game_state = GameState.JoiningLobby
  #   current_lobby = 
    

# class GamePageState extends State:
#   var lobby: Lobby

# class LookingForLobbyState extends State:
#   func enter_state(_previous_state: State) -> void:
#     Network.multiplayer_client.lobbies_updated.connect(_handle_lobbies_updated)
#   func exit_state() -> void: pass

#   func _handle_lobbies_updated(lobbies: Array[Lobby]) -> void:
#     if lobbies.size() > 0:
#       Network.multiplayer_client.join_lobby(lobbies[0].name)

# class JoiningLobbyState extends State:
#   signal did_leave_lobby
#   func enter_state(_previous_state: State) -> void:
#     lobby_info_panel.visible = true
#     Network.multiplayer_client.lobbies_updated.connect(_handle_lobbies_updated)
  
#   func _handle_lobbies_updated(lobbies: Array[Lobby]) -> void:
#     if lobbies.size() == 0:
#       did_leave_lobby.emit()
#       return
#     var new_lobby_data: Lobby = lobbies[0]
#     if new_lobby_data

#   func exit_state() -> void: pass

#   func _handle_lobbies_updated(lobbies: Array[Lobby]) -> void:
#     if lobbies.size() > 0:
#       Network.multiplayer_client.join_lobby(lobbies[0].name)
