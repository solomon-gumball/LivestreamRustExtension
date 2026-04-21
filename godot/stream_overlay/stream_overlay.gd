extends Node3D
class_name OverlayScene

var state = StateMachine.new()
var roaming_state = RoamingState.new(self)
var game_state = GameState.new(self)

func _ready():
  MultiplayerClient.current_lobby_updated.connect(_handle_lobby_updated)

  MultiplayerClient.start()
  WSClient.state.changed.connect(_handle_ws_state_changed)

  add_child(state)
  state.add_child(roaming_state)
  state.add_child(game_state)
  state.change_state(roaming_state)

func _handle_ws_state_changed(connection_state: WSClient.WSClientState) -> void:
  if connection_state is WSClient.AuthenticatedState:
    MultiplayerClient.start()

func _input(_event):
  if Input.is_action_just_pressed("StartLobby"):
    print(MultiplayerClient.state.current is MultiplayerClient.Disconnected)
    if MultiplayerClient.state.current is MultiplayerClient.Connected:
      MultiplayerClient.start_lobby()
    else:
      MultiplayerClient.join_lobby("")
    pass

var pong_game_template: PackedScene = preload("res://games/pong/pong_game.tscn")
func _handle_lobby_updated(lobby: Lobby) -> void:
  if lobby and lobby.started:
    game_state.lobby = lobby
    state.change_state(game_state)

class StreamOverlayState extends State:
  var overlay: OverlayScene
  func _init(_overlay: OverlayScene) -> void:
    self.overlay = _overlay

class RoamingState extends StreamOverlayState:
  var scene: RoamingBots
  var roaming_bots_template: PackedScene = preload("res://stream_overlay/roaming_bots.tscn")

  func enter_state(_previous_state: State) -> void:
    scene = roaming_bots_template.instantiate() as RoamingBots
    overlay.add_child(scene)
  
  func exit_state() -> void:
    scene.queue_free()

class GameState extends StreamOverlayState:
  var scene: PongGame
  var lobby: Lobby
  var pong_game_template: PackedScene = preload("res://games/pong/pong_game.tscn")

  func enter_state(_previous_state: State) -> void:
    scene = pong_game_template.instantiate() as PongGame
    scene.lobby = lobby
    overlay.add_child(scene)
  
  func exit_state() -> void:
    scene.queue_free()
