extends Node3D
class_name OverlayScene

var state = StateMachine.new()
var roaming_state = RoamingState.new(self)
var game_state = GameState.new(self)
var lobby_list: Array[Lobby] = []

@onready var loading: Loading = %Loading
@onready var debug_label: Label = %DebugLabel

var game_container: GameContainer = null
var roaming_scene: RoamingBots = null

func _ready():
  WSClient.authenticated_state.message_received.connect(_handle_ws_message)

  add_child(state)
  state.add_child(roaming_state)
  state.add_child(game_state)
  state.change_state(roaming_state)

  _handle_websocket_connection_changed(WSClient.state.current)
  MultiplayerClient.state.changed.connect(_handle_multiplayer_connection_changed)
  WSClient.state.changed.connect(_handle_websocket_connection_changed)

  game_state.game_finished.connect(_handle_game_finished)

func _handle_game_finished() -> void:
  MultiplayerClient.leave_lobby()
  _handle_updates()

func _handle_multiplayer_connection_changed(_connection_state: MultiplayerClient.MultiplayerClientState) -> void:
  print("Multiplayer connection state changed: %s" % MultiplayerClient.state.current)
  _handle_updates()

func _handle_websocket_connection_changed(connection_state: WSClient.WSClientState) -> void:
  if connection_state is WSClient.AuthenticatedState:
    WSClient.send_socket_message({ "type": "rtc-fetch-lobbies" })

func _input(_event):
  if Input.is_action_just_pressed("StartLobby"):
    print(MultiplayerClient.state.current is MultiplayerClient.Disconnected)
    if MultiplayerClient.state.current is MultiplayerClient.Connected:
      MultiplayerClient.start_lobby()
    else:
      # MultiplayerClient.join_lobby("")
      pass
    pass

var is_joining := false
func _handle_updates() -> void:
  var lobby = MultiplayerClient.current_lobby

  if lobby:
    is_joining = false
    if lobby.started:
      game_state.lobby = lobby
      state.change_state(game_state)
    return
  
  state.change_state(roaming_state)
  if lobby_list.size() > 0 and not is_joining:
    var available_lobby = lobby_list[0]
    print("Joining lobby: %s" % available_lobby.name)
    is_joining = true
    MultiplayerClient.join_lobby(available_lobby)

func _handle_ws_message(parsed: Variant) -> void:
  if typeof(parsed) != TYPE_DICTIONARY:
    return
  var msg: Dictionary = parsed
  if msg.get("type", "") == "rtc-lobbies-updated":
    var lobbies: Array[Lobby] = []
    for lobby_data in msg.get("lobbies", []):
      lobbies.append(Lobby.from_data(lobby_data))
    lobby_list = lobbies
    print("Multiplayer connection state changed: %s" % MultiplayerClient.state.current)
    _handle_updates()

class StreamOverlayState extends State:
  var overlay: OverlayScene
  func _init(_overlay: OverlayScene) -> void:
    self.overlay = _overlay

class RoamingState extends StreamOverlayState:
  var roaming_bots_template: PackedScene = preload("res://stream_overlay/roaming_bots.tscn")

  func enter_state(_previous_state: State) -> void:
    if _previous_state is GameState:
      await overlay.loading.transition_in()
    
    overlay.roaming_scene = roaming_bots_template.instantiate() as RoamingBots
    overlay.add_child(overlay.roaming_scene)
    
    if _previous_state is GameState:
      if overlay.game_container:
        overlay.game_container.queue_free()
      await overlay.loading.transition_out()

class GameState extends StreamOverlayState:
  var lobby: Lobby
  var pong_game_template: PackedScene = preload("res://games/pong/pong_game.tscn")
  signal game_finished

  func enter_state(_previous_state: State) -> void:
    await overlay.loading.transition_in()
    if _previous_state is RoamingState:
      if overlay.roaming_scene:
        overlay.roaming_scene.queue_free()
    overlay.game_container = GameContainer.new()
    overlay.add_child(overlay.game_container)
    overlay.game_container.game_finished.connect(game_finished.emit)
    await overlay.game_container.load_game_from_lobby(MultiplayerClient.current_lobby)
    await overlay.loading.transition_out()
