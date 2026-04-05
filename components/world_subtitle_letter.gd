@tool
extends RigidBody3D
class_name WorldSubtitleLetter

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var label_3d: Label3D = $Label3D
@onready var label_3d_2: Label3D = $Label3D2

var text: String = ""
var random_torque: Vector3 = Vector3.ZERO

func _ready() -> void:
	_apply_text()

func _physics_process(_delta: float) -> void:
	apply_torque(random_torque)

func set_character(value: String) -> void:
	text = value
	_apply_text()

func start_animation() -> void:
	if animation_player != null:
		animation_player.play("letter/start")

func queue_animation() -> void:
	if animation_player != null:
		animation_player.play("letter/queue")
	freeze = false
	sleeping = false
	linear_velocity = Vector3(
		randf_range(-0.18, 0.18),
		randf_range(-0.22, -0.08),
		randf_range(-0.18, 0.18)
	)
	angular_velocity = Vector3(
		randf_range(-2.0, 2.0),
		randf_range(-2.0, 2.0),
		randf_range(-2.0, 2.0)
	)
	random_torque = Vector3(
		randf_range(-0.5, 0.5),
		randf_range(-0.5, 0.5),
		randf_range(-0.5, 0.5)
	)

func _apply_text() -> void:
	if label_3d != null:
		label_3d.text = text
	if label_3d_2 != null:
		label_3d_2.text = text

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == &"letter/queue":
		queue_free()
