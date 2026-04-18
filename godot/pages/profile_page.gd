class_name ProfilePage
extends Control

@onready var gumbot: GumBot = %gumbot
@export var profile_overlay: ProfileOverlay

func _ready() -> void:
  Network.authenticated_state.emote_triggered.connect(_handle_emote_triggered)
  Network.authenticated_state.chatter_updated.connect(_handle_chatter_updated)
  _handle_chatter_updated(Network.authenticated_state.current_chatter)

func _handle_chatter_updated(chatter: Chatter) -> void:
  if Network.connection_state.current is not Network.AuthenticatedState:
    return

  gumbot.chatter = Network.authenticated_state.current_chatter
  profile_overlay.chatter = Network.authenticated_state.current_chatter
  var anim_tree_playback: AnimationNodeStateMachinePlayback = gumbot.anim_tree.get("parameters/StateMachine/playback")
  anim_tree_playback.travel("Locomotion")
  # gumbot.bot_state = GumBot.BotState.Walking

func _handle_emote_triggered(_chatter: Chatter, _emote: String) -> void:
  return
  
