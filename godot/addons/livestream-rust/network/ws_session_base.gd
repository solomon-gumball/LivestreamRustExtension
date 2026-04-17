class_name WsSessionBase
extends Node

@export var autojoin: bool = true
@export var current_lobby_id: String = ""  # Will create a new lobby if empty.
@export var mesh: bool = false  # Will use the lobby host as relay otherwise.

signal lobby_joined(lobby: String)
signal connected(id: int, use_mesh: bool)

# Peer leaves lobby (explicitly or by terminating ws connection)
signal disconnected()

# Some other peer joined lobby and wants to establish webRTC connection
signal peer_joined(id: int)

# Some other peer left lobby (explicitly or by terminating ws connection)
signal peer_disconnected(id: int)

# We have an SDP offer from the given peer, which should be sent to the WebRTC connection.
signal offer_received(id: int, offer: String)

# We have an SDP answer from the given peer, which should be sent to the WebRTC connection.
signal answer_received(id: int, answer: String)

# We have a new ICE candidate from the given peer, which should be sent to the WebRTC connection.
signal candidate_received(id: int, mid: String, index: int, sdp: String)

signal lobbies_updated(lobbies: Array[Lobby])
signal current_lobby_updated(lobby: Lobby)
signal lobby_sealed()

var all_lobbies: Dictionary[String, Lobby] = {}

func current_lobby() -> Lobby:
  return all_lobbies.get(current_lobby_id, null)

func handle_ws_message(parsed: Variant) -> bool:
  if typeof(parsed) != TYPE_DICTIONARY:
    return false
  var msg: Dictionary = parsed
  var type: String = msg.get("type", "")
  if type.is_empty():
    return false
  
  match type:
    "rtc-peer-id":
      connected.emit(int(msg.get("peer_id", 0)), bool(msg.get("mesh_mode", false)))
    "rtc-lobby-joined":
      current_lobby_id = str(msg.get("lobby_name", ""))
      lobby_joined.emit(current_lobby_id)
    "rtc-lobby-sealed":
      lobby_sealed.emit()
    "rtc-peer-joined":
      peer_joined.emit(int(msg.get("peer_id", 0)))
    "rtc-peer-disconnected":
      peer_disconnected.emit(int(msg.get("peer_id", 0)))
    "rtc-offer":
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
    "rtc-lobbies-updated":
      var prev_lobby = current_lobby()
      var lobbies: Array[Lobby] = []
      for lobby_data in msg.get("lobbies", []):
        lobbies.append(Lobby.from_data(lobby_data))
      all_lobbies = {}
      for lobby in lobbies:
        all_lobbies[lobby.name] = lobby
      lobbies_updated.emit(lobbies)
      var new_lobby = current_lobby()
      # TODO: Fix this equivalence check
      if prev_lobby != new_lobby:
        current_lobby_updated.emit()
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
  return Network.send_socket_message({ "type": "rtc-offer", "dest_peer_id": id, "sdp": offer })

func send_answer(id: int, answer: String) -> Error:
  return Network.send_socket_message({ "type": "rtc-answer", "dest_peer_id": id, "sdp": answer })
