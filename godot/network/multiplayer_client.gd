extends Node
class_name MultiplayerClient

@export var autojoin: bool = true
@export var current_lobby_id: String = ""  # Will create a new lobby if empty.
@export var mesh: bool = false  # Will use the lobby host as relay otherwise.

signal lobby_joined(lobby: String)
signal disconnected()
signal lobbies_updated(lobbies: Array[Lobby])
signal current_lobby_updated(lobby: Lobby)

signal packet_received(id: int, packet: Dictionary)
signal rtc_peer_ready(peer_id: int)

@onready var connection_state: StateMachine
@onready var looking_for_lobby_state: LookingForLobbyState
@onready var disconnected_state: DisconnectedState

var current_lobby: Lobby = null

var rtc_mp := WebRTCMultiplayerPeer.new()
var sealed: bool = false

func _init() -> void:
  disconnected.connect(_disconnected)

var ping_timer: Timer

func _ready() -> void:
  get_tree().multiplayer_poll = false

  ping_timer = Timer.new()
  ping_timer.autostart = false
  ping_timer.one_shot = false
  ping_timer.timeout.connect(_check_ping)
  add_child(ping_timer)

  connection_state = StateMachine.new()
  looking_for_lobby_state = LookingForLobbyState.new(self)
  disconnected_state = DisconnectedState.new(self)

  add_child(connection_state)
  connection_state.add_child(looking_for_lobby_state)
  connection_state.add_child(disconnected_state)

  connection_state.change_state(disconnected_state)

  looking_for_lobby_state.lobby_joined.connect(connection_state.change_state.bind(join_lobby))

func stop() -> void:
  multiplayer.multiplayer_peer = null
  ping_timer.stop()
  rtc_mp.close()

  # In Godot, close() on a WebRTCMultiplayerPeer doesn't fully reset
  # it for reuse — create_client() has an internal guard
  # (ERR_FAIL_COND_V(network_mode != MODE_NONE, ...)) that silently fails
  # if the mode wasn't cleanly reset, leaving the peer stuck in its old
  # MODE_CLIENT state. Then when _peer_joined fires with a non-1 ID
  # (any peer other than the host), add_peer rejects it.

  rtc_mp = WebRTCMultiplayerPeer.new()
  _offer_sent.clear()

func _create_peer(id: int) -> WebRTCPeerConnection:
  var peer: WebRTCPeerConnection = WebRTCPeerConnection.new()

  peer.initialize({
    "iceServers": [
      { "urls": ["stun:stun.l.google.com:19302"] },
      {
        "urls": ["turn:34.125.221.69:3478"],
        "username": Network.turn_credentials.get("username", ""),
        # "credential": "incorrectpasswordtest",
        "credential": Network.turn_credentials.get("password", "")
      }
    ]
  })

  peer.session_description_created.connect(_offer_created.bind(id))
  peer.ice_candidate_created.connect(_new_ice_candidate.bind(id))
  rtc_mp.add_peer(peer, id)

  if id < rtc_mp.get_unique_id(): # Ensure
    # Send an offer to this peer
    peer.create_offer()
  return peer

var relay_only_candidates: bool = true
const PRINT_DEBUG: bool = false

func _new_ice_candidate(mid_name: String, index_name: int, sdp_name: String, id: int) -> void:
  if PRINT_DEBUG: print("new ice candidate: %d: %s %d %s" % [id, mid_name, index_name, sdp_name])
  if relay_only_candidates and "typ relay" not in sdp_name:
    return
  send_candidate(id, mid_name, index_name, sdp_name)

var _offer_sent: Dictionary = {}  # id -> bool

func _offer_created(type: String, data: String, id: int) -> void:
  if PRINT_DEBUG: print("offer created: %d: %s" % [id, type])
  if not rtc_mp.has_peer(id):
      return
  rtc_mp.get_peer(id).connection.set_local_description(type, data)
  if type == "offer":
      if _offer_sent.get(id, false):
          if PRINT_DEBUG: print("duplicate offer for %d, skipping" % id)
          return
      _offer_sent[id] = true
      send_offer(id, data)
  else:
      send_answer(id, data)

func handle_ws_message(parsed: Variant) -> bool:
  if typeof(parsed) != TYPE_DICTIONARY:
    return false
  var msg: Dictionary = parsed
  var type: String = msg.get("type", "")
  if type.is_empty():
    return false
  
  if connection_state.current:
    connection_state.current.process_message(type, msg)

  # match type:
  #   "rtc-peer-id":
  #     _connected(int(msg.get("peer_id", 0)), bool(msg.get("mesh_mode", false)))
  #   "rtc-lobby-joined":
  #     current_lobby_id = str(msg.get("lobby_name", ""))
  #     lobby_joined.emit(current_lobby_id)
  #   "rtc-lobby-sealed":
  #     _lobby_sealed()
  #   "rtc-peer-joined":
  #     _peer_joined(int(msg.get("peer_id", 0)))
  #   "rtc-peer-disconnected":
  #     _peer_disconnected(int(msg.get("peer_id", 0)))
  #   "rtc-offer":
  #     _offer_received(int(msg.get("from_peer_id", 0)), str(msg.get("sdp", "")))
  #   "rtc-answer":
  #     _answer_received(int(msg.get("from_peer_id", 0)), str(msg.get("sdp", "")))
  #   "rtc-candidate":
  #     var from_id: int = int(msg.get("from_peer_id", 0))
  #     var parts: PackedStringArray = str(msg.get("candidate", "")).split("\n", false)
  #     if parts.size() != 3:
  #       return false
  #     if not parts[1].is_valid_int():
  #       return false
  #     _candidate_received(from_id, parts[0], parts[1].to_int(), parts[2])
  #   "rtc-lobbies-updated":
  #     var prev_lobby = current_lobby()
  #     var lobbies: Array[Lobby] = []
  #     for lobby_data in msg.get("lobbies", []):
  #       lobbies.append(Lobby.from_data(lobby_data))
  #     all_lobbies = {}
  #     for lobby in lobbies:
  #       all_lobbies[lobby.name] = lobby
  #     lobbies_updated.emit(lobbies)
  #     var new_lobby = current_lobby()
  #     # TODO: Fix this equivalence check
  #     if prev_lobby != new_lobby:
  #       current_lobby_updated.emit()
  #   _:
  #     return false

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

func _peer_disconnected(id: int) -> void:
  _offer_sent.erase(id)
  if rtc_mp.has_peer(id):
      rtc_mp.remove_peer(id)

func _connected(id: int, use_mesh: bool) -> void:
  var is_server := id == 1
  if PRINT_DEBUG: print("Connected %d (server=%s), mesh: %s" % [id, is_server, use_mesh])
  if use_mesh:
    rtc_mp.create_mesh(id)
  elif is_server:
    rtc_mp.create_server()
  else:
    rtc_mp.create_client(id)

  rtc_mp.peer_connected.connect(func(peer_id): rtc_peer_ready.emit(peer_id))

  _check_ping()
  ping_timer.start(5.0)
  multiplayer.multiplayer_peer = rtc_mp

func _lobby_sealed() -> void:
  sealed = true

func _disconnected() -> void:
  sealed = false
  stop()

func _peer_joined(id: int) -> void:
  _create_peer(id)

func _offer_received(id: int, offer: String) -> void:
  if rtc_mp.has_peer(id):
    rtc_mp.get_peer(id).connection.set_remote_description("offer", offer)

func _answer_received(id: int, answer: String) -> void:
  if rtc_mp.has_peer(id):
    rtc_mp.get_peer(id).connection.set_remote_description("answer", answer)

func _candidate_received(id: int, mid: String, index: int, sdp: String) -> void:
  if rtc_mp.has_peer(id):
    rtc_mp.get_peer(id).connection.add_ice_candidate(mid, index, sdp)

func send_packet(
  packet: Dictionary,
  target_peer: int = MultiplayerPeer.TARGET_PEER_BROADCAST,
  transfer_mode: int = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
) -> void:

  if not current_lobby:
    if PRINT_DEBUG: print("Can't send packet, not in lobby")
    return
  if !is_net_connected():
    if PRINT_DEBUG: print("Attempting to send packet while not connected")
    return

  var packet_data: PackedByteArray = var_to_bytes_with_objects(packet)
  rtc_mp.set_target_peer(target_peer)
  rtc_mp.set_transfer_mode(transfer_mode)
  rtc_mp.put_packet(packet_data)

enum GlobalNetCommand {
  Ping = 1000, Pong
}

func is_net_connected() -> bool:
  return rtc_mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func my_peer_id() -> int:
  # if is_net_connected():
    return rtc_mp.get_unique_id()
  # return -1

func is_authority() -> bool:
  return rtc_mp.get_unique_id() == 1

func is_initialized() -> bool:
  return rtc_mp.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED

func _check_ping() -> void:
  if !is_authority():
    send_packet({
      "type": GlobalNetCommand.Ping,
      "sent_at": Time.get_ticks_msec()
    }, MultiplayerPeer.TARGET_PEER_SERVER)

signal ping_check_completed(new_ping_ms: float)

func _process(_delta):
  rtc_mp.poll()

  while rtc_mp.get_available_packet_count() > 0:
    var sender_id: int = rtc_mp.get_packet_peer()
    var data: PackedByteArray = rtc_mp.get_packet()
    var message: Variant = bytes_to_var_with_objects(data)

    match message.type:
      GlobalNetCommand.Ping:
        send_packet({
          "type": GlobalNetCommand.Pong,
          "sent_at": message.get("sent_at", 0)
        }, sender_id)
      GlobalNetCommand.Pong:
        ping_check_completed.emit(Time.get_ticks_msec() - message.get("sent_at", 0))

    packet_received.emit(sender_id, message)

class RTCConnectionState extends State:
  var mc: MultiplayerClient
  func _init(_mc: MultiplayerClient):
    mc = _mc
  
  func process_message(type: String, _msg: Dictionary) -> void:
    assert(false, "process_message not implemented for type %s in state %s" % [type, self])

class DisconnectedState extends RTCConnectionState:
  func enter_state(_previous_state: State) -> void:
    mc.current_lobby = null
    mc.all_lobbies = {}

class LookingForLobbyState extends RTCConnectionState:
  var all_lobbies: Dictionary[String, Lobby] = {}
  signal lobby_joined()

  func enter_state(_previous_state: State) -> void:
    mc.current_lobby = null
    mc.all_lobbies = {}
    Network.send_socket_message({ "type": "rtc-fetch-lobbies" })

  func process_message(type: String, msg: Dictionary) -> void:
    match type:
      "rtc-lobbies-updated":
        var lobbies: Array[Lobby] = []
        for lobby_data in msg.get("lobbies", []):
          lobbies.append(Lobby.from_data(lobby_data))
        if lobbies.size() > 0:
          mc.current_lobby = lobbies[0]
          lobby_joined.emit()

class JoiningLobbyState extends RTCConnectionState:
  func process_message(type: String, msg: Dictionary) -> void:
    assert(mc.current_lobby != null, "Current lobby should always be valid in this state")
    # match type:
    #   "rtc-lobbies-updated":
        # Should handle updating the lobby and updating a signal for this

    # This will likely handle a lot of the same events as ConnectedToLobbyState
    pass

class ConnectedToLobbyState extends RTCConnectionState:
  func process_message(type: String, msg: Dictionary) -> void:
    assert(mc.current_lobby != null, "Current lobby should always be valid in this state")
