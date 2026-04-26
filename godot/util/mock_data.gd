class_name MockData
extends Object

static func generate_mock_game_lobby(
  num_players: int,
  num_connected_players: int,
  num_spectators: int,
  num_connected_spectators: int,
  game_metadata: GameMetadata
) -> Dictionary:
  var peer_id_counter := 1
  var peers_data: Array = []

  for i in range(num_players):
    var chatter_id := "mock_player_%d" % (i + 1)
    peers_data.append({
      "peerId": peer_id_counter,
      "chatterId": chatter_id,
      "connected": i < num_connected_players,
      "is_player": true,
    })
    peer_id_counter += 1

  for i in range(num_spectators):
    var chatter_id := "mock_spectator_%d" % (i + 1)
    peers_data.append({
      "peerId": peer_id_counter,
      "chatterId": chatter_id,
      "connected": i < num_connected_spectators,
      "is_player": false,
    })
    peer_id_counter += 1

  var host_peer = peers_data[0] if peers_data.size() > 0 else {"peerId": 1, "chatterId": "mock_player_1"}

  var lobby := Lobby.from_data({
    "name": "Mock Lobby",
    "hostId": host_peer["peerId"],
    "hostChatterId": host_peer["chatterId"],
    "mesh": false,
    "sealed": false,
    "started": false,
    "peers": peers_data,
    "game": {
      "thumbnail_url": game_metadata.thumbnail_url,
      "bundle_url": game_metadata.bundle_url,
      "title": game_metadata.title,
      "description": game_metadata.description,
      "entry": game_metadata.entry,
      "cost": game_metadata.cost,
      "min_players": game_metadata.min_players,
      "max_players": game_metadata.max_players,
      "pck_hash": game_metadata.pck_hash,
    },
  })

  var chatters: Array[Chatter] = []
  for peer_data in peers_data:
    chatters.append(_make_mock_chatter(peer_data["chatterId"]))

  return {
    "lobby": lobby,
    "chatters": chatters,
  }

static func _make_mock_chatter(chatter_id: String) -> Chatter:
  var label := chatter_id.replace("_", " ").capitalize()
  return Chatter.FromData({
    "id": chatter_id,
    "display_name": label,
    "login": chatter_id,
    "color": "#%06x" % (randi() & 0xFFFFFF),
    "emote": "",
    "equipped": {},
    "assets": [],
    "balance": 0,
    "messages_sent": 0,
    "created_at": "2024-01-01T00:00:00Z",
    "last_active": "2024-01-01T00:00:00Z",
    "duels_won": 0,
    "marbles_won": 0,
    "royales_won": 0,
    "gifts_given": 0,
  })
