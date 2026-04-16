extends Object
class_name Lobby

class PeerData:
	var peer_id: int
	var chatter_id: String

	static func from_data(d: Dictionary) -> PeerData:
		var peer := PeerData.new()
		peer.peer_id = d.get("peerId", 0)
		peer.chatter_id = d.get("chatterId", "")
		return peer

var name: String
var host_id: int
var host_chatter_id: String
var mesh: bool
var sealed: bool
var peers: Array[PeerData]
var started: bool

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
		lobby.peers.append(PeerData.from_data(peer_data))
	return lobby
