class_name PickupHandlerComponent
extends Node

@export_category("References")
@export var player: CharacterBody3D # 或者你的 PlayerController
@export var pickup_holder: SpringArm3D
@export var arm_end: Node3D

@export_category("Pickup Settings")
@export var throw_force: float = 5.0
@export var follow_speed: float = 10.0

var held_object: RigidBody3D = null

func _physics_process(delta: float) -> void:
	if held_object and arm_end:
		var target_position = arm_end.global_position
		var move_vector = target_position - held_object.global_position
		var distance = move_vector.length()
		
		if distance > 0.01:
			held_object.linear_velocity = move_vector * follow_speed
		else:
			held_object.linear_velocity = Vector3.ZERO


# 接收来自交互系统塞过来的物品
func pickup_specific_object(obj: RigidBody3D) -> void:
	if held_object: return
	
	held_object = obj
	held_object.gravity_scale = 0.0
	held_object.linear_damp = 10.0
	held_object.angular_damp = 10.0
	held_object.lock_rotation = false
	
	if held_object.has_method("set_held"):
		held_object.set_held(true)

func drop_object() -> void:
	if not held_object: return
	
	_reset_object_physics()
	held_object = null

func throw_object() -> void:
	if not held_object: return
	
	var obj = held_object
	_reset_object_physics()
	held_object = null
	
	# 给它一个朝向摄像机前方的力！
	var camera = get_viewport().get_camera_3d()
	if camera:
		var throw_dir = -camera.global_transform.basis.z
		obj.apply_central_impulse(throw_dir * throw_force)

func _reset_object_physics() -> void:
	if held_object:
		held_object.gravity_scale = 1.0
		held_object.linear_damp = 0.1
		held_object.angular_damp = 0.05
		held_object.lock_rotation = false
		
		if held_object.has_method("set_held"):
			held_object.set_held(false)

func is_holding_object() -> bool:
	return held_object != null
