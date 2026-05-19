extends Node3D
class_name ImpactBounceFx

@onready var impact_bounce_fx: GPUParticles3D = %ImpactBounceFx
@onready var circle_sprites: GPUParticles3D = %CircleSprites

var all_fx: Array[GPUParticles3D] = []

func _ready() -> void:
  impact_bounce_fx.one_shot = true
  circle_sprites.one_shot = true
  impact_bounce_fx.emitting = true
  circle_sprites.emitting = true

  for child in get_children():
    if child is GPUParticles3D:
      all_fx.append(child)

  for effect in all_fx:
    effect.finished.connect(_on_effect_finished)


func _on_effect_finished() -> void:
  for effect in all_fx:
    if effect.emitting:
      return
  queue_free()