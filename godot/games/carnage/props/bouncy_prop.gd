@tool
class_name BouncyProp
extends Node3D

enum Message {
  TriggerBounce
}

@export var static_body: StaticBody3D
@export var bounce_area: Area3D
@export var bounce_force: float = 3.0
@export var bounce_torque: float = 2.0
@export var mesh: MeshInstance3D
@onready var packet_channel: PacketChannel = %PacketChannel

@export var debug_bounce: bool = false:
  set(new_val):
    debug_bounce = new_val
    _trigger_bounce_animation()

const BOUNCE_COOLDOWN := 0.5
var _cooldowns: Dictionary = {}

func _ready() -> void:
  bounce_area.body_entered.connect(_on_bounce_area_body_entered)
  packet_channel.channel_id = name
  packet_channel.packet_received.connect(_handle_message)

func _handle_message(sender_id: int, packet: Dictionary) -> void:
  match packet.type:
    Message.TriggerBounce:
      _trigger_bounce_animation()

func _process(delta: float) -> void:
  for key in _cooldowns.keys():
    _cooldowns[key] -= delta
    if _cooldowns[key] <= 0.0:
      _cooldowns.erase(key)

func _on_bounce_area_body_entered(body: Node) -> void:
  if not body is PhysicsKart: return

  var kart := body as PhysicsKart
  var kart_id := kart.get_instance_id()
  if _cooldowns.has(kart_id):
    return
  _cooldowns[kart_id] = BOUNCE_COOLDOWN

  var away := (kart.global_position - global_position)
  away.y = 0.0
  away = away.normalized()

  var tilt_axis := away.cross(Vector3.UP).normalized()
  var impulse := away.rotated(tilt_axis, deg_to_rad(45)) * bounce_force
  var torque := -tilt_axis * bounce_torque
  kart.physics_kart_movement_sync.apply_impulse(impulse)
  kart.physics_kart_movement_sync.apply_torque_impulse(torque)

  packet_channel.send_packet(
    { "type": Message.TriggerBounce },
    MultiplayerPeer.TARGET_PEER_BROADCAST,
    MultiplayerPeer.TRANSFER_MODE_RELIABLE,
    MultiplayerClient.PacketSelfMode.SelfIncluded if MultiplayerClient.is_lobby_host() else MultiplayerClient.PacketSelfMode.SelfOnly
  )

  MultiplayerClient.send_packet({
      "type": Carnage.CarnageGameMessage.HandleKartPunched,
      "owner_peer_id": kart.physics_kart_movement_sync.owner_peer_id
    },
    MultiplayerPeer.TARGET_PEER_BROADCAST,
    MultiplayerPeer.TRANSFER_MODE_RELIABLE,
    MultiplayerClient.PacketSelfMode.SelfIncluded if MultiplayerClient.is_lobby_host() else MultiplayerClient.PacketSelfMode.SelfOnly
  )

func _trigger_bounce_animation() -> void:
  var tween := create_tween()
  tween.tween_property(mesh, "scale", Vector3(0.7, 1.3, 0.7), 0.05).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
  tween.tween_property(mesh, "scale", Vector3(1.3, 0.6, 1.3), 0.12).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
  tween.tween_property(mesh, "scale", Vector3.ONE, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CIRC)