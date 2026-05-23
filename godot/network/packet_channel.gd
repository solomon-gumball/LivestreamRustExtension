extends Node
class_name PacketChannel

@export var channel_id: String = ""

signal packet_received(sender_id: int, message: Dictionary)

func _ready() -> void:
  MultiplayerClient.packet_received.connect(_handle_peer_packet)

func _handle_peer_packet(sender_id: int, packet: Dictionary) -> void:
  if channel_id == "": return
  if packet.get("channel_id", null) != channel_id: return
  packet_received.emit(sender_id, packet)

func send_packet(
  packet: Dictionary,
  target_peer: int = MultiplayerPeer.TARGET_PEER_BROADCAST,
  transfer_mode: int = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED,
  self_mode: MultiplayerClient.PacketSelfMode = MultiplayerClient.PacketSelfMode.NoSelf
) -> void:
  packet.set("channel_id", channel_id)
  MultiplayerClient.send_packet(packet, target_peer, transfer_mode, self_mode)