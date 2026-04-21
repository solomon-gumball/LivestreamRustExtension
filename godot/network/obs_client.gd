extends Node

var obs_ws: WebSocketPeer = null

func _ready() -> void:
  if DebugScreenLayout.is_stream_overlay:
    return
  
  obs_ws = WebSocketPeer.new()
  var result = obs_ws.connect_to_url("ws://localhost:4455")

  if result != OK:
    print("Failed to connect to OBS WebSocket: ", result)
    return

# func 

func _process(delta: float) -> void:
  obs_ws.poll()

  # var ready_state = obs_ws.get_ready_state()
  # match ready_state:
  #   WebSocketPeer.STATE_OPEN:
  #     # while obs_ws.get_available_packet_count() > 0:
  #     #   var parsed = JSON.parse_string(obs_ws.get_packet().get_string_from_utf8())
  #     #   if parsed is Array:
  #     #     for message in parsed:
  #     #       state.current.handle_remote_message(message)
  #     #   else:
  #     #     state.current.handle_remote_message(parsed)

  #   WebSocketPeer.STATE_CLOSING:
  #     pass
  #   WebSocketPeer.STATE_CLOSED:
  #     pass
