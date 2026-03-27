@tool
extends Node3D

const EPSILON := 0.00001

@export var elbow_pole_distance_scale: float = 0.9
@export var knee_pole_distance_scale: float = 1.0

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

func _ready() -> void:
	if skeleton == null:
		push_warning("IKTargetDriver could not find sibling GeneralSkeleton.")
		return

	_cache_bones()
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
