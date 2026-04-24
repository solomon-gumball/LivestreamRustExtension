@tool
extends Node3D
class_name GameBase

var lobby: Lobby

@warning_ignore("UNUSED_SIGNAL")
signal game_finished

enum GlobalGameMessage {
  ClientReady = 1000,
  CamFollow
}

func _ready() -> void:
  pass