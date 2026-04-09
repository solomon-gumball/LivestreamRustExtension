extends Node3D

@onready var gumbot: GumBot = %gumbot

func _ready() -> void:
  Network.emote_triggered.connect(_handle_emote_triggered)
  Network.chatter_updated.connect(_handle_chatter_updated)

func _handle_chatter_updated(chatter: Chatter) -> void:
  print(chatter)
  gumbot.chatter = chatter

func _handle_emote_triggered(chatter: Chatter, emote: String) -> void:
  print('chatter ', chatter)
  return
  
