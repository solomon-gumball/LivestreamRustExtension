class_name WsSessionBase
extends Node

@export var autojoin: bool = true
@export var lobby: String = ""  # Will create a new lobby if empty.
@export var mesh: bool = false  # Will use the lobby host as relay otherwise.

signal lobby_joined(lobby: String)
signal connected(id: int, use_mesh: bool)
signal disconnected()
signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal offer_received(id: int, offer: String)
signal answer_received(id: int, answer: String)
signal candidate_received(id: int, mid: String, index: int, sdp: String)
signal lobby_sealed()

func handle_ws_message(parsed: Variant) -> bool:
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var msg: Dictionary = parsed
	var type: String = msg.get("type", "")
	if type.is_empty():
		return false
	
	# print("rtc type: %s" % type)
	match type:
		"rtc-peer-id":
			connected.emit(int(msg.get("peer_id", 0)), bool(msg.get("mesh_mode", false)))
		"rtc-lobby-joined":
			lobby_joined.emit(str(msg.get("lobby_name", "")))
		"rtc-lobby-sealed":
			lobby_sealed.emit()
		"rtc-peer-connected":
			peer_connected.emit(int(msg.get("peer_id", 0)))
		"rtc-peer-disconnected":
			peer_disconnected.emit(int(msg.get("peer_id", 0)))
		"rtc-offer":
			print("GOT OFFER FROM: %s" % str(msg.get("from_peer_id", 0)))
			offer_received.emit(int(msg.get("from_peer_id", 0)), str(msg.get("sdp", "")))
		"rtc-answer":
			answer_received.emit(int(msg.get("from_peer_id", 0)), str(msg.get("sdp", "")))
		"rtc-candidate":
			var from_id: int = int(msg.get("from_peer_id", 0))
			var parts: PackedStringArray = str(msg.get("candidate", "")).split("\n", false)
			if parts.size() != 3:
				return false
			if not parts[1].is_valid_int():
				return false
			candidate_received.emit(from_id, parts[0], parts[1].to_int(), parts[2])
		_:
			return false

	return true  # Parsed.

func join_lobby(lobby_name: String) -> Error:
	if lobby_name.is_empty():
		return Network.send_socket_message({ "type": "rtc-create-lobby", "mesh_mode": mesh })
	else:
		return Network.send_socket_message({ "type": "rtc-join-lobby", "lobby_name": lobby_name })

func seal_lobby() -> Error:
	return Network.send_socket_message({ "type": "rtc-seal-lobby" })

func send_candidate(id: int, mid: String, index: int, sdp: String) -> Error:
	return Network.send_socket_message({ "type": "rtc-candidate", "dest_peer_id": id, "candidate": "%s\n%d\n%s" % [mid, index, sdp] })

func send_offer(id: int, offer: String) -> Error:
	print("SENT OFFER TO %d !!!" % id)
	return Network.send_socket_message({ "type": "rtc-offer", "dest_peer_id": id, "sdp": offer })

func send_answer(id: int, answer: String) -> Error:
	return Network.send_socket_message({ "type": "rtc-answer", "dest_peer_id": id, "sdp": answer })
