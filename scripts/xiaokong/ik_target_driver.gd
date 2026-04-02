@tool
extends Node3D

const EPSILON := 0.00001

@export var elbow_pole_distance_scale: float = 0.9
@export var knee_pole_distance_scale: float = 1.0
@export var look_at_follow_bone_name: StringName = &"头部"
@export var look_at_auto_forward_offset: float = 0.08
@export var auto_manage_influence: bool = true
@export var manage_head_look_at: bool = true
@export var position_offset_threshold: float = 0.002
@export var rotation_offset_threshold_degrees: float = 1.0
@export var idle_arm_offset_blend_speed: float = 8.0
@export var idle_left_hand_offset: Vector3 = Vector3(-0.02, 0.0, 0.0)
@export var idle_right_hand_offset: Vector3 = Vector3(0.02, 0.0, 0.0)
@export var idle_left_elbow_pole_offset: Vector3 = Vector3(0.0, 0.0, -0.01)
@export var idle_right_elbow_pole_offset: Vector3 = Vector3(0.0, 0.0, -0.01)

@onready var skeleton: Skeleton3D = get_parent().get_node_or_null("GeneralSkeleton") as Skeleton3D
@onready var left_hand_auto: Node3D = get_node_or_null("LeftHandAuto") as Node3D
@onready var right_hand_auto: Node3D = get_node_or_null("RightHandAuto") as Node3D
@onready var left_hand_rot_auto: Node3D = get_node_or_null("LeftHandRotAuto") as Node3D
@onready var right_hand_rot_auto: Node3D = get_node_or_null("RightHandRotAuto") as Node3D
@onready var left_foot_auto: Node3D = get_node_or_null("LeftFootAuto") as Node3D
@onready var right_foot_auto: Node3D = get_node_or_null("RightFootAuto") as Node3D
@onready var look_at_auto: Node3D = get_node_or_null("LookAtAuto") as Node3D
@onready var left_elbow_pole_auto: Node3D = get_node_or_null("LeftElbowPoleAuto") as Node3D
@onready var right_elbow_pole_auto: Node3D = get_node_or_null("RightElbowPoleAuto") as Node3D
@onready var left_knee_pole_auto: Node3D = get_node_or_null("LeftKneePoleAuto") as Node3D
@onready var right_knee_pole_auto: Node3D = get_node_or_null("RightKneePoleAuto") as Node3D
@onready var left_hand_target: Marker3D = get_node_or_null("LeftHandAuto/LeftHandTarget") as Marker3D
@onready var right_hand_target: Marker3D = get_node_or_null("RightHandAuto/RightHandTarget") as Marker3D
@onready var left_hand_rot_target: Marker3D = get_node_or_null("LeftHandRotAuto/LeftHandRotTarget") as Marker3D
@onready var right_hand_rot_target: Marker3D = get_node_or_null("RightHandRotAuto/RightHandRotTarget") as Marker3D
@onready var left_foot_target: Marker3D = get_node_or_null("LeftFootAuto/LeftFootTarget") as Marker3D
@onready var right_foot_target: Marker3D = get_node_or_null("RightFootAuto/RightFootTarget") as Marker3D
@onready var left_elbow_pole_target: Marker3D = get_node_or_null("LeftElbowPoleAuto/LeftElbowPoleTarget") as Marker3D
@onready var right_elbow_pole_target: Marker3D = get_node_or_null("RightElbowPoleAuto/RightElbowPoleTarget") as Marker3D
@onready var left_knee_pole_target: Marker3D = get_node_or_null("LeftKneePoleAuto/LeftKneePoleTarget") as Marker3D
@onready var right_knee_pole_target: Marker3D = get_node_or_null("RightKneePoleAuto/RightKneePoleTarget") as Marker3D
@onready var mark_look_at_target: Marker3D = get_node_or_null("LookAtAuto/mark3d") as Marker3D
@onready var head_look_at: LookAtModifier3D = get_parent().get_node_or_null("GeneralSkeleton/HeadLookAt") as LookAtModifier3D
@onready var left_arm_ik: TwoBoneIK3D = get_parent().get_node_or_null("GeneralSkeleton/LeftArmIK") as TwoBoneIK3D
@onready var right_arm_ik: TwoBoneIK3D = get_parent().get_node_or_null("GeneralSkeleton/RightArmIK") as TwoBoneIK3D
@onready var left_leg_ik: TwoBoneIK3D = get_parent().get_node_or_null("GeneralSkeleton/LeftLegIK") as TwoBoneIK3D
@onready var right_leg_ik: TwoBoneIK3D = get_parent().get_node_or_null("GeneralSkeleton/RightLegIK") as TwoBoneIK3D
@onready var left_hand_copy_rotation: CopyTransformModifier3D = get_parent().get_node_or_null("GeneralSkeleton/LeftHandCopyRotation") as CopyTransformModifier3D
@onready var right_hand_copy_rotation: CopyTransformModifier3D = get_parent().get_node_or_null("GeneralSkeleton/RightHandCopyRotation") as CopyTransformModifier3D

var left_upper_arm_bone: int = -1
var left_lower_arm_bone: int = -1
var left_hand_bone: int = -1
var right_upper_arm_bone: int = -1
var right_lower_arm_bone: int = -1
var right_hand_bone: int = -1
var left_upper_leg_bone: int = -1
var left_lower_leg_bone: int = -1
var left_foot_bone: int = -1
var right_upper_leg_bone: int = -1
var right_lower_leg_bone: int = -1
var right_foot_bone: int = -1
var look_at_follow_bone: int = -1

var left_hand_target_base: Transform3D
var right_hand_target_base: Transform3D
var left_hand_rot_target_base: Transform3D
var right_hand_rot_target_base: Transform3D
var left_foot_target_base: Transform3D
var right_foot_target_base: Transform3D
var left_elbow_pole_target_base: Transform3D
var right_elbow_pole_target_base: Transform3D
var left_knee_pole_target_base: Transform3D
var right_knee_pole_target_base: Transform3D
var mark_look_at_target_base: Transform3D
var _idle_arm_offset_target_weight: float = 0.0
var _idle_arm_offset_weight: float = 0.0
var _idle_arm_offset_dirty: bool = true

func _ready() -> void:
	if skeleton == null:
		push_warning("IKTargetDriver could not find sibling GeneralSkeleton.")
		return

	_cache_bones()
	_cache_base_target_transforms()
	if not skeleton.pose_updated.is_connected(_on_skeleton_pose_updated):
		skeleton.pose_updated.connect(_on_skeleton_pose_updated)
	_on_skeleton_pose_updated()
	_apply_idle_arm_offsets(0.0)
	set_process(true)

func _process(delta: float) -> void:
	if skeleton == null:
		return
	if Engine.is_editor_hint():
		_on_skeleton_pose_updated()

	if _idle_arm_offset_dirty or _idle_arm_offset_weight > EPSILON or _idle_arm_offset_target_weight > EPSILON:
		_apply_idle_arm_offsets(delta)

func _exit_tree() -> void:
	if skeleton != null and skeleton.pose_updated.is_connected(_on_skeleton_pose_updated):
		skeleton.pose_updated.disconnect(_on_skeleton_pose_updated)

func _cache_bones() -> void:
	left_upper_arm_bone = skeleton.find_bone("LeftUpperArm")
	left_lower_arm_bone = skeleton.find_bone("LeftLowerArm")
	left_hand_bone = skeleton.find_bone("LeftHand")
	right_upper_arm_bone = skeleton.find_bone("RightUpperArm")
	right_lower_arm_bone = skeleton.find_bone("RightLowerArm")
	right_hand_bone = skeleton.find_bone("RightHand")
	left_upper_leg_bone = skeleton.find_bone("LeftUpperLeg")
	left_lower_leg_bone = skeleton.find_bone("LeftLowerLeg")
	left_foot_bone = skeleton.find_bone("LeftFoot")
	right_upper_leg_bone = skeleton.find_bone("RightUpperLeg")
	right_lower_leg_bone = skeleton.find_bone("RightLowerLeg")
	right_foot_bone = skeleton.find_bone("RightFoot")

	look_at_follow_bone = skeleton.find_bone(String(look_at_follow_bone_name))
	if look_at_follow_bone == -1:
		look_at_follow_bone = skeleton.find_bone("头部")
	if look_at_follow_bone == -1:
		look_at_follow_bone = skeleton.find_bone("Head")
	if look_at_follow_bone == -1:
		push_warning("IKTargetDriver could not find a LookAt follow bone.")

func _on_skeleton_pose_updated() -> void:
	_set_auto_from_bone(left_hand_auto, left_hand_bone)
	_set_auto_from_bone(right_hand_auto, right_hand_bone)
	_set_auto_from_bone(left_hand_rot_auto, left_hand_bone)
	_set_auto_from_bone(right_hand_rot_auto, right_hand_bone)
	_set_auto_from_bone(left_foot_auto, left_foot_bone)
	_set_auto_from_bone(right_foot_auto, right_foot_bone)
	_set_auto_from_bone_with_forward_offset(look_at_auto, look_at_follow_bone, look_at_auto_forward_offset)

	_update_pole_auto(left_elbow_pole_auto, left_upper_arm_bone, left_lower_arm_bone, left_hand_bone, Vector3(0, 0, -1), elbow_pole_distance_scale)
	_update_pole_auto(right_elbow_pole_auto, right_upper_arm_bone, right_lower_arm_bone, right_hand_bone, Vector3(0, 0, -1), elbow_pole_distance_scale)
	_update_pole_auto(left_knee_pole_auto, left_upper_leg_bone, left_lower_leg_bone, left_foot_bone, Vector3(0, 0, 1), knee_pole_distance_scale)
	_update_pole_auto(right_knee_pole_auto, right_upper_leg_bone, right_lower_leg_bone, right_foot_bone, Vector3(0, 0, 1), knee_pole_distance_scale)

	if auto_manage_influence:
		_update_modifier_influence()

func _set_auto_from_bone(target: Node3D, bone_idx: int) -> void:
	if target == null or bone_idx == -1:
		return

	target.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)

func _set_auto_from_bone_with_forward_offset(target: Node3D, bone_idx: int, forward_offset: float) -> void:
	if target == null or bone_idx == -1:
		return

	var bone_global: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)
	var forward: Vector3 = -bone_global.basis.z.normalized()
	bone_global.origin += forward * forward_offset
	target.global_transform = bone_global

func _update_pole_auto(target: Node3D, root_bone_idx: int, middle_bone_idx: int, end_bone_idx: int, fallback_direction: Vector3, distance_scale: float) -> void:
	if target == null or root_bone_idx == -1 or middle_bone_idx == -1 or end_bone_idx == -1:
		return

	var root_transform: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(root_bone_idx)
	var middle_transform: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(middle_bone_idx)
	var end_transform: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(end_bone_idx)

	var root_position: Vector3 = root_transform.origin
	var middle_position: Vector3 = middle_transform.origin
	var end_position: Vector3 = end_transform.origin

	var root_to_end: Vector3 = end_position - root_position
	if root_to_end.length_squared() <= EPSILON:
		target.global_transform = Transform3D(Basis.IDENTITY, middle_position)
		return

	var root_to_end_dir: Vector3 = root_to_end.normalized()
	var root_to_middle: Vector3 = middle_position - root_position
	var projected_middle: Vector3 = root_to_end_dir * root_to_middle.dot(root_to_end_dir)
	var pole_direction: Vector3 = root_to_middle - projected_middle
	if pole_direction.length_squared() <= EPSILON:
		pole_direction = fallback_direction.normalized()
	else:
		pole_direction = pole_direction.normalized()

	var upper_len: float = (middle_position - root_position).length()
	var lower_len: float = (end_position - middle_position).length()
	var pole_distance: float = max(upper_len, lower_len) * distance_scale
	var auto_basis: Basis = skeleton.global_transform.basis.orthonormalized()
	target.global_transform = Transform3D(auto_basis, middle_position + pole_direction * pole_distance)

func _cache_base_target_transforms() -> void:
	left_hand_target_base = _safe_local_transform(left_hand_target)
	right_hand_target_base = _safe_local_transform(right_hand_target)
	left_hand_rot_target_base = _safe_local_transform(left_hand_rot_target)
	right_hand_rot_target_base = _safe_local_transform(right_hand_rot_target)
	left_foot_target_base = _safe_local_transform(left_foot_target)
	right_foot_target_base = _safe_local_transform(right_foot_target)
	left_elbow_pole_target_base = _safe_local_transform(left_elbow_pole_target)
	right_elbow_pole_target_base = _safe_local_transform(right_elbow_pole_target)
	left_knee_pole_target_base = _safe_local_transform(left_knee_pole_target)
	right_knee_pole_target_base = _safe_local_transform(right_knee_pole_target)
	mark_look_at_target_base = _safe_local_transform(mark_look_at_target)

func _safe_local_transform(node: Node3D) -> Transform3D:
	if node == null:
		return Transform3D.IDENTITY
	return node.transform

func reset_arm_targets_to_base() -> void:
	_idle_arm_offset_target_weight = 0.0
	_idle_arm_offset_weight = 0.0
	_idle_arm_offset_dirty = false
	_restore_local_transform(left_hand_target, left_hand_target_base)
	_restore_local_transform(right_hand_target, right_hand_target_base)
	_restore_local_transform(left_elbow_pole_target, left_elbow_pole_target_base)
	_restore_local_transform(right_elbow_pole_target, right_elbow_pole_target_base)
	_restore_local_transform(left_hand_rot_target, left_hand_rot_target_base)
	_restore_local_transform(right_hand_rot_target, right_hand_rot_target_base)

	if auto_manage_influence:
		_update_modifier_influence()

func set_idle_arm_offset_weight(weight: float) -> void:
	_idle_arm_offset_target_weight = clampf(weight, 0.0, 1.0)
	_idle_arm_offset_dirty = true
	if not is_inside_tree():
		return
	if idle_arm_offset_blend_speed <= EPSILON:
		_idle_arm_offset_weight = _idle_arm_offset_target_weight
		_apply_arm_target_offsets(_idle_arm_offset_weight)

func _apply_idle_arm_offsets(delta: float) -> void:
	var blend_step := maxf(idle_arm_offset_blend_speed, 0.0) * maxf(delta, 0.0)
	if blend_step > 0.0:
		_idle_arm_offset_weight = move_toward(_idle_arm_offset_weight, _idle_arm_offset_target_weight, blend_step)
	else:
		_idle_arm_offset_weight = _idle_arm_offset_target_weight

	_apply_arm_target_offsets(_idle_arm_offset_weight)
	if is_zero_approx(_idle_arm_offset_weight) and is_zero_approx(_idle_arm_offset_target_weight):
		_idle_arm_offset_dirty = false

func _apply_arm_target_offsets(weight: float) -> void:
	_set_position_offset(left_hand_target, left_hand_target_base, idle_left_hand_offset, weight)
	_set_position_offset(right_hand_target, right_hand_target_base, idle_right_hand_offset, weight)
	_set_position_offset(left_elbow_pole_target, left_elbow_pole_target_base, idle_left_elbow_pole_offset, weight)
	_set_position_offset(right_elbow_pole_target, right_elbow_pole_target_base, idle_right_elbow_pole_offset, weight)

	if auto_manage_influence:
		_update_modifier_influence()

func _set_position_offset(node: Node3D, base_transform: Transform3D, offset: Vector3, weight: float) -> void:
	if node == null:
		return
	var target_transform := base_transform
	target_transform.origin += offset * weight
	node.transform = target_transform

func _restore_local_transform(node: Node3D, base_transform: Transform3D) -> void:
	if node == null:
		return
	node.transform = base_transform

func _update_modifier_influence() -> void:
	var left_arm_active: bool = _has_position_offset(left_hand_target, left_hand_target_base) or _has_position_offset(left_elbow_pole_target, left_elbow_pole_target_base)
	var right_arm_active: bool = _has_position_offset(right_hand_target, right_hand_target_base) or _has_position_offset(right_elbow_pole_target, right_elbow_pole_target_base)
	var left_leg_active: bool = _has_position_offset(left_foot_target, left_foot_target_base) or _has_position_offset(left_knee_pole_target, left_knee_pole_target_base)
	var right_leg_active: bool = _has_position_offset(right_foot_target, right_foot_target_base) or _has_position_offset(right_knee_pole_target, right_knee_pole_target_base)
	var left_hand_rot_active: bool = _has_rotation_offset(left_hand_rot_target, left_hand_rot_target_base)
	var right_hand_rot_active: bool = _has_rotation_offset(right_hand_rot_target, right_hand_rot_target_base)

	_set_influence(left_arm_ik, 1.0 if left_arm_active else 0.0)
	_set_influence(right_arm_ik, 1.0 if right_arm_active else 0.0)
	_set_influence(left_leg_ik, 1.0 if left_leg_active else 0.0)
	_set_influence(right_leg_ik, 1.0 if right_leg_active else 0.0)
	_set_influence(left_hand_copy_rotation, 1.0 if left_hand_rot_active else 0.0)
	_set_influence(right_hand_copy_rotation, 1.0 if right_hand_rot_active else 0.0)

	if manage_head_look_at:
		var head_active: bool = _has_position_offset(mark_look_at_target, mark_look_at_target_base)
		_set_influence(head_look_at, 1.0 if head_active else 0.0)

func _set_influence(modifier: SkeletonModifier3D, value: float) -> void:
	if modifier == null:
		return
	modifier.influence = value

func _has_position_offset(node: Node3D, base_transform: Transform3D) -> bool:
	if node == null:
		return false
	return node.transform.origin.distance_to(base_transform.origin) > position_offset_threshold

func _has_rotation_offset(node: Node3D, base_transform: Transform3D) -> bool:
	if node == null:
		return false

	var delta_basis: Basis = base_transform.basis.inverse() * node.transform.basis
	var delta_quaternion: Quaternion = delta_basis.get_rotation_quaternion().normalized()
	var angle: float = 2.0 * acos(clamp(abs(delta_quaternion.w), -1.0, 1.0))
	return angle > deg_to_rad(rotation_offset_threshold_degrees)
