class_name PongGameState

enum RoundState { Playing, RoundComplete }
@export_storage var round_state: int = RoundState.RoundComplete

@export_storage var paddle_l_state: PongEntity = PongEntity.new()
@export_storage var paddle_r_state: PongEntity = PongEntity.new()
@export_storage var ball_state: PongEntity = null