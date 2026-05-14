class_name KartGameStateSynchronizer
extends StateSynchronizer

enum Message {
  CheckpointReached
}

class GameState:
  var checkpoints_reached: Dictionary[int, int] = {}

var game_state: GameState:
  get: return state as GameState
  set(v): state = v

func _init() -> void:
  channel_id = "kart_game_state"
  game_state = GameState.new()

func authority_checkpoint_reached(peer_id: int, new_checkpoint_index: int) -> void:
  var previously_reached_checkpoint: int = game_state.checkpoints_reached.get(peer_id, -1)

  if new_checkpoint_index != previously_reached_checkpoint + 1:
    print(
      "Checkpoint was reached in incorrect order. prev=%d new=%d",
      [previously_reached_checkpoint, new_checkpoint_index]
    )
    return
  
  game_state.checkpoints_reached.set(peer_id, new_checkpoint_index)
  send_refresh_state(MultiplayerPeer.TARGET_PEER_BROADCAST)
  state_updated.emit()

# func message_received(_sender_id: int, packet: Dictionary) -> void:
#   match packet.type:
