extends WsSessionBase
class_name MultiplayerClient

var rtc_mp := WebRTCMultiplayerPeer.new()
var sealed: bool = false

# Player calls join lobby to create a new lobby on the server
# Server responds with "rtc-peer-id" which triggers the connected signal
# This signal 

signal packet_received(id: int, packet: Dictionary)

func _init() -> void:
  connected.connect(_connected)
  disconnected.connect(_disconnected)

  offer_received.connect(_offer_received)
  answer_received.connect(_answer_received)
  candidate_received.connect(_candidate_received)

  lobby_sealed.connect(_lobby_sealed)
  peer_connected.connect(_peer_connected)
  peer_disconnected.connect(_peer_disconnected)

var ping_timer: Timer

func _ready() -> void:
  get_tree().multiplayer_poll = false

  ping_timer = Timer.new()
  ping_timer.autostart = false
  ping_timer.one_shot = false
  ping_timer.timeout.connect(_check_ping)
  add_child(ping_timer)

func stop() -> void:
  multiplayer.multiplayer_peer = null
  ping_timer.stop()
  rtc_mp.close()

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

# We have a new ICE candidate from the WebRTC connection.
# This should be sent to every other peer.
func _new_ice_candidate(mid_name: String, index_name: int, sdp_name: String, id: int) -> void:
  if PRINT_DEBUG: print("new ice candidate: %d: %s %d %s" % [id, mid_name, index_name, sdp_name])
  if relay_only_candidates and "typ relay" not in sdp_name:
    return
  send_candidate(id, mid_name, index_name, sdp_name)

var _offer_sent: Dictionary = {}  # id -> bool

# We have an SDP document to send to the given peer. 
# If it's an offer, we need to send it to the server to relay to the peer.
# If it's an answer, we can send it directly to the peer.
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

func _peer_disconnected(id: int) -> void:
  print("Peer disconnected: %d" % id)
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
  
  _check_ping()
  ping_timer.start(5.0)
  multiplayer.multiplayer_peer = rtc_mp

func _lobby_sealed() -> void:
  sealed = true

func _disconnected() -> void:
  # print("Disconnected: %d: %s" % [code, reason])
  if not sealed:
    stop() # Unexpected disconnect

func _peer_connected(id: int) -> void:
  print("Peer connected: %d" % id)
  _create_peer(id)

# func _peer_disconnected(id: int) -> void:
#   if rtc_mp.has_peer(id):
#     rtc_mp.remove_peer(id)

func _offer_received(id: int, offer: String) -> void:
  # print("Got offer: %d" % id)
  if rtc_mp.has_peer(id):
    rtc_mp.get_peer(id).connection.set_remote_description("offer", offer)

func _answer_received(id: int, answer: String) -> void:
  # print("Got answer: %d" % id)
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

  if not current_lobby():
    if PRINT_DEBUG: print("Can't send packet, not in lobby")
    return
  if !is_net_connected():
    if PRINT_DEBUG: print("Attempting to send packet while not connected")
    return

  var packet_data: PackedByteArray = var_to_bytes(packet)
  rtc_mp.set_target_peer(target_peer)
  rtc_mp.set_transfer_mode(transfer_mode)
  rtc_mp.put_packet(packet_data)
  
enum GlobalNetCommand {
  Ping = 1000, Pong
}

func is_net_connected() -> bool:
  return rtc_mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func my_peer_id() -> int:
  if is_net_connected():
    return rtc_mp.get_unique_id()
  return -1

func is_authority() -> bool:
  return rtc_mp.get_unique_id() == 1

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
    var message := bytes_to_var(data)
  
    match message.type:
      GlobalNetCommand.Ping:
        send_packet({
          "type": GlobalNetCommand.Pong,
          "sent_at": message.get("sent_at", 0)
        }, sender_id)
      GlobalNetCommand.Pong:
        ping_check_completed.emit(Time.get_ticks_msec() - message.get("sent_at", 0))

    packet_received.emit(sender_id, message)
