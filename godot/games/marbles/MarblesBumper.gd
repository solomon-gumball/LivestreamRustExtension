extends Node3D
class_name MarblesBumper

@onready var collider: Area3D = $Collider
@onready var animations: AnimationPlayer = $Animations

func _ready() -> void:
  collider.body_entered.connect(on_body_entered)

func on_body_entered(body: PhysicsBody3D):
  if body is MarbleBot:
    var bot = body as RigidBody3D
    var impulse_dir = (body.global_position - collider.global_position)
    impulse_dir.x = 0
    impulse_dir = (impulse_dir + global_basis.y).normalized()
    var impulse = impulse_dir.normalized() * (10.0 + clamp(bot.linear_velocity.length() / 30.0, 0, 1) * 3.0)
    bot.linear_velocity = Vector3.ZERO
    # DebugDraw3D.draw_arrow(collider.global_position, collider.global_position + impulse, Color(1, 0, 0, 1), 5, true, 10)
    bot.apply_central_impulse(impulse)
    animations.play("spring_out")
