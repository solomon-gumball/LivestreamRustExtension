extends Object
class_name Lobby

class PeerData:
  var peer_id: int
  var chatter_id: String
  var connected: bool
  var is_player: bool

  static func from_data(d: Dictionary) -> PeerData:
    var peer := PeerData.new()
    peer.peer_id = d.get("peerId", 0)
    peer.chatter_id = d.get("chatterId", "")
    peer.connected = d.get("connected", false)
    peer.is_player = d.get("is_player", false)
    return peer

var name: String
var host_id: int
var host_chatter_id: String
var mesh: bool
var sealed: bool
var peers: Array[PeerData]
var started: bool

var peer_from_chatter: Dictionary[String, int] = {}
var chatter_from_peer: Dictionary[int, String] = {}
var connected_peers: Array[PeerData] = []
var players: Array[PeerData] = []
var spectators: Array[PeerData] = []

static func from_data(d: Dictionary) -> Lobby:
  var lobby := Lobby.new()
  lobby.started = d.get("started", false)
  lobby.name = d.get("name", "")
  lobby.host_id = d.get("hostId", 0)
  lobby.host_chatter_id = d.get("hostChatterId", "")
  lobby.mesh = d.get("mesh", false)
  lobby.sealed = d.get("sealed", false)
  lobby.peers = []
  for peer_data in d.get("peers", []):
    var peer := PeerData.from_data(peer_data)
    lobby.peers.append(peer)
    lobby.chatter_from_peer[peer.peer_id] = peer.chatter_id
    lobby.peer_from_chatter[peer.chatter_id] = peer.peer_id
    if peer.connected:
      lobby.connected_peers.append(peer)
    if peer.is_player:
      lobby.players.append(peer)
    else:
      lobby.spectators.append(peer)
  return lobby
