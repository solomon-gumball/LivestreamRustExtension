class_name PongGameState

enum Phase { Intro, Playing, RoundComplete }
@export_storage var phase: int = Phase.Intro

@export_storage var score_l: int = 0
@export_storage var score_r: int = 0
@export_storage var paddle_l_state: PongEntity = PongEntity.new()
@export_storage var paddle_r_state: PongEntity = PongEntity.new()
@export_storage var ball_state: PongEntity = null
@export_storage var animation_state: PongAnimationState = null