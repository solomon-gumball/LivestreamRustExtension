extends Node

@export var mesh: bool = false

signal current_lobby_updated(lobby: Lobby)
signal packet_received(id: int, packet: Dictionary)
@warning_ignore("UNUSED_SIGNAL")
signal rtc_peer_ready(peer: int)

var state: StateMachine
var disconnected_state: Disconnected
var looking_for_lobby_state: LookingForLobby
var connected_state: Connected

var all_lobbies: Dictionary[String, Lobby] = {}

var current_lobby: Lobby = null:
  set(val):
    current_lobby = val
    current_lobby_updated.emit(val)

var rtc_mp := WebRTCMultiplayerPeer.new()

const PRINT_DEBUG: bool = false
const RELAY_ONLY_CANDIDATES: bool = true

enum GlobalNetCommand {
  Ping = 1000, Pong
}

func _ready() -> void:
  get_tree().multiplayer_poll = false

  state = StateMachine.new()
  add_child(state)

  disconnected_state = Disconnected.new(self)
  looking_for_lobby_state = LookingForLobby.new(self)
  connected_state = Connected.new(self)

  state.add_child(disconnected_state)
  state.add_child(looking_for_lobby_state)
  state.add_child(connected_state)

  WSClient.authenticated_state.message_received.connect(_handle_ws_message)

  looking_for_lobby_state.entered_lobby.connect(state.change_state.bind(connected_state))
  connected_state.left_lobby.connect(func() -> void:
    state.change_state(looking_for_lobby_state)
  )
  WSClient.state.changed.connect(_ws_connection_changed)
  state.change_state(disconnected_state)

func is_lobby_host() -> bool:
  if state.current is not Connected:
    print("ALERT! Called is_lobby_host when no lobby!")
    return false
  return current_lobby.host_chatter_id == WSClient.my_chatter().id

func _ws_connection_changed(status: WSClient.WSClientState) -> void:
  if status is WSClient.DisconnectedState:
    state.change_state(disconnected_state)

func search_for_lobbies() -> void:
  state.change_state(looking_for_lobby_state)

func stop() -> void:
  state.change_state(disconnected_state)

func leave_lobby() -> void:
  if current_lobby:
    WSClient.send_socket_message({
      "type": "rtc-leave-lobby",
      "lobby_id": current_lobby.name
    })
    search_for_lobbies()

func start_lobby() -> void:
  if MultiplayerClient.current_lobby:
    print("Sending start lobby message for lobby: ")
    WSClient.send_socket_message({
      "type": "rtc-start-game",
      "lobby_id": MultiplayerClient.current_lobby.name
    })

func _handle_ws_message(parsed: Variant) -> bool:
  if typeof(parsed) != TYPE_DICTIONARY:
    return false
  var msg: Dictionary = parsed
  var type: String = msg.get("type", "")
  if type.is_empty() or not type.begins_with("rtc-"):
    return false
  if state.current:
    state.current.handle_ws_message(type, msg)
  return true

func join_lobby(lobby_name: String) -> Error:
  if lobby_name.is_empty():
    # Prevent LookingForLobby from auto-joining the lobby we just created
    # when the server broadcasts rtc-lobbies-updated
    looking_for_lobby_state.join_request_already_sent = true

    return WSClient.send_socket_message({
      "type": "rtc-create-lobby",
      "mesh_mode": mesh
    })
  else:
    return WSClient.send_socket_message({
      "type": "rtc-join-lobby",
      "lobby_name": lobby_name
    })

func seal_lobby() -> Error:
  return WSClient.send_socket_message({ "type": "rtc-seal-lobby" })

func send_candidate(id: int, mid: String, index: int, sdp: String) -> Error:
  return WSClient.send_socket_message({
    "type": "rtc-candidate",
    "dest_peer_id": id,
    "candidate": "%s\n%d\n%s" % [mid, index, sdp]
  })

func send_offer(id: int, offer: String) -> Error:
  return WSClient.send_socket_message({
    "type": "rtc-offer",
    "dest_peer_id": id,
    "sdp": offer
  })

func send_answer(id: int, answer: String) -> Error:
  return WSClient.send_socket_message({
    "type": "rtc-answer",
    "dest_peer_id": id,
    "sdp": answer
  })

func send_packet(
  packet: Dictionary,
  target_peer: int = MultiplayerPeer.TARGET_PEER_BROADCAST,
  transfer_mode: int = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED,
  call_self: bool = false
) -> void:
  if not current_lobby:
    if PRINT_DEBUG: print("Can't send packet, not in lobby")
    return
  if not is_net_connected():
    if PRINT_DEBUG: print("Attempting to send packet while not connected")
    return
  
  var serialized: Variant = BinarySerializer.serialize_var(packet)
  var packet_data := var_to_bytes(serialized)

  # var packet_data: PackedByteArray = var_to_bytes_with_objects(packet)
  rtc_mp.set_target_peer(target_peer)
  rtc_mp.set_transfer_mode(transfer_mode)
  rtc_mp.put_packet(packet_data)

  if call_self:
    packet_received.emit(rtc_mp.get_unique_id(), packet)

func is_net_connected() -> bool:
  return rtc_mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

var is_rtc_connected: bool:
  get: return rtc_mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func my_peer_id() -> int:
  if rtc_mp.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
    return -1
  return rtc_mp.get_unique_id()

func is_authority() -> bool:
  return rtc_mp.get_unique_id() == 1

func is_initialized() -> bool:
  return rtc_mp.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED

func _process(_delta: float) -> void:
  rtc_mp.poll()
  while rtc_mp.get_available_packet_count() > 0:
    var sender_id: int = rtc_mp.get_packet_peer()
    var data: PackedByteArray = rtc_mp.get_packet()

    var message_var: Variant = bytes_to_var(data)
    var message: Variant = BinarySerializer.deserialize_var(message_var)

    state.current.handle_rtc_message(message, sender_id)
    packet_received.emit(sender_id, message)

class MultiplayerClientState extends State:
  var mc: MultiplayerClient

  func _init(_mc: MultiplayerClient) -> void:
    mc = _mc
  func handle_ws_message(_type: String, _msg: Dictionary) -> void:
    pass
  func handle_rtc_message(_message: Variant, _sender_id: int) -> void:
    pass

class Disconnected extends MultiplayerClientState:
  func enter_state(_previous_state: State) -> void:
    mc.current_lobby = null
    mc.all_lobbies = {}

class LookingForLobby extends MultiplayerClientState:
  signal entered_lobby
  signal lobby_list_updated(lobbies: Array[Lobby])

  var join_request_already_sent: bool = false
  var peer_id: int
  var mesh_mode: bool
  var lobby_to_join: Lobby

  func enter_state(_previous_state: State) -> void:
    join_request_already_sent = false
    mc.current_lobby = null
    mc.all_lobbies = {}
    WSClient.send_socket_message({ "type": "rtc-fetch-lobbies" })

  func handle_ws_message(type: String, msg: Dictionary) -> void:
    match type:
      "rtc-peer-joined":
        assert(false, "Should not receive peer-joined in lookingforlobby state!!")
      "rtc-lobbies-updated":
        if join_request_already_sent:
          return
        var lobbies: Array[Lobby] = []
        for lobby_data in msg.get("lobbies", []):
          lobbies.append(Lobby.from_data(lobby_data))
        mc.all_lobbies = {}
        for lobby in lobbies:
          mc.all_lobbies[lobby.name] = lobby

        if lobbies.size() > 0:
          join_request_already_sent = true
          lobby_list_updated.emit(lobbies)
          # mc.join_lobby(lobbies[0].name)
      "rtc-peer-id":
        peer_id = int(msg.get("peer_id", 0))
        mesh_mode = bool(msg.get("mesh_mode", false))
        lobby_to_join = Lobby.from_data(msg.get("lobby"))
        entered_lobby.emit()

class Connected extends MultiplayerClientState:
  var ping_timer: Timer
  var _offer_sent: Dictionary = {}

  signal left_lobby
  signal lobby_updated
  signal ping_check_completed(new_ping_ms: float)

  func _ready() -> void:
    ping_timer = Timer.new()
    ping_timer.autostart = false
    ping_timer.one_shot = false
    ping_timer.timeout.connect(_check_ping)
    add_child(ping_timer)
  
  func _init_client(id: int, use_mesh: bool) -> void:
    var is_server := id == 1
    if mc.PRINT_DEBUG: print("Connected %d (server=%s), mesh: %s" % [id, is_server, use_mesh])
    if use_mesh:
      mc.rtc_mp.create_mesh(id)
    elif is_server:
      mc.rtc_mp.create_server()
    else:
      mc.rtc_mp.create_client(id)
    mc.rtc_mp.peer_connected.connect(func(peer):
      mc.rtc_peer_ready.emit(peer)
    )
    mc.rtc_mp.peer_disconnected.connect(func(peer):
      _remove_peer(peer)
    )
    mc.multiplayer.multiplayer_peer = mc.rtc_mp

  func enter_state(_previous_state: State) -> void:
    if _previous_state is LookingForLobby:
      _close_rtc()
      _init_client(_previous_state.peer_id, _previous_state.mesh_mode)
      mc.current_lobby = _previous_state.lobby_to_join

    _check_ping()
    ping_timer.start(5.0)
  
  func exit_state() -> void:
    _close_rtc()

  func _check_ping() -> void:
    if not mc.is_authority():
      mc.send_packet({
        "type": MultiplayerClient.GlobalNetCommand.Ping,
        "sent_at": Time.get_ticks_msec()
      }, MultiplayerPeer.TARGET_PEER_SERVER)

  func _create_peer(id: int) -> WebRTCPeerConnection:
    var peer: WebRTCPeerConnection = WebRTCPeerConnection.new()
    peer.session_description_created.connect(_offer_created.bind(id))
    peer.ice_candidate_created.connect(_new_ice_candidate.bind(id))
    peer.initialize({
      "iceServers": [
        { "urls": ["stun:stun.l.google.com:19302"] },
        {
          "urls": ["turn:34.125.221.69:3478"],
          "username": WSClient.authenticated_state.turn_credentials.get("username", ""),
          "credential": WSClient.authenticated_state.turn_credentials.get("password", "")
        }
      ]
    })
    mc.rtc_mp.add_peer(peer, id)

    # Ensure offers only go one way
    if id < mc.rtc_mp.get_unique_id():
      # Create an offer to this peer
      peer.create_offer()
    return peer

  func _new_ice_candidate(mid_name: String, index_name: int, sdp_name: String, id: int) -> void:
    if mc.PRINT_DEBUG: print("Created a new ice candidate to send to peer %d: %s %d %s" % [id, mid_name, index_name, sdp_name])
    if mc.RELAY_ONLY_CANDIDATES and "typ relay" not in sdp_name:
      return
    
    mc.send_candidate(id, mid_name, index_name, sdp_name)

  func _offer_created(type: String, data: String, id: int) -> void:
    if mc.PRINT_DEBUG: print("offer created: %d: %s" % [id, type])
    if not mc.rtc_mp.has_peer(id):
      return
    mc.rtc_mp.get_peer(id).connection.set_local_description(type, data)
    if type == "offer":
      if _offer_sent.get(id, false):
        if mc.PRINT_DEBUG: print("duplicate offer for %d, skipping" % id)
        return
      _offer_sent[id] = true
      mc.send_offer(id, data)
    else:
      mc.send_answer(id, data)

  func _remove_peer(id: int) -> void:
    _offer_sent.erase(id)
    if mc.rtc_mp.has_peer(id):
      mc.rtc_mp.remove_peer(id)
    
    # If host leaves, disconnect
    if id == 1:
      print(mc.my_peer_id(), ' noticed host DID LEAVE!!')
      left_lobby.emit()

  func _offer_received(id: int, offer: String) -> void:
    if mc.PRINT_DEBUG: print("%d received offer event from: %d" % [mc.rtc_mp.get_unique_id(), id])
    if mc.rtc_mp.has_peer(id):
      mc.rtc_mp.get_peer(id).connection.set_remote_description("offer", offer)
    else:
      print(mc.rtc_mp.get_unique_id(), " MISSED AN OFFER FROM ", id)

  func _answer_received(id: int, answer: String) -> void:
    if mc.PRINT_DEBUG: print("%d received answer event from: %d" % [mc.rtc_mp.get_unique_id(), id])
    if mc.rtc_mp.has_peer(id):
      mc.rtc_mp.get_peer(id).connection.set_remote_description("answer", answer)
    else:
      print(mc.rtc_mp.get_unique_id(), " MISSED AN ANSWER FROM ", id)

  func _candidate_received(id: int, mid: String, index: int, sdp: String) -> void:
    if mc.PRINT_DEBUG: print("%d received candidate event from: %d" % [mc.rtc_mp.get_unique_id(), id])
    if mc.rtc_mp.has_peer(id):
      mc.rtc_mp.get_peer(id).connection.add_ice_candidate(mid, index, sdp)
    else:
      print(mc.rtc_mp.get_unique_id(), " MISSED A CANDIDATE FROM ", id)

  func _lobby_sealed() -> void:
    mc.sealed = true
  
  func _close_rtc() -> void:
    mc.multiplayer.multiplayer_peer = null
    mc.connected_state.ping_timer.stop()
    mc.rtc_mp.close()
    # In Godot, close() on a WebRTCMultiplayerPeer doesn't fully reset
    # it for reuse — create_client() has an internal guard
    # (ERR_FAIL_COND_V(network_mode != MODE_NONE, ...)) that silently fails
    # if the mode wasn't cleanly reset, leaving the peer stuck in its old
    # MODE_CLIENT state. Then when _peer_joined fires with a non-1 ID
    # (any peer other than the host), add_peer rejects it.
    mc.rtc_mp = WebRTCMultiplayerPeer.new()
    mc.connected_state._offer_sent.clear()
  
  func _update_peers_for_lobby(lobby: Lobby) -> void:
    var lobby_connected_peer_ids: Array[int] = []
    var my_peer_id = mc.my_peer_id()
    for peer in lobby.connected_peers():
      lobby_connected_peer_ids.append(peer.peer_id)

    var existing_peers := mc.rtc_mp.get_peers()
    for existing_peer: int in existing_peers.keys():
      if existing_peer == my_peer_id: continue
      if !lobby_connected_peer_ids.has(existing_peer):
        print(mc.my_peer_id(), " IS REMOVING PEER ", existing_peer)
        _remove_peer(existing_peer)

    for peer in lobby_connected_peer_ids:
      if peer == my_peer_id: continue
      if !mc.rtc_mp.has_peer(peer):
        print(mc.my_peer_id(), " IS ADDING PEER ", peer)
        _create_peer(peer)

  func handle_rtc_message(message: Variant, sender_id: int) -> void:
    match message.type:
      MultiplayerClient.GlobalNetCommand.Ping:
        mc.send_packet({
          "type": MultiplayerClient.GlobalNetCommand.Pong,
          "sent_at": message.get("sent_at", 0)
        }, sender_id)
      MultiplayerClient.GlobalNetCommand.Pong:
        ping_check_completed.emit(Time.get_ticks_msec() - message.get("sent_at", 0))

  func handle_ws_message(type: String, msg: Dictionary) -> void:
    match type:
      "rtc-peer-id":
        assert(false, "Connected state received rtc-peer-id message, this should never happen")
      "rtc-lobby-joined":
        var current_lobby_id = str(msg.get("lobby_name", ""))
        mc.current_lobby = mc.all_lobbies.get(current_lobby_id)
        _update_peers_for_lobby(mc.current_lobby)
      "rtc-lobby-sealed":
        _lobby_sealed()
      "rtc-offer":
        _offer_received(int(msg.get("from_peer_id", 0)), str(msg.get("sdp", "")))
      "rtc-answer":
        _answer_received(int(msg.get("from_peer_id", 0)), str(msg.get("sdp", "")))
      "rtc-candidate":
        var from_id: int = int(msg.get("from_peer_id", 0))
        var parts: PackedStringArray = str(msg.get("candidate", "")).split("\n", false)
        if parts.size() != 3 or not parts[1].is_valid_int():
          return
        _candidate_received(from_id, parts[0], parts[1].to_int(), parts[2])
      "rtc-lobbies-updated":
        var lobbies: Array[Lobby] = []
        for lobby_data in msg.get("lobbies", []):
          lobbies.append(Lobby.from_data(lobby_data))
        mc.all_lobbies = {}
        for lobby in lobbies:
          mc.all_lobbies[lobby.name] = lobby

        var updated: Lobby = null
        if mc.current_lobby != null:
          updated = mc.all_lobbies.get(mc.current_lobby.name)
          mc.current_lobby = updated
          lobby_updated.emit()
          if updated == null:
            left_lobby.emit()
        
        if mc.current_lobby:
          _update_peers_for_lobby(mc.current_lobby)
