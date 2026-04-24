@tool
extends Node3D
class_name GameBase

@warning_ignore("UNUSED_SIGNAL")
signal game_finished

enum GlobalGameMessage {
  ClientReady = 1000,
  CamFollow
}

func _ready() -> void:
  pass