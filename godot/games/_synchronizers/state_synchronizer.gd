class_name StateSynchronizer
extends Node

var state: Variant

@export var channel_id: String = ""

func _ready() -> void:
  MultiplayerClient.packet_received.connect(_handle_peer_packet)
  if !MultiplayerClient.is_lobby_host():
    MultiplayerClient.send_packet({
      "channel_id": channel_id,
      "type": SessionSynchronizer.GlobalGameMessage.ClientReady
    })

func _send_refresh_state(peer_id: int) -> void:
  MultiplayerClient.send_packet({
      "type": SessionSynchronizer.GlobalGameMessage.StateSyncRefreshState,
      "state": state
    },
    peer_id,
    MultiplayerPeer.TRANSFER_MODE_RELIABLE,
  )

func _handle_peer_packet(sender_id: int, packet: Dictionary) -> void:
  if packet.get("channel_id", null) != channel_id: return

  match packet.type:
    SessionSynchronizer.GlobalGameMessage.StateSyncRefreshState:
      state = packet.get("state")
    SessionSynchronizer.GlobalGameMessage.ClientReady:
      _send_refresh_state(sender_id)

  message_received(sender_id, packet)

# func send_packet(
#   packet: Dictionary,
#   target_peer: int = MultiplayerPeer.TARGET_PEER_BROADCAST,
#   transfer_mode: int = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED,
#   self_mode: PacketSelfMode = PacketSelfMode.NoSelf
# ) -> void:
#   packet.c
#   MultiplayerClient.se

func message_received(_sender_id: int, _packet: Dictionary) -> void:
  pass