extends Object
class_name Lobby

var name: String
var host_id: int
var mesh: bool
var sealed: bool
var peers: Array[String]

static func from_data(d: Dictionary) -> Lobby:
	var lobby := Lobby.new()
	lobby.name = d.get("name", "")
	lobby.host_id = d.get("hostId", 0)
	lobby.mesh = d.get("mesh", false)
	lobby.sealed = d.get("sealed", false)
	lobby.peers = Array(d.get("peers", []), TYPE_STRING, "", null)
	return lobby
