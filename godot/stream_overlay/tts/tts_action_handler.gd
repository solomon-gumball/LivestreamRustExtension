class_name TTSActionHandler
extends Node3D

@onready var tts_end_pos: Node3D = %TTSEndPos
@onready var tts_start_pos: Node3D = %TTSStartPos
@onready var gumbot: GumBot = %Gumbot
@onready var tts_service: TTSService = %TTSService

var _is_busy: bool = false

func _ready() -> void:
  gumbot.visible = false

func is_busy() -> bool:
  return _is_busy

func handle_action(action: Message.TTSRequest) -> void:
  _is_busy = true

  gumbot.visible = true
  gumbot.chatter = action.chatter
  gumbot.anim_tree.active = false
  gumbot.anim_player.play("StandIdle")

  gumbot.global_position = tts_start_pos.global_position

  var animate_in_tween := get_tree().create_tween()\
    .tween_property(gumbot, "global_position", tts_end_pos.global_position, 1.5)\
    .set_ease(Tween.EaseType.EASE_OUT)\
    .set_trans(Tween.TransitionType.TRANS_CUBIC)

  await animate_in_tween.finished

  tts_service.request_tts(action)
  await tts_service.did_start_playing
  gumbot.anim_player.play("Gamba")
  await tts_service.did_finish
  gumbot.anim_player.play("StandIdle")
  await get_tree().create_timer(1.5).timeout

  var animate_out_tween := get_tree().create_tween()\
    .tween_property(gumbot, "global_position", tts_start_pos.global_position, 1.5)\
    .set_ease(Tween.EaseType.EASE_IN)\
    .set_trans(Tween.TransitionType.TRANS_CUBIC)

  await animate_out_tween.finished

  WSClient.tts_activated(action.uuid)
  gumbot.visible = false
  _is_busy = false
