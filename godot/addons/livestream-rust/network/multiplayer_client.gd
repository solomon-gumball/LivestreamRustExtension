extends WsSessionBase
class_name MultiplayerClient

var rtc_mp := WebRTCMultiplayerPeer.new()
var sealed: bool = false

func _init() -> void:
  connected.connect(_connected)
  disconnected.connect(_disconnected)

  offer_received.connect(_offer_received)
  answer_received.connect(_answer_received)
  candidate_received.connect(_candidate_received)

  lobby_joined.connect(_lobby_joined)
  lobby_sealed.connect(_lobby_sealed)
  peer_connected.connect(_peer_connected)
  peer_disconnected.connect(_peer_disconnected)

func start(url: String, _lobby: String = "", _mesh: bool = true) -> void:
  stop()
  sealed = false
  mesh = _mesh
  lobby = _lobby
  # connect_to_url(url)

func stop() -> void:
  multiplayer.multiplayer_peer = null
  rtc_mp.close()
  # close()

func _create_peer(id: int) -> WebRTCPeerConnection:
  var peer: WebRTCPeerConnection = WebRTCPeerConnection.new()

  # Use a public STUN server for moderate NAT traversal.
  # Note that STUN cannot punch through strict NATs (such as most mobile connections),
  # in which case TURN is required. TURN generally does not have public servers available,
  # as it requires much greater resources to host (all traffic goes through
  # the TURN server, instead of only performing the initial connection).
  peer.initialize({
    "iceServers": [ { "urls": ["stun:stun.l.google.com:19302"] } ]
  })
  peer.session_description_created.connect(_offer_created.bind(id))
  print("signal connected: ", peer.session_description_created.is_connected(_offer_created.bind(id)))

  peer.ice_candidate_created.connect(_new_ice_candidate.bind(id))
  rtc_mp.add_peer(peer, id)
  print("Creating peer: remote_id=%d, my_id=%d, will_offer=%s" % [id, rtc_mp.get_unique_id(), id < rtc_mp.get_unique_id()])
  if id < rtc_mp.get_unique_id():  # So lobby creator never creates offers.
    print("CREATING OFFER ", peer.create_offer())
  return peer

func _new_ice_candidate(mid_name: String, index_name: int, sdp_name: String, id: int) -> void:
  print("new ice candidate: %d: %s %d %s" % [id, mid_name, index_name, sdp_name])
  send_candidate(id, mid_name, index_name, sdp_name)

var _offer_sent: Dictionary = {}  # id -> bool

func _offer_created(type: String, data: String, id: int) -> void:
    print("offer created: %d: %s" % [id, type])
    if not rtc_mp.has_peer(id):
        return
    rtc_mp.get_peer(id).connection.set_local_description(type, data)
    if type == "offer":
        if _offer_sent.get(id, false):
            print("duplicate offer for %d, skipping" % id)
            return
        _offer_sent[id] = true
        send_offer(id, data)
    else:
        send_answer(id, data)

func _peer_disconnected(id: int) -> void:
    _offer_sent.erase(id)
    if rtc_mp.has_peer(id):
        rtc_mp.remove_peer(id)

func _connected(id: int, use_mesh: bool) -> void:
  var is_server := id == 1
  print("Connected %d (server=%s), mesh: %s" % [id, is_server, use_mesh])
  if use_mesh:
    rtc_mp.create_mesh(id)
  elif is_server:
    rtc_mp.create_server()
  else:
    rtc_mp.create_client(id)
  multiplayer.multiplayer_peer = rtc_mp

  multiplayer.peer_connected.connect(func(pid): print("RTC peer connected: ", pid))
  multiplayer.connected_to_server.connect(func(): print("RTC connected to server"))
  multiplayer.connection_failed.connect(func(): print("RTC connection FAILED"))

func _lobby_joined(_lobby: String) -> void:
  lobby = _lobby

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
  print("Got offer: %d" % id)
  if rtc_mp.has_peer(id):
    rtc_mp.get_peer(id).connection.set_remote_description("offer", offer)

func _answer_received(id: int, answer: String) -> void:
  print("Got answer: %d" % id)
  if rtc_mp.has_peer(id):
    rtc_mp.get_peer(id).connection.set_remote_description("answer", answer)

func _candidate_received(id: int, mid: String, index: int, sdp: String) -> void:
  if rtc_mp.has_peer(id):
    rtc_mp.get_peer(id).connection.add_ice_candidate(mid, index, sdp)

# func _process(_delta: float) -> void:
#   rtc_mp.poll()
