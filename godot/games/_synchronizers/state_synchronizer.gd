class_name StateSynchronizer
extends Node

var state: Variant

signal state_updated

@export var channel_id: String = ""

func _ready() -> void:
  MultiplayerClient.packet_received.connect(_handle_peer_packet)
  if !MultiplayerClient.is_lobby_host():
    MultiplayerClient.send_packet({
      "channel_id": channel_id,
      "type": SessionSynchronizer.GlobalGameMessage.StateSyncClientReady
    })

func send_refresh_state(peer_id: int) -> void:
  MultiplayerClient.send_packet({
      "channel_id": channel_id,
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
    SessionSynchronizer.GlobalGameMessage.StateSyncClientReady:
      send_refresh_state(sender_id)

  message_received(sender_id, packet)
  state_updated.emit()

func send_packet(
  packet: Dictionary,
  target_peer: int = MultiplayerPeer.TARGET_PEER_BROADCAST,
  transfer_mode: int = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED,
  self_mode: MultiplayerClient.PacketSelfMode = MultiplayerClient.PacketSelfMode.NoSelf
) -> void:
  packet.set("channel_id", channel_id)
  MultiplayerClient.send_packet(packet, target_peer, transfer_mode, self_mode)

func message_received(_sender_id: int, _packet: Dictionary) -> void:
  pass
