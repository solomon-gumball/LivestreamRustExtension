extends Object
class_name Lobby

var name: String
var host_id: int
var host_chatter_id: String
var mesh: bool
var sealed: bool
var peers: Array[String]
var started: bool

static func from_data(d: Dictionary) -> Lobby:
	var lobby := Lobby.new()
	lobby.started = d.get("started", false)
	lobby.name = d.get("name", "")
	lobby.host_id = d.get("hostId", 0)
	lobby.host_chatter_id = d.get("hostChatterId", "")
	lobby.mesh = d.get("mesh", false)
	lobby.sealed = d.get("sealed", false)
	lobby.peers = Array(d.get("peers", []), TYPE_STRING, "", null)
	return lobby
