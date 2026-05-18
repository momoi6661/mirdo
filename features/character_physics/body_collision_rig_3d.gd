@tool
class_name BodyCollisionRig3D
extends Node

const SOLVER_SCRIPT := preload("res://features/character_physics/secondary_physics_solver.gd")

@export var skeleton_path: NodePath = NodePath("..")
@export var spring_bone_collision_root_path: NodePath = NodePath("../AnimeSpringBones")
@export var collision_margin: float = 0.025
@export var include_name_filters: PackedStringArray = PackedStringArray()
@export var exclude_name_filters: PackedStringArray = PackedStringArray()
@export var lap_support_enabled: bool = true
@export var lap_left_bone: StringName = &"LeftUpperLeg"
@export var lap_right_bone: StringName = &"RightUpperLeg"
@export var lap_height_offset: float = 0.075
@export var lap_front_offset: float = 0.02
@export var lap_back_offset: float = 0.20
@export var lap_width_margin: float = 0.08

var _solver: SecondaryPhysicsSolver = SOLVER_SCRIPT.new()
var _skeleton: Skeleton3D
var _colliders: Array[SpringBoneCollision3D] = []

func _ready() -> void:
	_resolve_skeleton()
	_rebuild_colliders()

func project_point_out(point: Vector3, extra_margin: float = 0.0) -> Vector3:
	if _skeleton == null:
		_resolve_skeleton()
	if _skeleton == null:
		return point
	if _colliders.is_empty():
		_rebuild_colliders()

	var corrected := point
	for collider in _colliders:
		if not is_instance_valid(collider):
			continue
		var collider_world := _get_collider_world_transform(collider)
		var margin := collision_margin + extra_margin
		if collider is SpringBoneCollisionCapsule3D:
			var capsule := collider as SpringBoneCollisionCapsule3D
			var radius := capsule.radius
			var height := capsule.height
			var half_segment := maxf(height * 0.5 - radius, 0.0)
			var axis := collider_world.basis.y.normalized()
			corrected = _solver.project_point_out_of_capsule(
				corrected,
				collider_world.origin - axis * half_segment,
				collider_world.origin + axis * half_segment,
				radius,
				margin
			)
		elif collider is SpringBoneCollisionSphere3D:
			var sphere := collider as SpringBoneCollisionSphere3D
			corrected = _solver.project_point_out_of_sphere(corrected, collider_world.origin, sphere.radius, margin)
	if lap_support_enabled:
		corrected = _project_point_above_lap_support(corrected, extra_margin)
	return corrected

func _rebuild_colliders() -> void:
	_colliders.clear()
	var root := get_node_or_null(spring_bone_collision_root_path)
	if root == null:
		return
	_collect_colliders(root)

func _collect_colliders(node: Node) -> void:
	if node is SpringBoneCollision3D and _name_allowed(String(node.name)):
		_colliders.append(node as SpringBoneCollision3D)
	for child in node.get_children():
		_collect_colliders(child)

func _name_allowed(collider_name: String) -> bool:
	var lowered := collider_name.to_lower()
	for filter in exclude_name_filters:
		if lowered.contains(String(filter).to_lower()):
			return false
	if include_name_filters.is_empty():
		return true
	for filter in include_name_filters:
		if lowered.contains(String(filter).to_lower()):
			return true
	return false

func _get_collider_world_transform(collider: SpringBoneCollision3D) -> Transform3D:
	var bone_idx := collider.bone
	if bone_idx < 0 and not String(collider.bone_name).is_empty():
		bone_idx = _skeleton.find_bone(collider.bone_name)
	if bone_idx >= 0 and bone_idx < _skeleton.get_bone_count():
		var bone_world := _skeleton.global_transform * _skeleton.get_bone_global_pose(bone_idx)
		return bone_world * Transform3D(Basis(collider.rotation_offset), collider.position_offset)
	return collider.global_transform

func _project_point_above_lap_support(point: Vector3, extra_margin: float) -> Vector3:
	var left_idx := _skeleton.find_bone(lap_left_bone)
	var right_idx := _skeleton.find_bone(lap_right_bone)
	if left_idx < 0 or right_idx < 0:
		return point

	var left_world := _skeleton.global_transform * _skeleton.get_bone_global_pose(left_idx)
	var right_world := _skeleton.global_transform * _skeleton.get_bone_global_pose(right_idx)
	var left_basis := left_world.basis.orthonormalized()
	var right_basis := right_world.basis.orthonormalized()
	var center := (left_world.origin + right_world.origin) * 0.5
	var side_axis := (right_world.origin - left_world.origin)
	var side_length := side_axis.length()
	if side_length <= 0.0001:
		return point
	side_axis /= side_length

	var leg_axis := (left_basis.y.normalized() + right_basis.y.normalized()).normalized()
	if leg_axis.length_squared() <= 0.0001:
		leg_axis = Vector3.FORWARD
	var up_axis := Vector3.UP
	var forward_axis := leg_axis.slide(up_axis).normalized()
	if forward_axis.length_squared() <= 0.0001:
		forward_axis = side_axis.cross(up_axis).normalized()

	var support_center := center + up_axis * (lap_height_offset + collision_margin + extra_margin) + forward_axis * lap_front_offset
	var rel := point - support_center
	var side_distance := absf(rel.dot(side_axis))
	var forward_distance := rel.dot(forward_axis)
	var half_width := side_length * 0.5 + lap_width_margin
	if side_distance > half_width:
		return point
	if forward_distance < -lap_back_offset or forward_distance > lap_front_offset + 0.45:
		return point

	var signed_height := rel.dot(up_axis)
	if signed_height >= 0.0:
		return point
	return point - up_axis * signed_height

func _resolve_skeleton() -> void:
	_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if _skeleton != null:
		return
	var parent := get_parent()
	if parent is Skeleton3D:
		_skeleton = parent as Skeleton3D
