class_name MarblesGameState
extends BaseGameState

enum GameState { Waiting, Playing, Ended }
var game_state: int = GameState.Waiting
var started_at: float = 0
var marbles_by_peer_id: Dictionary[int, MarbleState] = {}
var animation: AnimationState = null
var username_visibility: bool = false

class MarbleState:
  var position: Vector3
  var rotation: Vector3
  var linear_velocity: Vector3
  var frozen: bool = true