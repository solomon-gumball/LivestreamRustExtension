class_name ProfilePage
extends Control

@onready var gumbot: GumBot = %gumbot
@export var profile_overlay: ProfileOverlay
@onready var username_label: Label = %UsernameLabel

func _ready() -> void:
  username_label.text = ""
  WSClient.authenticated_state.emote_triggered.connect(_handle_emote_triggered)
  WSClient.authenticated_state.my_chatter_updated.connect(_handle_chatter_updated)
  _handle_chatter_updated(WSClient.authenticated_state.current_chatter)

func _handle_chatter_updated(chatter: Chatter) -> void:
  if WSClient.state.current is not WSClient.AuthenticatedState:
    return

  username_label.text = chatter.display_name
  gumbot.chatter = WSClient.authenticated_state.current_chatter
  profile_overlay.chatter = WSClient.authenticated_state.current_chatter
  var anim_tree_playback: AnimationNodeStateMachinePlayback = gumbot.anim_tree.get("parameters/StateMachine/playback")
  anim_tree_playback.travel("Locomotion")
  # gumbot.bot_state = GumBot.BotState.Walking

func _handle_emote_triggered(_chatter: Chatter, _emote: String) -> void:
  return
  
