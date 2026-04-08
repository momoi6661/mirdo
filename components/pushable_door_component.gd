class_name PushableDoorComponent
extends RigidBody3D

@export var interaction_time: float = 0.0
@export var prompt_text: String = "Push Door"
@export var push_torque: float = 5.0
@export var max_angular_speed: float = 2.2

func _ready() -> void:
	can_sleep = false

func get_interaction_time() -> float:
	return interaction_time

func get_prompt_text() -> String:
	return prompt_text

func interact(player: Node) -> void:
	_push_from_player(player)

func short_interact(player: Node) -> void:
	_push_from_player(player)

func _physics_process(_delta: float) -> void:
	var w := angular_velocity
	w.x = 0.0
	w.z = 0.0
	if abs(w.y) > max_angular_speed:
		w.y = sign(w.y) * max_angular_speed
	angular_velocity = w

func _push_from_player(player: Node) -> void:
	var push_sign := 1.0
	if player is Node3D:
		var local_player := to_local((player as Node3D).global_position)
		push_sign = -sign(local_player.x)
		if push_sign == 0.0:
			push_sign = 1.0

	apply_torque_impulse(Vector3.UP * push_torque * push_sign)
