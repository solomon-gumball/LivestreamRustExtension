class_name PongAnimationState

@export_storage var animation_name: String
@export_storage var started_at: float
@export_storage var skipped: bool = false

func equals(other: PongAnimationState) -> bool:
  if other != null and\
    other.animation_name == animation_name and\
    other.started_at == started_at and\
    other.skipped == skipped:
    return true
  return false
