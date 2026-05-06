extends Node

var child_scene: Node = null
@onready var version_label: Label = %VersionLabel

# var stream_overlay_scene: PackedScene = preload("res://stream_overlay/stream_overlay.tscn")
# var extension_scene: PackedScene = preload("res://pages/extension_root.tscn")

func get_main_scene() -> PackedScene:
  return load("res://stream_overlay/stream_overlay.tscn") \
    if OS.has_feature("overlay") else \
    load("res://pages/extension_root.tscn")

func _ready() -> void:
  ObjectSerializer.register_script(BaseGameState)
  ObjectSerializer.register_script(PongGameState)
  ObjectSerializer.register_script(MarblesGameState)

  child_scene = get_main_scene().instantiate()
  add_child(child_scene)

  var version_file := FileAccess.open("res://version.txt", FileAccess.READ)
  version_label.text = version_file.get_as_text().strip_edges() if version_file else ""
