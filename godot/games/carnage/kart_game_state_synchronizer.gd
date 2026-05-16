class_name KartGameStateSynchronizer
extends StateSynchronizer

@export var starting_checkpoint: int = -1

class GameState:
  var checkpoints_reached: Dictionary[int, int] = {}

var game_state: GameState:
  get: return state as GameState
  set(v): state = v

func _init() -> void:
  channel_id = "kart_game_state"
  game_state = GameState.new()

func get_last_reached_checkpoint(peer_id: int) -> int:
  return game_state.checkpoints_reached.get(peer_id, starting_checkpoint)

func authority_checkpoint_reached(peer_id: int, new_checkpoint_index: int) -> void:
  var previously_reached_checkpoint: int = game_state.checkpoints_reached.get(peer_id, starting_checkpoint)
  if new_checkpoint_index > previously_reached_checkpoint + 1:
    print(
      "Checkpoint was reached in incorrect order. prev=%d new=%d" %
      [previously_reached_checkpoint, new_checkpoint_index]
    )
    return
  elif new_checkpoint_index <= previously_reached_checkpoint:
    print("already reached checkpoint! no op")
  else:
    print("reached new checkpoint ", new_checkpoint_index)
    game_state.checkpoints_reached.set(peer_id, new_checkpoint_index)
    state = game_state
    send_refresh_state(MultiplayerPeer.TARGET_PEER_BROADCAST)
    state_updated.emit()

