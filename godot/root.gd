extends Node

var child_scene: Node = null

var stream_overlay_scene: PackedScene = preload("res://stream_overlay/stream_overlay.tscn")
var extension_scene: PackedScene = preload("res://pages/extension_root.tscn")

func _ready() -> void:
  print(DebugScreenLayout.window_index)
  if DebugScreenLayout.window_index == 0:
    WSClient.debug_chatter_id = '22445910' # Gumball
    child_scene = stream_overlay_scene.instantiate()
    add_child(child_scene)
  else:
    WSClient.debug_chatter_id = '1273990990' # GumBOT
    child_scene = extension_scene.instantiate()
    add_child(child_scene)
