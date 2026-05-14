extends Node
class_name MultiplayerTestContainer

@export var child_scene: PackedScene
@export var num_players: int = 2

var is_host := false
var ready_peers: Array[int]

func _ready() -> void:
  ObjectSerializer.register_script(MarblesGameState)
  ObjectSerializer.register_script(PongGameState)
  if WSClient.state.current is not WSClient.AuthenticatedState:
    await WSClient.authenticated

  MultiplayerClient.rtc_peer_ready.connect(_peer_ready)
  WSClient.authenticated_state.message_received.connect(_handle_ws_message)
  MultiplayerClient.connected_state.lobby_updated.connect(try_start)

  is_host = DebugScreenLayout.window_index == 0
  if is_host:
    var error: String = await WSClient.create_lobby("pong", true)
    if error:
      print("err ", error)
  else:
    WSClient.send_socket_message({ "type": "rtc-fetch-lobbies" })

func _peer_ready(peer_id: int) -> void:
  if !ready_peers.has(peer_id):
    ready_peers.append(peer_id)
    _host_check_ready()

var did_join := false
func _handle_ws_message(parsed: Variant) -> void:
  if typeof(parsed) != TYPE_DICTIONARY:
    return
  var msg: Dictionary = parsed
  if msg.get("type", "") == "rtc-lobbies-updated":
    _host_check_ready()

    var lobbies_data: Array = msg.get("lobbies", [])
    if lobbies_data.get(0):
      var lobby_to_join := Lobby.from_data(lobbies_data.get(0))
      if lobby_to_join and !lobby_to_join.has_chatter(WSClient.my_chatter().id) and !did_join:
        MultiplayerClient.join_lobby(lobby_to_join, true)
        did_join = true

var did_start := false
func _host_check_ready() -> void:
  if !is_host or did_start: return
  if MultiplayerClient.state.current is MultiplayerClient.Connected:
    var lobby: Lobby = MultiplayerClient.current_lobby

    var all_players_ready := ready_peers.size() >= num_players - 1
    if !lobby.started and all_players_ready:
      did_start = true
      MultiplayerClient.start_lobby()

func try_start():
  var lobby := MultiplayerClient.current_lobby

  if lobby and lobby.started:
    var game_container := GameContainer.new()
    add_child(game_container)
    await game_container.load_game_from_lobby(MultiplayerClient.current_lobby)
    
