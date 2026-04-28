extends Node

var child_scene: Node = null

var stream_overlay_scene: PackedScene = preload("res://stream_overlay/stream_overlay.tscn")
var extension_scene: PackedScene = preload("res://pages/extension_root.tscn")

func get_main_scene() -> PackedScene:
  return stream_overlay_scene if DebugScreenLayout.is_stream_overlay else extension_scene

func _ready() -> void:
  ObjectSerializer.register_script(BaseGameState)
  ObjectSerializer.register_script(PongGameState)
  ObjectSerializer.register_script(MarblesGameState)

  var debug_ids: Dictionary[int, String] = {
    0: '22445910', # Gumball
    1: '1273990990', # GumBOT
    2: '892082742', # Slowed,
    3: '126430714', # Joony
  }
  
  WSClient.debug_chatter_id = debug_ids.get(DebugScreenLayout.window_index, "")

  child_scene = get_main_scene().instantiate()
  add_child(child_scene)
