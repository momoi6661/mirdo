@tool
extends Node3D

const EPSILON := 0.00001

@export var elbow_pole_distance_scale: float = 0.9
@export var knee_pole_distance_scale: float = 1.0
@export var auto_manage_influence: bool = true
@export var manage_head_look_at: bool = true
@export var position_offset_threshold: float = 0.002
@export var rotation_offset_threshold_degrees: float = 1.0

@onready var skeleton: Skeleton3D = %GeneralSkeleton
@onready var left_hand_auto: Node3D = %LeftHandAuto
@onready var right_hand_auto: Node3D = %RightHandAuto
@onready var left_hand_rot_auto: Node3D = %LeftHandRotAuto
@onready var right_hand_rot_auto: Node3D = %RightHandRotAuto
@onready var left_foot_auto: Node3D = %LeftFootAuto
@onready var right_foot_auto: Node3D = %RightFootAuto
@onready var left_elbow_pole_auto: Node3D = %LeftElbowPoleAuto
@onready var right_elbow_pole_auto: Node3D = %RightElbowPoleAuto
@onready var left_knee_pole_auto: Node3D = %LeftKneePoleAuto
@onready var right_knee_pole_auto: Node3D = %RightKneePoleAuto
@onready var left_hand_target: Marker3D = $LeftHandAuto/LeftHandTarget
@onready var right_hand_target: Marker3D = $RightHandAuto/RightHandTarget
@onready var left_hand_rot_target: Marker3D = $LeftHandRotAuto/LeftHandRotTarget
@onready var right_hand_rot_target: Marker3D = $RightHandRotAuto/RightHandRotTarget
@onready var left_foot_target: Marker3D = $LeftFootAuto/LeftFootTarget
@onready var right_foot_target: Marker3D = $RightFootAuto/RightFootTarget
@onready var left_elbow_pole_target: Marker3D = $LeftElbowPoleAuto/LeftElbowPoleTarget
@onready var right_elbow_pole_target: Marker3D = $RightElbowPoleAuto/RightElbowPoleTarget
@onready var left_knee_pole_target: Marker3D = $LeftKneePoleAuto/LeftKneePoleTarget
@onready var right_knee_pole_target: Marker3D = $RightKneePoleAuto/RightKneePoleTarget
@onready var mark_look_at_target: Marker3D = %mark3d
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

func _ready() -> void:
	if skeleton == null:
		push_warning("IKTargetDriver could not find sibling GeneralSkeleton.")
		return

	_cache_bones()
	_cache_base_target_transforms()
	if not skeleton.pose_updated.is_connected(_on_skeleton_pose_updated):
		skeleton.pose_updated.connect(_on_skeleton_pose_updated)
	_on_skeleton_pose_updated()

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

func _on_skeleton_pose_updated() -> void:
	_set_auto_from_bone(left_hand_auto, left_hand_bone)
	_set_auto_from_bone(right_hand_auto, right_hand_bone)
	_set_auto_from_bone(left_hand_rot_auto, left_hand_bone)
	_set_auto_from_bone(right_hand_rot_auto, right_hand_bone)
	_set_auto_from_bone(left_foot_auto, left_foot_bone)
	_set_auto_from_bone(right_foot_auto, right_foot_bone)

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
	left_hand_target_base = left_hand_target.transform
	right_hand_target_base = right_hand_target.transform
	left_hand_rot_target_base = left_hand_rot_target.transform
	right_hand_rot_target_base = right_hand_rot_target.transform
	left_foot_target_base = left_foot_target.transform
	right_foot_target_base = right_foot_target.transform
	left_elbow_pole_target_base = left_elbow_pole_target.transform
	right_elbow_pole_target_base = right_elbow_pole_target.transform
	left_knee_pole_target_base = left_knee_pole_target.transform
	right_knee_pole_target_base = right_knee_pole_target.transform
	if mark_look_at_target != null:
		mark_look_at_target_base = mark_look_at_target.transform

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
