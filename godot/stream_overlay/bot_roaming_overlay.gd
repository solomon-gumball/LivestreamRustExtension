extends CanvasLayer

# @onready var animation_player: AnimationPlayer = %AnimationPlayer
# @onready var slot_reward_label: RichTextLabel = %SlotRewardLabel

# func show_slots_reward(result: GambaMachine.RowResult, multiplier: int) -> void:
#   if result == null:
#     return
  
#   slot_reward_label.text = result.description()
#   slot_reward_label.text += "\n+%s Gumbucks" % str(result.gumbucks() * multiplier)
#   animation_player.play("show_rewards_text")
#   await animation_player.animation_finished
