class_name AnimationSynchronizer
extends StateSynchronizer

class AnimationState:
  var animation_name: String
  var started_at: float
  var skipped: bool = false

  func equals(other: AnimationState) -> bool:
    if other != null and\
      other.animation_name == animation_name and\
      other.started_at == started_at and\
      other.skipped == skipped:
      return true
    return false

var anim_state: AnimationState:
  get: return state as AnimationState
  set(v): state = v

@export var animation_player: AnimationPlayer:
  set(new_animation_player):
    if animation_player:
      animation_player.animation_finished.disconnect(animation_finished.emit)
    animation_player = new_animation_player
    if animation_player:
      animation_player.animation_finished.connect(animation_finished.emit)

func message_received(_sender_id: int, packet: Dictionary) -> void:
  match packet.type:
    SessionSynchronizer.GlobalGameMessage.UpdateAnimation:
      anim_state = AnimationState.new()
      anim_state.started_at = packet.get("started_at", 0)
      anim_state.animation_name = packet.get("animation_name", "")
      anim_state.skipped = packet.get("skipped", false)
  if anim_state:
    if !anim_state.equals(local_anim_state):
      _sync_animation_state()

signal animation_finished(animation_name: String)

var local_anim_state: AnimationState
func _sync_animation_state() -> void:
  local_anim_state = anim_state
  var animation_to_play := animation_player.get_animation(local_anim_state.animation_name)

  if animation_to_play == null:
    assert(false, "Attempted to play nonexistent animation %s" % local_anim_state.animation_name)

  var anim_elapsed_time: float = animation_to_play.length\
    if local_anim_state.skipped\
    else Time.get_unix_time_from_system() - anim_state.started_at

  animation_player.play(local_anim_state.animation_name)
  if anim_elapsed_time >= animation_to_play.length:
    animation_player.seek(animation_to_play.length, false)
    animation_player.advance(0.0)
    await get_tree().process_frame
    animation_player.advance(0.0)
    animation_finished.emit(local_anim_state.animation_name)
  else:
    animation_player.seek(anim_elapsed_time, true)

func authority_skip_current_animation() -> void:
  if !MultiplayerClient.is_lobby_host():
    assert(false, "ERROR: Non-host player called authority_skip_current_animation()!")

  if local_anim_state and !local_anim_state.skipped:
    send_packet(
      {
        "type": SessionSynchronizer.GlobalGameMessage.UpdateAnimation,
        "animation_name": local_anim_state.animation_name,
        "started_at": local_anim_state.started_at,
        "skipped": true
      },
      MultiplayerPeer.TARGET_PEER_BROADCAST,
      MultiplayerPeer.TRANSFER_MODE_RELIABLE,
      MultiplayerClient.PacketSelfMode.SelfIncluded
    )

func handle_animation_finished(_animation_name: String) -> void:
  pass

func authority_play_animation(animation_name: String) -> void:
  if !MultiplayerClient.is_lobby_host():
    assert(false, "ERROR: Non-host player called authority_play_animation()!")

  send_packet(
    {
      "type": SessionSynchronizer.GlobalGameMessage.UpdateAnimation,
      "animation_name": animation_name,
      "started_at": Time.get_unix_time_from_system(),
      "skipped": false
    },
    MultiplayerPeer.TARGET_PEER_BROADCAST,
    MultiplayerPeer.TRANSFER_MODE_RELIABLE,
    MultiplayerClient.PacketSelfMode.SelfIncluded
  )

func _unhandled_input(_event: InputEvent) -> void:
  if MultiplayerClient.is_lobby_host():
    if Input.is_key_pressed(KEY_ENTER):
      authority_skip_current_animation()
