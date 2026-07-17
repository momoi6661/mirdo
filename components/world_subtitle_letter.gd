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


func reveal_immediate() -> void:
	"""跳过入场动画直接显示，供 TTS 起播时的整句字幕使用。"""
	for candidate in [label_3d, label_3d_2]:
		var label := candidate as Label3D
		if label == null:
			continue
		# 场景初始透明度为 0；不补这一层时，直接渲染的字幕会“有节点但看不见”。
		label.modulate = Color(1.0, 1.0, 1.0, 1.0)
		label.outline_modulate = Color(1.0, 1.0, 1.0, 1.0)
		label.scale = Vector3.ONE
		label.position = Vector3(0.0, 0.0, label.position.z)
		label.rotation = Vector3.ZERO

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
