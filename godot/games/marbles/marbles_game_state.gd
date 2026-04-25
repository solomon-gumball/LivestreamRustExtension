class_name MarblesGameState

enum GameState { Waiting, Playing, Ended }
@export_storage var game_state: int = GameState.Waiting

@export_storage var marbles_by_peer_id: Dictionary[int, MarbleState] = {}

class MarbleState:
  @export_storage var position: Vector3
  @export_storage var rotation: Vector3
  @export_storage var linear_velocity: Vector3