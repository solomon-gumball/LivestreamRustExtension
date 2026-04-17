extends CanvasLayer
class_name AlertLayer

@onready var alert_label: RichTextLabel = %AlertLabel
@onready var overlay: ColorRect = %Overlay

func display_alert(message: String) -> void:
  overlay.visible = true
  alert_label.text = message

func hide_alert() -> void:
  overlay.visible = false
  
