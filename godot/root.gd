extends Node

var child_scene: Node = null

var stream_overlay_scene: PackedScene = preload("res://stream_overlay/stream_overlay.tscn")
var extension_scene: PackedScene = preload("res://pages/extension_root.tscn")

func get_main_scene() -> PackedScene:
  return stream_overlay_scene if DebugScreenLayout.is_stream_overlay else extension_scene

func _ready() -> void:
  ObjectSerializer.register_script(PongGameState)

  if DebugScreenLayout.window_index == 0:
    WSClient.debug_chatter_id = '22445910' # Gumball
  else:
    WSClient.debug_chatter_id = '1273990990' # GumBOT

  print('hi ', (DebugScreenLayout.is_stream_overlay))
  child_scene = get_main_scene().instantiate()
  add_child(child_scene)
