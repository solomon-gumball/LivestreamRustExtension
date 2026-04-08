extends Node2D

@onready var network_handler: NetworkHandler = %NetworkHandler

func _ready() -> void:
  network_handler.emote_triggered.connect(_handle_emote_triggered)
  network_handler.chatter_updated.connect(_handle_chatter_updated)

  # network_handler.scrolling_text_updated.connect(

func _handle_chatter_updated(chatter: Chatter) -> void:
  print(chatter)

func _handle_emote_triggered(chatter: Chatter, emote: String) -> void:
  print('chatter ', chatter)
  return
  
