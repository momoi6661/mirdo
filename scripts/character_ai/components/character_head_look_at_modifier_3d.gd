@tool
class_name CharacterHeadLookAtModifier3D
extends SkeletonModifier3D

## Small, self-contained head look-at modifier for Mirdo-style characters.
## The controller only moves a proxy Marker3D and blends target_weight; this
## modifier writes the head bone after the body AnimationTree has evaluated.

@export var enabled: bool = true
@export var target_path: NodePath
@export var head_bone_name: StringName = &"Head"
@export_range(0.0, 1.0, 0.001) var target_weight: float = 0.0
@export_range(0.0, 1.0, 0.001) var pose_write_strength: float = 0.78
@export_range(-180.0, 180.0, 0.1) var yaw_degrees: float = 0.0
@export_range(-89.0, 89.0, 0.1) var pitch_degrees: float = 0.0
@export var use_actor_local_limits: bool = true
@export var actor_path: NodePath
@export var use_negative_z_forward: bool = false
@export_range(0.0, 120.0, 0.1) var max_yaw_degrees: float = 65.0
@export_range(0.0, 80.0, 0.1) var max_pitch_up_degrees: float = 25.0
@export_range(0.0, 80.0, 0.1) var max_pitch_down_degrees: float = 35.0
@export var head_forward_axis: Vector3 = Vector3(0.0, 0.0, 1.0)
@export var head_up_axis: Vector3 = Vector3(0.0, 1.0, 0.0)
@export var debug_log: bool = false

var _head_bone_idx: int = -1
var _cached_skeleton: Skeleton3D
var _target_node: Node3D
var _actor_node: Node3D

func _ready() -> void:
	_refresh_refs()

func _process_modification_with_delta(_delta: float) -> void:
	if not enabled or target_weight <= 0.001:
		return
	_refresh_refs_if_needed()
	var skeleton := get_skeleton()
	if skeleton == null or _head_bone_idx < 0 or _target_node == null:
		return

	var current_pose := skeleton.get_bone_global_pose(_head_bone_idx)
	var current_world := skeleton.global_transform * current_pose
	var target_world_pos := _target_node.global_position
	var to_target := target_world_pos - current_world.origin
	if to_target.length_squared() <= 0.0001:
		return
	var desired_dir := _clamp_direction(to_target.normalized())
	if desired_dir.length_squared() <= 0.0001:
		return

	var current_axis := (current_world.basis * head_forward_axis).normalized()
	if current_axis.length_squared() <= 0.0001:
		current_axis = current_world.basis.z.normalized()
	var rotation_to_target := Quaternion(current_axis, desired_dir.normalized())
	var target_basis := (Basis(rotation_to_target) * current_world.basis).orthonormalized()
	var target_pose := skeleton.global_transform.affine_inverse() * Transform3D(target_basis, current_world.origin)
	var write_weight := clampf(target_weight * pose_write_strength, 0.0, 1.0)
	skeleton.set_bone_global_pose(_head_bone_idx, current_pose.interpolate_with(target_pose, write_weight))
	skeleton.force_update_bone_child_transform(_head_bone_idx)

func set_look_weight(value: float) -> void:
	target_weight = clampf(value, 0.0, 1.0)

func set_target_node(node: Node3D) -> void:
	_target_node = node
	if node != null and is_inside_tree():
		target_path = get_path_to(node)

func _refresh_refs_if_needed() -> void:
	var skeleton := get_skeleton()
	if skeleton != _cached_skeleton or _head_bone_idx < 0:
		_refresh_refs()
	elif _target_node == null and target_path != NodePath():
		_target_node = get_node_or_null(target_path) as Node3D
	elif _actor_node == null and actor_path != NodePath():
		_actor_node = get_node_or_null(actor_path) as Node3D

func _refresh_refs() -> void:
	_cached_skeleton = get_skeleton()
	_head_bone_idx = -1
	if _cached_skeleton != null:
		_head_bone_idx = _cached_skeleton.find_bone(head_bone_name)
	if target_path != NodePath():
		_target_node = get_node_or_null(target_path) as Node3D
	if actor_path != NodePath():
		_actor_node = get_node_or_null(actor_path) as Node3D

func _clamp_direction(world_dir: Vector3) -> Vector3:
	if not use_actor_local_limits:
		return world_dir.normalized()
	var actor := _resolve_actor()
	if actor == null:
		return world_dir.normalized()
	var forward := (-actor.global_basis.z if use_negative_z_forward else actor.global_basis.z).normalized()
	var right := actor.global_basis.x.normalized()
	var up := actor.global_basis.y.normalized()
	if forward.length_squared() <= 0.0001:
		return world_dir.normalized()

	var local_x := world_dir.dot(right)
	var local_y := world_dir.dot(up)
	var local_z := world_dir.dot(forward)
	var horizontal := Vector2(local_x, local_z)
	if horizontal.length_squared() <= 0.000001:
		return world_dir.normalized()
	var yaw := atan2(local_x, local_z)
	var pitch := atan2(local_y, horizontal.length())
	var clamped_yaw := clampf(yaw, -deg_to_rad(max_yaw_degrees), deg_to_rad(max_yaw_degrees))
	var clamped_pitch := clampf(pitch, -deg_to_rad(max_pitch_down_degrees), deg_to_rad(max_pitch_up_degrees))
	yaw_degrees = rad_to_deg(clamped_yaw)
	pitch_degrees = rad_to_deg(clamped_pitch)

	var cos_pitch := cos(clamped_pitch)
	var clamped_local := Vector3(
		sin(clamped_yaw) * cos_pitch,
		sin(clamped_pitch),
		cos(clamped_yaw) * cos_pitch
	).normalized()
	return (right * clamped_local.x + up * clamped_local.y + forward * clamped_local.z).normalized()

func _resolve_actor() -> Node3D:
	if _actor_node != null and is_instance_valid(_actor_node):
		return _actor_node
	if actor_path != NodePath():
		_actor_node = get_node_or_null(actor_path) as Node3D
		if _actor_node != null:
			return _actor_node
	var current: Node = self
	while current != null:
		if current is CharacterBody3D:
			_actor_node = current as Node3D
			return _actor_node
		current = current.get_parent()
	return null
