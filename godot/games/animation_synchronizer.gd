class_name AnimationSynchronizer
extends Node

@export var animation_player: AnimationPlayer:
  set(anim_player):
    animation_player = anim_player
    animation_player.animation_finished.connect(animation_finished.emit)

var state: AnimationState = null

func _ready() -> void:
  MultiplayerClient.packet_received.connect(_handle_peer_packet)
  MultiplayerClient.rtc_peer_ready.connect(_new_peer_ready)

func _new_peer_ready(peer_id: int) -> void:
  MultiplayerClient.send_packet({
      "type": GameBase.GlobalGameMessage.AnimationStateRefresh,
      "state": state
    },
    peer_id,
    MultiplayerPeer.TRANSFER_MODE_RELIABLE,
  )
  print("Sending updated action")

func _handle_peer_packet(_sender_id: int, packet: Dictionary) -> void:
  match packet.type:
    GameBase.GlobalGameMessage.ClientReady:
      _new_peer_ready(_sender_id)
    GameBase.GlobalGameMessage.UpdateAnimation:
      state = AnimationState.new()
      state.started_at = packet.get("started_at", 0)
      state.animation_name = packet.get("animation_name", "")
      state.skipped = packet.get("skipped", false)
    GameBase.GlobalGameMessage.AnimationStateRefresh:
      state = packet.get("state")
  if state:
    if !state.equals(local_anim_state):
      _sync_animation_state()

signal animation_finished(animation_name: String)

var local_anim_state: AnimationState
func _sync_animation_state() -> void:
  local_anim_state = state
  var animation_to_play := animation_player.get_animation(local_anim_state.animation_name)

  if animation_to_play == null:
    assert(false, "Attempted to play nonexistent animation %s" % local_anim_state.animation_name)

  var anim_elapsed_time: float = animation_to_play.length\
    if local_anim_state.skipped\
    else Time.get_unix_time_from_system() - state.started_at

  animation_player.play(local_anim_state.animation_name)
  animation_player.seek(anim_elapsed_time, true)
  if anim_elapsed_time >= animation_to_play.length:
    animation_finished.emit(local_anim_state.animation_name)

func authority_skip_current_animation() -> void:
  if !MultiplayerClient.is_lobby_host():
    assert(false, "ERROR: Non-host player called authority_skip_current_animation()!")  

  if local_anim_state and !local_anim_state.skipped:
    MultiplayerClient.send_packet(
      {
        "type": GameBase.GlobalGameMessage.UpdateAnimation,
        "animation_name": local_anim_state.animation_name,
        "started_at": local_anim_state.started_at,
        "skipped": true
      },
      MultiplayerPeer.TARGET_PEER_BROADCAST,
      MultiplayerPeer.TRANSFER_MODE_RELIABLE,
      true
    )

func handle_animation_finished(animation_name: String) -> void:
  pass

func authority_play_animation(animation_name: String) -> void:
  if !MultiplayerClient.is_lobby_host():
    assert(false, "ERROR: Non-host player called authority_play_animation()!")

  MultiplayerClient.send_packet(
    {
      "type": GameBase.GlobalGameMessage.UpdateAnimation,
      "animation_name": animation_name,
      "started_at": Time.get_unix_time_from_system(),
      "skipped": false
    },
    MultiplayerPeer.TARGET_PEER_BROADCAST,
    MultiplayerPeer.TRANSFER_MODE_RELIABLE,
    true
  )

func _unhandled_input(_event: InputEvent) -> void:
  if MultiplayerClient.is_authority():
    if Input.is_key_pressed(KEY_ENTER):
      authority_skip_current_animation()
