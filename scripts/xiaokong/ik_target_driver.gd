@tool
extends Node3D

const EPSILON := 0.00001
const META_IK_MODE := &"xiaokong_ik_mode"
const META_IK_LOOK_OFFSET := &"xiaokong_ik_look_offset"
const META_IK_LEFT_HAND_OFFSET := &"xiaokong_ik_left_hand_offset"
const META_IK_RIGHT_HAND_OFFSET := &"xiaokong_ik_right_hand_offset"
const META_IK_LEFT_HAND_ROTATION_DEG := &"xiaokong_ik_left_hand_rot_deg"
const META_IK_RIGHT_HAND_ROTATION_DEG := &"xiaokong_ik_right_hand_rot_deg"
const META_IK_AUTO_CLEAR_SEC := &"xiaokong_ik_auto_clear_sec"

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
@export var interaction_target_blend_speed: float = 10.0
@export var interaction_release_blend_speed: float = 8.0
@export var interaction_default_look_offset: Vector3 = Vector3(0.0, 1.35, 0.0)
@export var interaction_default_right_hand_offset: Vector3 = Vector3(0.12, 1.05, 0.0)
@export var interaction_default_left_hand_offset: Vector3 = Vector3(-0.12, 1.05, 0.0)
@export var interaction_default_auto_clear_sec: float = 0.0

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
var _interaction_anchor: Node3D
var _interaction_mode: StringName = &""
var _interaction_look_enabled: bool = false
var _interaction_left_hand_enabled: bool = false
var _interaction_right_hand_enabled: bool = false
var _interaction_weight: float = 0.0
var _interaction_target_weight: float = 0.0
var _interaction_auto_clear_left: float = 0.0
var _interaction_look_offset: Vector3 = Vector3.ZERO
var _interaction_left_hand_offset: Vector3 = Vector3.ZERO
var _interaction_right_hand_offset: Vector3 = Vector3.ZERO
var _interaction_left_hand_rotation_deg: Vector3 = Vector3.ZERO
var _interaction_right_hand_rotation_deg: Vector3 = Vector3.ZERO

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
	_update_marker_interaction(delta)

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
	if _interaction_target_weight > EPSILON or _interaction_weight > EPSILON:
		_idle_arm_offset_target_weight = 0.0
		_idle_arm_offset_dirty = true
		return
	_idle_arm_offset_target_weight = clampf(weight, 0.0, 1.0)
	_idle_arm_offset_dirty = true
	if not is_inside_tree():
		return
	if idle_arm_offset_blend_speed <= EPSILON:
		_idle_arm_offset_weight = _idle_arm_offset_target_weight
		_apply_arm_target_offsets(_idle_arm_offset_weight)

func apply_marker_interaction(marker: Marker3D) -> bool:
	if marker == null:
		clear_marker_interaction()
		return false
	if not marker.has_meta(META_IK_MODE):
		clear_marker_interaction()
		return false

	var mode_text: String = String(marker.get_meta(META_IK_MODE)).strip_edges().to_lower()
	if mode_text.is_empty() or mode_text == "none" or mode_text == "clear":
		clear_marker_interaction()
		return false

	_interaction_mode = StringName(mode_text)
	_interaction_anchor = marker
	_interaction_look_enabled = mode_text.find("look") >= 0
	_interaction_left_hand_enabled = mode_text.find("left") >= 0 or mode_text.find("both") >= 0
	_interaction_right_hand_enabled = mode_text.find("right") >= 0 or mode_text.find("both") >= 0
	if mode_text.find("reach") >= 0 and not _interaction_left_hand_enabled and not _interaction_right_hand_enabled:
		_interaction_right_hand_enabled = true

	_interaction_look_offset = _read_meta_vector3(marker, META_IK_LOOK_OFFSET, interaction_default_look_offset)
	_interaction_left_hand_offset = _read_meta_vector3(marker, META_IK_LEFT_HAND_OFFSET, interaction_default_left_hand_offset)
	_interaction_right_hand_offset = _read_meta_vector3(marker, META_IK_RIGHT_HAND_OFFSET, interaction_default_right_hand_offset)
	_interaction_left_hand_rotation_deg = _read_meta_vector3(marker, META_IK_LEFT_HAND_ROTATION_DEG, Vector3.ZERO)
	_interaction_right_hand_rotation_deg = _read_meta_vector3(marker, META_IK_RIGHT_HAND_ROTATION_DEG, Vector3.ZERO)
	_interaction_auto_clear_left = _read_meta_float(marker, META_IK_AUTO_CLEAR_SEC, interaction_default_auto_clear_sec)
	_interaction_target_weight = 1.0

	if not _interaction_look_enabled and not _interaction_left_hand_enabled and not _interaction_right_hand_enabled:
		clear_marker_interaction()
		return false

	set_idle_arm_offset_weight(0.0)
	return true

func apply_look_at_target(target: Node3D, local_offset: Vector3 = Vector3(0.0, 1.35, 0.0), auto_clear_sec: float = 0.0) -> bool:
	if target == null:
		clear_marker_interaction()
		return false

	_interaction_mode = &"look"
	_interaction_anchor = target
	_interaction_look_enabled = true
	_interaction_left_hand_enabled = false
	_interaction_right_hand_enabled = false
	_interaction_look_offset = local_offset
	_interaction_left_hand_offset = Vector3.ZERO
	_interaction_right_hand_offset = Vector3.ZERO
	_interaction_left_hand_rotation_deg = Vector3.ZERO
	_interaction_right_hand_rotation_deg = Vector3.ZERO
	_interaction_auto_clear_left = maxf(auto_clear_sec, 0.0)
	_interaction_target_weight = 1.0
	return true

func clear_marker_interaction(immediate: bool = false) -> void:
	_interaction_anchor = null
	_interaction_mode = &""
	_interaction_look_enabled = false
	_interaction_left_hand_enabled = false
	_interaction_right_hand_enabled = false
	_interaction_auto_clear_left = 0.0
	_interaction_target_weight = 0.0

	if immediate:
		_interaction_weight = 0.0
		_restore_targets_after_interaction_clear()

func has_active_marker_interaction() -> bool:
	return _interaction_target_weight > EPSILON or _interaction_weight > EPSILON

func _update_marker_interaction(delta: float) -> void:
	if _interaction_auto_clear_left > 0.0:
		_interaction_auto_clear_left = maxf(_interaction_auto_clear_left - delta, 0.0)
		if _interaction_auto_clear_left <= 0.0:
			_interaction_target_weight = 0.0

	if _interaction_anchor != null and not is_instance_valid(_interaction_anchor):
		_interaction_anchor = null
		_interaction_target_weight = 0.0

	var blend_speed := interaction_target_blend_speed if _interaction_target_weight >= _interaction_weight else interaction_release_blend_speed
	var blend_step := maxf(blend_speed, 0.0) * maxf(delta, 0.0)
	if blend_step > 0.0:
		_interaction_weight = move_toward(_interaction_weight, _interaction_target_weight, blend_step)
	else:
		_interaction_weight = _interaction_target_weight

	if _interaction_weight <= EPSILON:
		if _interaction_target_weight <= EPSILON:
			_restore_targets_after_interaction_clear()
		return
	if _interaction_anchor == null:
		return

	var anchor_transform: Transform3D = _interaction_anchor.global_transform
	if _interaction_look_enabled:
		var look_world: Vector3 = anchor_transform * _interaction_look_offset
		_blend_global_pose(mark_look_at_target, mark_look_at_target_base, look_world, Basis.IDENTITY, false, true)
	else:
		_blend_to_base_global(mark_look_at_target, mark_look_at_target_base, false, true)

	if _interaction_left_hand_enabled:
		var left_world: Vector3 = anchor_transform * _interaction_left_hand_offset
		var left_basis: Basis = anchor_transform.basis * Basis.from_euler(_deg_to_rad_vec3(_interaction_left_hand_rotation_deg))
		_blend_global_pose(left_hand_target, left_hand_target_base, left_world, Basis.IDENTITY, false, true)
		_blend_global_pose(left_hand_rot_target, left_hand_rot_target_base, Vector3.ZERO, left_basis, true, false)
	else:
		_blend_idle_arm_target_to_base(left_hand_target, left_hand_target_base, idle_left_hand_offset)
		_blend_to_base_global(left_hand_rot_target, left_hand_rot_target_base, true, false)

	if _interaction_right_hand_enabled:
		var right_world: Vector3 = anchor_transform * _interaction_right_hand_offset
		var right_basis: Basis = anchor_transform.basis * Basis.from_euler(_deg_to_rad_vec3(_interaction_right_hand_rotation_deg))
		_blend_global_pose(right_hand_target, right_hand_target_base, right_world, Basis.IDENTITY, false, true)
		_blend_global_pose(right_hand_rot_target, right_hand_rot_target_base, Vector3.ZERO, right_basis, true, false)
	else:
		_blend_idle_arm_target_to_base(right_hand_target, right_hand_target_base, idle_right_hand_offset)
		_blend_to_base_global(right_hand_rot_target, right_hand_rot_target_base, true, false)

	if auto_manage_influence:
		_update_modifier_influence()

func _restore_targets_after_interaction_clear() -> void:
	_interaction_anchor = null
	_interaction_mode = &""
	_restore_local_transform(mark_look_at_target, mark_look_at_target_base)
	_restore_local_transform(left_hand_rot_target, left_hand_rot_target_base)
	_restore_local_transform(right_hand_rot_target, right_hand_rot_target_base)
	_apply_arm_target_offsets(_idle_arm_offset_weight)
	if auto_manage_influence:
		_update_modifier_influence()

func _blend_idle_arm_target_to_base(node: Node3D, base_transform: Transform3D, idle_offset: Vector3) -> void:
	if node == null:
		return
	var target_local := base_transform
	target_local.origin += idle_offset * _idle_arm_offset_weight
	var parent_node := node.get_parent_node_3d()
	if parent_node == null:
		node.transform = node.transform.interpolate_with(target_local, _interaction_weight)
		return
	var target_global := parent_node.global_transform * target_local
	var current_global := node.global_transform
	var blended_global := current_global
	blended_global.origin = current_global.origin.lerp(target_global.origin, clampf(_interaction_weight, 0.0, 1.0))
	node.global_transform = blended_global

func _blend_to_base_global(node: Node3D, base_local: Transform3D, include_rotation: bool, include_position: bool) -> void:
	if node == null:
		return
	var parent_node := node.get_parent_node_3d()
	if parent_node == null:
		return
	var base_global: Transform3D = parent_node.global_transform * base_local
	var current: Transform3D = node.global_transform
	var blended := current
	var weight := clampf(_interaction_weight, 0.0, 1.0)
	var release_weight := 1.0 - weight
	if include_position:
		blended.origin = current.origin.lerp(base_global.origin, release_weight)
	if include_rotation:
		blended.basis = _slerp_basis(current.basis, base_global.basis, release_weight)
	node.global_transform = blended

func _blend_global_pose(node: Node3D, base_local: Transform3D, target_world_position: Vector3, target_world_basis: Basis, include_rotation: bool, include_position: bool) -> void:
	if node == null:
		return
	var parent_node := node.get_parent_node_3d()
	if parent_node == null:
		return

	var base_global: Transform3D = parent_node.global_transform * base_local
	var desired_global := base_global
	if include_position:
		desired_global.origin = target_world_position
	if include_rotation:
		desired_global.basis = target_world_basis

	var weight := clampf(_interaction_weight, 0.0, 1.0)
	var current: Transform3D = node.global_transform
	var blended := current
	if include_position:
		var weighted_target := base_global.origin.lerp(desired_global.origin, weight)
		blended.origin = current.origin.lerp(weighted_target, weight)
	if include_rotation:
		var weighted_basis := _slerp_basis(base_global.basis, desired_global.basis, weight)
		blended.basis = _slerp_basis(current.basis, weighted_basis, weight)
	node.global_transform = blended

func _slerp_basis(from_basis: Basis, to_basis: Basis, weight: float) -> Basis:
	var t := clampf(weight, 0.0, 1.0)
	var from_scale: Vector3 = from_basis.get_scale()
	var to_scale: Vector3 = to_basis.get_scale()
	var from_rot: Quaternion = from_basis.get_rotation_quaternion()
	var to_rot: Quaternion = to_basis.get_rotation_quaternion()
	var out_rot: Quaternion = from_rot.slerp(to_rot, t)
	var out_scale: Vector3 = from_scale.lerp(to_scale, t)
	return Basis(out_rot).scaled(out_scale)

func _deg_to_rad_vec3(value: Vector3) -> Vector3:
	return Vector3(
		deg_to_rad(value.x),
		deg_to_rad(value.y),
		deg_to_rad(value.z)
	)

func _read_meta_vector3(marker: Marker3D, key: StringName, fallback: Vector3) -> Vector3:
	if marker == null or not marker.has_meta(key):
		return fallback
	var raw_value: Variant = marker.get_meta(key)
	if raw_value is Vector3:
		return raw_value as Vector3
	if raw_value is Array:
		var arr := raw_value as Array
		if arr.size() >= 3:
			return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	if raw_value is String:
		var raw_text: String = String(raw_value).strip_edges()
		if raw_text.is_empty():
			return fallback
		if raw_text.begins_with("Vector3"):
			var parsed: Variant = str_to_var(raw_text)
			if parsed is Vector3:
				return parsed as Vector3
		var parts: PackedStringArray = raw_text.split(",", false)
		if parts.size() >= 3:
			return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	return fallback

func _read_meta_float(marker: Marker3D, key: StringName, fallback: float) -> float:
	if marker == null or not marker.has_meta(key):
		return fallback
	return float(marker.get_meta(key))

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
