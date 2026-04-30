class_name PongGameState
extends BaseGameState

enum Phase { Intro, Playing, RoundComplete }
var phase: int = Phase.Intro

var phase_started_at: float = 0.0
var score_l: int = 0
var score_r: int = 0
var paddle_l_state: PongEntity = PongEntity.new()
var paddle_r_state: PongEntity = PongEntity.new()
var ball_state: PongEntity = null

class BallState:
  var position: Vector3
  var velocity: Vector3
  var owner: int
  var sent_at: float

class PongEntity:
  var position: Vector3
  var velocity: Vector3
  var owner: int
  var score: int
  var sent_at: float