class_name GameDebugOverlay
extends CanvasLayer

@onready var client_id_label: RichTextLabel = %ClientIdLabel
@onready var chatter_name_label: RichTextLabel = %ChatterNameLabel
@onready var ping_label: RichTextLabel = %PingLabel
@onready var peer_role_label: RichTextLabel = %PeerRoleLabel
@onready var sim_tick_label: RichTextLabel = %SimTickLabel

func _ready() -> void:
  MultiplayerClient.state.changed.connect(_update_all)
  SessionSynchronizer.get_instance().rtt_updated.connect(_rtt_updated)
  MultiplayerClient.connected_state.lobby_updated.connect(_update_role_label)

  _update_all(MultiplayerClient.state.current)

func _exit_tree() -> void:
  MultiplayerClient.state.changed.disconnect(_update_all)
  # SessionSynchronizer.get_instance().rtt_updated.disconnect(_rtt_updated)
  MultiplayerClient.connected_state.lobby_updated.disconnect(_update_role_label)

func _update_all(_state: Variant = null) -> void:
  _update_client_id_label()
  _update_chatter_label(WSClient.my_chatter())
  _update_role_label()

func _update_client_id_label() -> void:
  var peer_id := MultiplayerClient.my_peer_id()
  client_id_label.text = "[color=cyan]PEER ID: %d[/color]" % peer_id

func _update_chatter_label(chatter: Chatter) -> void:
  if chatter:
    chatter_name_label.text = "[color=white]%s[/color]" % chatter.display_name
  else:
    chatter_name_label.text = "[color=gray]UNKNOWN[/color]"

func _rtt_updated(msec_ping: float, prediction_tick_offset: int) -> void:
  ping_label.text = "[color=yellow]PING: %dms[/color]" % msec_ping
  sim_tick_label.text = "[color=pink]TICK +%d (+%dms)[/color]" % [prediction_tick_offset, float(prediction_tick_offset) / float(SessionSynchronizer.TICK_RATE_HZ) * 1000.0]

func _update_role_label() -> void:
  var lobby := MultiplayerClient.current_lobby
  if lobby == null:
    peer_role_label.text = "[color=gray]NOT IN LOBBY[/color]"
    return

  var my_chatter_id := WSClient.my_chatter().id if WSClient.my_chatter() else ""
  var is_host := lobby.host_chatter_id == my_chatter_id

  var my_peer: Lobby.PeerData = null
  for peer in lobby.peers:
    if peer.chatter_id == my_chatter_id:
      my_peer = peer
      break

  if is_host:
    peer_role_label.text = "[color=gold]HOST[/color]"
  elif my_peer == null:
    peer_role_label.text = "[color=gray]NOT IN LOBBY[/color]"
  elif my_peer.is_player:
    peer_role_label.text = "[color=green]PLAYER[/color]"
  else:
    peer_role_label.text = "[color=yellow]SPECTATING[/color]"
