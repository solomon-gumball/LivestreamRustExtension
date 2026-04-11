extends Node3D

@onready var gumbot: GumBot = %gumbot

func _ready() -> void:
  Network.emote_triggered.connect(_handle_emote_triggered)
  Network.chatter_updated.connect(_handle_chatter_updated)

func _handle_chatter_updated(chatter: Chatter) -> void:
  print(chatter)
  gumbot.chatter = chatter
  var anim_tree_playback: AnimationNodeStateMachinePlayback = gumbot.anim_tree.get("parameters/StateMachine/playback")
  anim_tree_playback.travel("Locomotion")
  # gumbot.bot_state = GumBot.BotState.Walking

func _handle_emote_triggered(chatter: Chatter, emote: String) -> void:
  print('chatter ', chatter)
  return
  
