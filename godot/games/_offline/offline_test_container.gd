extends Node
class_name OfflineTestContainer

@export var child_scene: PackedScene
var mock_lobby: Lobby
func _ready() -> void:
  ObjectSerializer.register_script(MarblesGameState)
  
  if WSClient.state.current is not WSClient.AuthenticatedState:
    await WSClient.authenticated

  var mock_game_data := GameMetadata.new()
  var mock_data := MockData.generate_mock_game_lobby(WSClient.my_chatter(), 5, 3, 5, 5, mock_game_data)
  mock_lobby = mock_data.get("lobby")
  # print(mock_lobby.host_chatter_id, " ", WSClient.my_chatter().id)
  MultiplayerClient.current_lobby = mock_lobby
  print(MultiplayerClient.is_lobby_host())

  var scene_inst: GameBase = child_scene.instantiate() as GameBase
  scene_inst.lobby = mock_lobby
  for chatter in mock_data.get("chatters"):
    scene_inst.chatters[chatter.id] = chatter
  add_child(scene_inst)