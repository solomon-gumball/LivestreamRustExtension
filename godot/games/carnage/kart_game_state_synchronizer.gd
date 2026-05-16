class_name KartGameStateSynchronizer
extends StateSynchronizer

@export var starting_checkpoint: int = -1
var total_checkpoints_count: int = 0

class GameState:
  var start_time: int = -1
  var results: Array[RaceResult] = []
  var checkpoints_reached: Dictionary[int, int] = {}

class RaceResult:
  var peer_id: int
  var name: String
  var time: int

var game_state: GameState:
  get: return state as GameState
  set(v): state = v

func _init() -> void:
  channel_id = "kart_game_state"
  game_state = GameState.new()

func get_last_reached_checkpoint(peer_id: int) -> int:
  return game_state.checkpoints_reached.get(peer_id, starting_checkpoint)

func authority_checkpoint_reached(peer_id: int, new_checkpoint_index: int) -> void:
  if !MultiplayerClient.is_lobby_host(): return

  var previously_reached_checkpoint: int = game_state.checkpoints_reached.get(peer_id, starting_checkpoint)
  
  # Invalid checkpoint order
  if new_checkpoint_index > previously_reached_checkpoint + 1:
    print(
      "Checkpoint was reached in incorrect order. prev=%d new=%d" %
      [previously_reached_checkpoint, new_checkpoint_index]
    )
    return

  # Already reached checkpoint
  elif new_checkpoint_index <= previously_reached_checkpoint:
    pass

  # Reached new checkpoint
  else:
    game_state.checkpoints_reached.set(peer_id, new_checkpoint_index)
    state = game_state

    # If final checkpoint
    if new_checkpoint_index >= total_checkpoints_count - 1:
      var result := RaceResult.new()
      result.peer_id = peer_id
      result.time = Time.get_ticks_msec() - game_state.start_time
      game_state.results.append(result)

    send_refresh_state(MultiplayerPeer.TARGET_PEER_BROADCAST)
    state_updated.emit()

