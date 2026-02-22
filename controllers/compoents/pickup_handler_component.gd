class_name PickupHandlerComponent
extends Node

@export_category("References")
@export var player: PlayerController
@export var pickup_ray: RayCast3D
@export var pickup_holder: SpringArm3D
@export var arm_end: Node3D

@export_category("Pickup Settings")
@export var pickup_distance: float = 5.0
@export var throw_force: float = 5.0
@export var follow_speed: float = 10.0

var held_object: Node3D = null

func _ready():
	if !pickup_ray:
		print("WARNING: pickup_ray is null!")
	
	if !pickup_holder:
		print("WARNING: pickup_holder is null!")
	
	if !arm_end:
		print("WARNING: arm_end is null!")

func _input(event):
	pass

func _physics_process(delta):
	if held_object and arm_end:
		var target_position = arm_end.global_position
		var move_vector = target_position - held_object.global_position
		var distance = move_vector.length()
		
		if distance > 0.01:
			held_object.linear_velocity = move_vector * follow_speed
		else:
			held_object.linear_velocity = Vector3.ZERO

func try_pickup_object() -> bool:
	if !pickup_ray:
		return false
	
	if !pickup_holder:
		return false
	
	if !arm_end:
		return false
	
	pickup_ray.force_raycast_update()
	
	if pickup_ray.is_colliding():
		var collider = pickup_ray.get_collider()
		
		if collider is RigidBody3D and collider.has_node("PickupPoint"):
			held_object = collider
			
			held_object.gravity_scale = 0.0
			held_object.linear_damp = 10.0
			held_object.angular_damp = 10.0
			held_object.lock_rotation = false
			
			if held_object is InteractableItem:
				held_object.set_held(true)
			
			return true
	
	return false

func pickup_object(object: Node3D) -> bool:
	if !pickup_holder:
		return false
	
	if !arm_end:
		return false
	
	if !object or !(object is RigidBody3D) or !object.has_node("PickupPoint"):
		return false
	
	if held_object:
		release_object(false)
	
	held_object = object
	
	held_object.gravity_scale = 0.0
	held_object.linear_damp = 10.0
	held_object.angular_damp = 10.0
	held_object.lock_rotation = true
	
	if held_object is InteractableItem:
		held_object.set_held(true)
	
	return true

func release_object(throw: bool = false) -> bool:
	if !held_object:
		return false
	
	if throw:
		var throw_direction = -pickup_ray.global_transform.basis.z
		var throw_force_vec = throw_direction * throw_force
		held_object.apply_central_impulse(throw_force_vec)
	else:
		pass
	
	if held_object is InteractableItem:
		held_object.set_held(false)
	
	held_object.gravity_scale = 1.0
	held_object.linear_damp = 0.1
	held_object.angular_damp = 0.05
	held_object.lock_rotation = false
	
	held_object = null
	
	return true


func is_holding_object() -> bool:
	return held_object != null

func get_held_object() -> RigidBody3D:
	return held_object
