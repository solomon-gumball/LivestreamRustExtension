class_name ProfilePage
extends Node3D

@onready var gumbot: GumBot = %gumbot
@export var profile_overlay: ProfileOverlay

func _ready() -> void:
  Network.emote_triggered.connect(_handle_emote_triggered)
  Network.chatter_updated.connect(_handle_chatter_updated)
  Network.store_data_received.connect(_store_data_received)
  _handle_chatter_updated(Network.current_chatter)

func _store_data_received() -> void:
  if DebugScreenLayout.window_index == 0:
    Network.subscribe(['LOBBIES', '22445910']) # solomongumbal1
  # elif DebugScreenLayout.window_index == 1:
  else:
    Network.subscribe(['LOBBIES', '1273990990']) # solomongumbot

func _handle_chatter_updated(chatter: Chatter) -> void:
  if Network.current_chatter:
    gumbot.chatter = Network.current_chatter
    profile_overlay.chatter = Network.current_chatter
    var anim_tree_playback: AnimationNodeStateMachinePlayback = gumbot.anim_tree.get("parameters/StateMachine/playback")
    anim_tree_playback.travel("Locomotion")
    # gumbot.bot_state = GumBot.BotState.Walking

func _handle_emote_triggered(_chatter: Chatter, _emote: String) -> void:
  return
  
