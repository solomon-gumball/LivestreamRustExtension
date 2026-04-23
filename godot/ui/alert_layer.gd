extends CanvasLayer

@onready var alert_label: RichTextLabel = %AlertLabel
@onready var overlay: ColorRect = %Overlay
@onready var dismiss_button: Button = %DismissButton

func _ready() -> void:
  hide_alert()
  dismiss_button.pressed.connect(hide_alert)

func display_alert(message: String, allow_dismiss: bool = false) -> void:
  alert_label.text = message
  dismiss_button.visible = allow_dismiss
  overlay.self_modulate.a = 0.0
  overlay.visible = true
  get_tree().create_tween().tween_property(overlay, "self_modulate:a", 1.0, 0.1)

func hide_alert() -> void:
  overlay.visible = false
  
