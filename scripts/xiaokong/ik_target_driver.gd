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
const META_NODE_FORWARD_OFFSET := &"ik_forward_offset"
const META_NODE_POLE_DISTANCE_SCALE := &"ik_pole_distance_scale"
const META_NODE_POLE_FALLBACK_LOCAL := &"ik_pole_fallback_local"
const META_NODE_GROUND_FOOT_AUTO := &"ik_ground_auto_enabled"
const META_NODE_GROUND_COLLISION_MASK := &"ik_ground_collision_mask"
const META_NODE_GROUND_RAYCAST_UP := &"ik_ground_raycast_up"
const META_NODE_GROUND_RAYCAST_DOWN := &"ik_ground_raycast_down"
const META_NODE_GROUND_FOOT_HEIGHT := &"ik_ground_foot_height"
const META_NODE_GROUND_MAX_TARGET_DISTANCE := &"ik_ground_max_target_distance"
const META_NODE_GROUND_POSITION_LERP_SPEED := &"ik_ground_position_lerp_speed"
const META_NODE_GROUND_ROTATION_LERP_SPEED := &"ik_ground_rotation_lerp_speed"
const META_NODE_GROUND_INFLUENCE_BLEND_SPEED := &"ik_ground_influence_blend_speed"
const META_NODE_GROUND_DISABLE_SPEED := &"ik_ground_disable_speed"
const META_NODE_GROUND_ALIGN_TO_NORMAL := &"ik_ground_align_to_normal"
const META_NODE_PLANT_ENABLED := &"ik_plant_enabled"
const META_NODE_PLANT_HEIGHT_THRESHOLD := &"ik_plant_height_threshold"
const META_NODE_PLANT_VERTICAL_SPEED_THRESHOLD := &"ik_plant_vertical_speed_threshold"
const META_NODE_PLANT_RELEASE_DISTANCE := &"ik_plant_release_distance"
const META_NODE_PLANT_RELEASE_HEIGHT := &"ik_plant_release_height"
const META_NODE_PLANT_MIN_HOLD_TIME := &"ik_plant_min_hold_time"
const IK_CHANNEL_LOOK := &"look"
const IK_CHANNEL_SPINE := &"spine"
const IK_CHANNEL_ARM_REACH := &"arm_reach"
const IK_CHANNEL_ARM_IDLE := &"arm_idle"
const IK_CHANNEL_LEG_GROUND := &"leg_ground"
const IK_CHANNEL_HAND_ROT := &"hand_rot"
const IK_CHANNELS: Array[StringName] = [
	IK_CHANNEL_LOOK,
	IK_CHANNEL_SPINE,
	IK_CHANNEL_ARM_REACH,
	IK_CHANNEL_ARM_IDLE,
	IK_CHANNEL_LEG_GROUND,
	IK_CHANNEL_HAND_ROT,
]
const STATE_PROFILE_DEFAULT := &"default"
const DEFAULT_ELBOW_POLE_DISTANCE_SCALE := 0.9
const DEFAULT_KNEE_POLE_DISTANCE_SCALE := 1.0
const DEFAULT_GROUND_COLLISION_MASK := 1
const DEFAULT_GROUND_RAYCAST_UP := 0.4
const DEFAULT_GROUND_RAYCAST_DOWN := 1.0
const DEFAULT_GROUND_FOOT_HEIGHT := 0.03
const DEFAULT_GROUND_MAX_TARGET_DISTANCE := 0.35
const DEFAULT_GROUND_POSITION_LERP_SPEED := 14.0
const DEFAULT_GROUND_ROTATION_LERP_SPEED := 10.0
const DEFAULT_GROUND_INFLUENCE_BLEND_SPEED := 8.0
const DEFAULT_GROUND_DISABLE_SPEED := 1.8
const DEFAULT_GROUND_ALIGN_TO_NORMAL := true
const DEFAULT_PLANT_ENABLED := false
const DEFAULT_PLANT_HEIGHT_THRESHOLD := 0.045
const DEFAULT_PLANT_VERTICAL_SPEED_THRESHOLD := 0.18
const DEFAULT_PLANT_RELEASE_DISTANCE := 0.16
const DEFAULT_PLANT_RELEASE_HEIGHT := 0.06
const DEFAULT_PLANT_MIN_HOLD_TIME := 0.08

@export var look_at_follow_bone_name: StringName = &"头部"
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
@export_group("Runtime Update")
@export var runtime_update_in_physics: bool = true
@export var animation_state_provider_path: NodePath = NodePath("../..")
@export var runtime_ik_enabled: bool = true
@export var state_profile_enabled: bool = true
@export_group("Editor Preview")
@export var editor_auto_follow_enabled: bool = true
@export var editor_pose_preview_enabled: bool = true
@export var hide_targets_in_game: bool = true
@export_range(0.0, 1.0, 0.01) var master_ik_weight: float = 1.0
@export var master_ik_blend_speed: float = 8.0
@export var ik_driver_physics_process_priority: int = 20
@export var skeleton_modifier_physics_process_priority: int = 30
@export var enforce_physics_modifier_callback_mode: bool = true
@export_group("State IK Multipliers")
@export var state_channel_multipliers: Dictionary = {
	"default": {
		"look": 1.0,
		"spine": 1.0,
		"arm_reach": 1.0,
		"arm_idle": 1.0,
		"leg_ground": 1.0,
		"hand_rot": 1.0,
	},
	"Idle": {
		"look": 1.0,
		"spine": 1.0,
		"arm_reach": 1.0,
		"arm_idle": 1.0,
		"leg_ground": 1.0,
		"hand_rot": 1.0,
	},
	"Walk": {
		"look": 0.65,
		"spine": 0.2,
		"arm_reach": 0.65,
		"arm_idle": 0.35,
		"leg_ground": 0.55,
		"hand_rot": 0.6,
	},
	"LeftTurn": {
		"look": 0.5,
		"spine": 0.35,
		"arm_reach": 0.45,
		"arm_idle": 0.3,
		"leg_ground": 0.0,
		"hand_rot": 0.5,
	},
	"RightTurn": {
		"look": 0.5,
		"spine": 0.35,
		"arm_reach": 0.45,
		"arm_idle": 0.3,
		"leg_ground": 0.0,
		"hand_rot": 0.5,
	},
	"SitDown": {
		"look": 0.25,
		"spine": 0.0,
		"arm_reach": 0.25,
		"arm_idle": 0.0,
		"leg_ground": 0.0,
		"hand_rot": 0.3,
	},
	"SitToStand": {
		"look": 0.25,
		"spine": 0.0,
		"arm_reach": 0.25,
		"arm_idle": 0.0,
		"leg_ground": 0.0,
		"hand_rot": 0.3,
	},
	"LayDown": {
		"look": 0.2,
		"spine": 0.0,
		"arm_reach": 0.25,
		"arm_idle": 0.0,
		"leg_ground": 0.0,
		"hand_rot": 0.3,
	},
	"LayUp": {
		"look": 0.2,
		"spine": 0.0,
		"arm_reach": 0.25,
		"arm_idle": 0.0,
		"leg_ground": 0.0,
		"hand_rot": 0.3,
	},
	"SittingIdle": {
		"look": 0.35,
		"spine": 0.15,
		"arm_reach": 0.55,
		"arm_idle": 0.0,
		"leg_ground": 0.0,
		"hand_rot": 0.6,
	},
	"Laying": {
		"look": 0.3,
		"spine": 0.15,
		"arm_reach": 0.45,
		"arm_idle": 0.0,
		"leg_ground": 0.0,
		"hand_rot": 0.55,
	},
}
@export_group("Channel Blend Speeds")
@export var channel_look_blend_speed: float = 8.0
@export var channel_spine_blend_speed: float = 8.0
@export var channel_arm_reach_blend_speed: float = 8.0
@export var channel_arm_idle_blend_speed: float = 8.0
@export var channel_leg_ground_blend_speed: float = 8.0
@export var channel_hand_rot_blend_speed: float = 8.0
@export_group("Spine CCDIK")
@export var enable_spine_ccdik: bool = true
@export var spine_follow_bone_name: StringName = &"UpperChest"
@export var spine_ccdik_look_weight: float = 0.45

var skeleton: Skeleton3D
var left_hand_auto: Node3D
var right_hand_auto: Node3D
var left_hand_rot_auto: Node3D
var right_hand_rot_auto: Node3D
var left_foot_auto: Node3D
var right_foot_auto: Node3D
var spine_bend_auto: Node3D
var look_at_auto: Node3D
var left_elbow_pole_auto: Node3D
var right_elbow_pole_auto: Node3D
var left_knee_pole_auto: Node3D
var right_knee_pole_auto: Node3D
var left_hand_target: Node3D
var right_hand_target: Node3D
var left_hand_rot_target: Node3D
var right_hand_rot_target: Node3D
var left_foot_target: Node3D
var right_foot_target: Node3D
var spine_bend_target: Node3D
var left_elbow_pole_target: Node3D
var right_elbow_pole_target: Node3D
var left_knee_pole_target: Node3D
var right_knee_pole_target: Node3D
var mark_look_at_target: Node3D
var head_look_at: LookAtModifier3D
var left_arm_ik: TwoBoneIK3D
var right_arm_ik: TwoBoneIK3D
var left_leg_ik: TwoBoneIK3D
var right_leg_ik: TwoBoneIK3D
var spine_ccdik: CCDIK3D
var left_hand_copy_rotation: CopyTransformModifier3D
var right_hand_copy_rotation: CopyTransformModifier3D

var _owner_body: CharacterBody3D
var _left_leg_auto_weight: float = 0.0
var _right_leg_auto_weight: float = 0.0
var _animation_state_provider: Node
var _channel_runtime_weights: Dictionary = {}
var _channel_smoothed_weights: Dictionary = {}
var _channel_state_weights: Dictionary = {}
var _active_master_weight: float = 1.0

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
var spine_follow_bone: int = -1
var look_at_follow_bone: int = -1

var _left_elbow_pole_profile: Dictionary = {}
var _right_elbow_pole_profile: Dictionary = {}
var _left_knee_pole_profile: Dictionary = {}
var _right_knee_pole_profile: Dictionary = {}
var _left_ground_foot_profile: Dictionary = {}
var _right_ground_foot_profile: Dictionary = {}
var _left_foot_plant_state: Dictionary = {}
var _right_foot_plant_state: Dictionary = {}

var left_hand_target_base: Transform3D
var right_hand_target_base: Transform3D
var left_hand_rot_target_base: Transform3D
var right_hand_rot_target_base: Transform3D
var left_foot_target_base: Transform3D
var right_foot_target_base: Transform3D
var spine_bend_target_base: Transform3D
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
var _initialized: bool = false

func _ready() -> void:
	_initialize_driver()

func _initialize_driver() -> bool:
	_ensure_target_nodes()
	_resolve_scene_references()
	if skeleton == null:
		push_warning("IKTargetDriver could not find sibling GeneralSkeleton.")
		_initialized = false
		return false

	if _channel_runtime_weights.is_empty() or _channel_smoothed_weights.is_empty() or _channel_state_weights.is_empty():
		_initialize_channel_weights()
	_resolve_animation_state_provider()
	_owner_body = _resolve_owner_body()
	_cache_bones()
	_cache_pole_profiles()
	_ensure_ground_foot_state_defaults()
	_cache_ground_foot_profiles()
	_clear_foot_plant_lock(_left_foot_plant_state)
	_clear_foot_plant_lock(_right_foot_plant_state)
	_remember_foot_auto_origin(_left_foot_plant_state, left_foot_auto)
	_remember_foot_auto_origin(_right_foot_plant_state, right_foot_auto)
	_cache_base_target_transforms()
	_initialized = true
	_sync_helper_visibility()
	if not skeleton.pose_updated.is_connected(_on_skeleton_pose_updated):
		skeleton.pose_updated.connect(_on_skeleton_pose_updated)
	refresh_editor_targets()
	_apply_idle_arm_offsets(0.0)
	_configure_runtime_order()
	_sync_update_callbacks()
	return true

func _ensure_target_nodes() -> void:
	var created_any := false
	created_any = _ensure_auto_target_pair("LeftHandAuto", "LeftHandTarget") or created_any
	created_any = _ensure_auto_target_pair("RightHandAuto", "RightHandTarget") or created_any
	created_any = _ensure_auto_target_pair("LeftHandRotAuto", "LeftHandRotTarget") or created_any
	created_any = _ensure_auto_target_pair("RightHandRotAuto", "RightHandRotTarget") or created_any
	created_any = _ensure_auto_target_pair("LeftFootAuto", "LeftFootTarget") or created_any
	created_any = _ensure_auto_target_pair("RightFootAuto", "RightFootTarget") or created_any
	created_any = _ensure_auto_target_pair("SpineBendAuto", "SpineBendTarget") or created_any
	created_any = _ensure_auto_target_pair("LookAtAuto", "mark3d") or created_any
	created_any = _ensure_auto_target_pair("LeftElbowPoleAuto", "LeftElbowPoleTarget") or created_any
	created_any = _ensure_auto_target_pair("RightElbowPoleAuto", "RightElbowPoleTarget") or created_any
	created_any = _ensure_auto_target_pair("LeftKneePoleAuto", "LeftKneePoleTarget") or created_any
	created_any = _ensure_auto_target_pair("RightKneePoleAuto", "RightKneePoleTarget") or created_any
	if created_any:
		_initialized = false

func _ensure_auto_target_pair(auto_name: String, target_name: String) -> bool:
	var created_any := false
	var auto_node := get_node_or_null(auto_name) as Node3D
	if auto_node == null:
		auto_node = Node3D.new()
		auto_node.name = auto_name
		add_child(auto_node)
		auto_node.owner = owner if owner != null else self
		created_any = true

	var target_node := auto_node.get_node_or_null(target_name) as Node3D
	if target_node == null:
		var marker := Marker3D.new()
		marker.name = target_name
		auto_node.add_child(marker)
		marker.owner = owner if owner != null else self
		created_any = true
	return created_any

func _resolve_scene_references() -> void:
	skeleton = get_parent().get_node_or_null("GeneralSkeleton") as Skeleton3D
	left_hand_auto = get_node_or_null("LeftHandAuto") as Node3D
	right_hand_auto = get_node_or_null("RightHandAuto") as Node3D
	left_hand_rot_auto = get_node_or_null("LeftHandRotAuto") as Node3D
	right_hand_rot_auto = get_node_or_null("RightHandRotAuto") as Node3D
	left_foot_auto = get_node_or_null("LeftFootAuto") as Node3D
	right_foot_auto = get_node_or_null("RightFootAuto") as Node3D
	spine_bend_auto = get_node_or_null("SpineBendAuto") as Node3D
	look_at_auto = get_node_or_null("LookAtAuto") as Node3D
	left_elbow_pole_auto = get_node_or_null("LeftElbowPoleAuto") as Node3D
	right_elbow_pole_auto = get_node_or_null("RightElbowPoleAuto") as Node3D
	left_knee_pole_auto = get_node_or_null("LeftKneePoleAuto") as Node3D
	right_knee_pole_auto = get_node_or_null("RightKneePoleAuto") as Node3D
	left_hand_target = get_node_or_null("LeftHandAuto/LeftHandTarget") as Node3D
	right_hand_target = get_node_or_null("RightHandAuto/RightHandTarget") as Node3D
	left_hand_rot_target = get_node_or_null("LeftHandRotAuto/LeftHandRotTarget") as Node3D
	right_hand_rot_target = get_node_or_null("RightHandRotAuto/RightHandRotTarget") as Node3D
	left_foot_target = get_node_or_null("LeftFootAuto/LeftFootTarget") as Node3D
	right_foot_target = get_node_or_null("RightFootAuto/RightFootTarget") as Node3D
	spine_bend_target = get_node_or_null("SpineBendAuto/SpineBendTarget") as Node3D
	left_elbow_pole_target = get_node_or_null("LeftElbowPoleAuto/LeftElbowPoleTarget") as Node3D
	right_elbow_pole_target = get_node_or_null("RightElbowPoleAuto/RightElbowPoleTarget") as Node3D
	left_knee_pole_target = get_node_or_null("LeftKneePoleAuto/LeftKneePoleTarget") as Node3D
	right_knee_pole_target = get_node_or_null("RightKneePoleAuto/RightKneePoleTarget") as Node3D
	mark_look_at_target = get_node_or_null("LookAtAuto/mark3d") as Node3D
	head_look_at = get_parent().get_node_or_null("GeneralSkeleton/HeadLookAt") as LookAtModifier3D
	left_arm_ik = get_parent().get_node_or_null("GeneralSkeleton/LeftArmIK") as TwoBoneIK3D
	right_arm_ik = get_parent().get_node_or_null("GeneralSkeleton/RightArmIK") as TwoBoneIK3D
	left_leg_ik = get_parent().get_node_or_null("GeneralSkeleton/LeftLegIK") as TwoBoneIK3D
	right_leg_ik = get_parent().get_node_or_null("GeneralSkeleton/RightLegIK") as TwoBoneIK3D
	spine_ccdik = get_parent().get_node_or_null("GeneralSkeleton/SpineCCDIK") as CCDIK3D
	left_hand_copy_rotation = get_parent().get_node_or_null("GeneralSkeleton/LeftHandCopyRotation") as CopyTransformModifier3D
	right_hand_copy_rotation = get_parent().get_node_or_null("GeneralSkeleton/RightHandCopyRotation") as CopyTransformModifier3D

func _ensure_initialized() -> bool:
	if _initialized and skeleton != null and is_instance_valid(skeleton):
		return true
	return _initialize_driver()

func _process(delta: float) -> void:
	if not _ensure_initialized():
		return
	if skeleton == null:
		return
	_sync_helper_visibility()
	if Engine.is_editor_hint():
		if editor_auto_follow_enabled:
			refresh_editor_targets()
		if editor_pose_preview_enabled:
			_update_channel_weights(0.0)
			if auto_manage_influence:
				_update_modifier_influence()
		return
	if runtime_update_in_physics:
		return
	_run_runtime_update(delta)

func _physics_process(delta: float) -> void:
	if not _ensure_initialized():
		return
	if skeleton == null:
		return
	if Engine.is_editor_hint() or not runtime_update_in_physics:
		return
	_run_runtime_update(delta)

func _run_runtime_update(delta: float) -> void:
	if not _ensure_initialized():
		return
	_resolve_animation_state_provider()
	_update_channel_weights(delta)
	if _idle_arm_offset_dirty or _idle_arm_offset_weight > EPSILON or _idle_arm_offset_target_weight > EPSILON:
		_apply_idle_arm_offsets(delta)
	_update_ground_foot_targets(delta)
	_update_marker_interaction(delta)
	if auto_manage_influence:
		_update_modifier_influence()

func _exit_tree() -> void:
	_initialized = false
	if skeleton != null and skeleton.pose_updated.is_connected(_on_skeleton_pose_updated):
		skeleton.pose_updated.disconnect(_on_skeleton_pose_updated)

func _sync_update_callbacks() -> void:
	if Engine.is_editor_hint():
		set_process(true)
		set_physics_process(false)
		return
	set_process(not runtime_update_in_physics)
	set_physics_process(runtime_update_in_physics)

func _sync_helper_visibility() -> void:
	visible = Engine.is_editor_hint() or not hide_targets_in_game

func refresh_editor_targets() -> void:
	if not _ensure_initialized():
		return
	_cache_pole_profiles()
	_cache_ground_foot_profiles()
	_on_skeleton_pose_updated()

func _configure_runtime_order() -> void:
	set_process_priority(ik_driver_physics_process_priority)
	set_physics_process_priority(ik_driver_physics_process_priority)
	if skeleton == null:
		return
	skeleton.set_physics_process_priority(skeleton_modifier_physics_process_priority)
	if runtime_update_in_physics and enforce_physics_modifier_callback_mode:
		skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS

func _initialize_channel_weights() -> void:
	for channel in IK_CHANNELS:
		_channel_runtime_weights[channel] = 1.0
		_channel_smoothed_weights[channel] = 1.0
		_channel_state_weights[channel] = 1.0
	_active_master_weight = clampf(master_ik_weight, 0.0, 1.0)

func _resolve_animation_state_provider() -> void:
	if Engine.is_editor_hint():
		_animation_state_provider = null
		return
	if _animation_state_provider != null and is_instance_valid(_animation_state_provider):
		return
	if animation_state_provider_path != NodePath():
		var provider := get_node_or_null(animation_state_provider_path)
		if provider != null:
			_animation_state_provider = provider
			return
	var fallback := get_parent()
	if fallback != null and fallback.get_parent() != null:
		_animation_state_provider = fallback.get_parent()

func _get_animation_state_name() -> StringName:
	if Engine.is_editor_hint():
		return &""
	if _animation_state_provider == null or not is_instance_valid(_animation_state_provider):
		return &""
	if _animation_state_provider.has_method("get_current_state_name"):
		var raw_state: Variant = _animation_state_provider.call("get_current_state_name")
		if raw_state is StringName:
			return raw_state as StringName
		if raw_state is String:
			return StringName(String(raw_state))
	return &""

func _update_channel_weights(delta: float) -> void:
	var state_name := _get_animation_state_name()
	var state_multiplier_enabled := state_profile_enabled and not state_channel_multipliers.is_empty()
	var master_target := clampf(master_ik_weight, 0.0, 1.0)
	if not runtime_ik_enabled:
		master_target = 0.0
	var master_step := maxf(master_ik_blend_speed, 0.0) * maxf(delta, 0.0)
	if master_step > 0.0:
		_active_master_weight = move_toward(_active_master_weight, master_target, master_step)
	else:
		_active_master_weight = master_target

	for channel in IK_CHANNELS:
		var runtime_multiplier := float(_channel_runtime_weights.get(channel, 1.0))
		var state_multiplier := 1.0
		if state_multiplier_enabled:
			state_multiplier = _get_state_channel_multiplier(state_name, channel)
		_channel_state_weights[channel] = state_multiplier

		var target := clampf(_active_master_weight * runtime_multiplier * state_multiplier, 0.0, 1.0)
		var current := float(_channel_smoothed_weights.get(channel, 1.0))
		var speed := _get_channel_blend_speed(channel)
		var step := maxf(speed, 0.0) * maxf(delta, 0.0)
		if step > 0.0:
			current = move_toward(current, target, step)
		else:
			current = target
		_channel_smoothed_weights[channel] = current

func _get_state_channel_multiplier(state_name: StringName, channel: StringName) -> float:
	if state_channel_multipliers.is_empty():
		return 1.0
	var state_key := String(state_name)
	var channel_key := String(channel)
	var profile := _get_state_profile(state_key)
	if profile.is_empty():
		profile = _get_state_profile(String(STATE_PROFILE_DEFAULT))
	if profile.is_empty():
		return 1.0
	return clampf(_read_dict_float(profile, channel_key, 1.0), 0.0, 1.0)

func _get_state_profile(state_key: String) -> Dictionary:
	if state_key.is_empty():
		return {}
	if state_channel_multipliers.has(state_key):
		var direct: Variant = state_channel_multipliers[state_key]
		if direct is Dictionary:
			return direct as Dictionary
	var state_key_lower := state_key.to_lower()
	for key in state_channel_multipliers.keys():
		if String(key).to_lower() == state_key_lower:
			var profile: Variant = state_channel_multipliers[key]
			if profile is Dictionary:
				return profile as Dictionary
	return {}

func _read_dict_float(source: Dictionary, key: String, fallback: float) -> float:
	if source.has(key):
		return float(source[key])
	var key_lower := key.to_lower()
	for source_key in source.keys():
		if String(source_key).to_lower() == key_lower:
			return float(source[source_key])
	return fallback

func _get_channel_blend_speed(channel: StringName) -> float:
	match channel:
		IK_CHANNEL_LOOK:
			return channel_look_blend_speed
		IK_CHANNEL_SPINE:
			return channel_spine_blend_speed
		IK_CHANNEL_ARM_REACH:
			return channel_arm_reach_blend_speed
		IK_CHANNEL_ARM_IDLE:
			return channel_arm_idle_blend_speed
		IK_CHANNEL_LEG_GROUND:
			return channel_leg_ground_blend_speed
		IK_CHANNEL_HAND_ROT:
			return channel_hand_rot_blend_speed
		_:
			return master_ik_blend_speed

func _normalize_channel_name(channel: StringName) -> StringName:
	var key := String(channel).strip_edges().to_lower()
	match key:
		"look":
			return IK_CHANNEL_LOOK
		"spine":
			return IK_CHANNEL_SPINE
		"arm_reach":
			return IK_CHANNEL_ARM_REACH
		"arm_idle":
			return IK_CHANNEL_ARM_IDLE
		"leg_ground":
			return IK_CHANNEL_LEG_GROUND
		"hand_rot":
			return IK_CHANNEL_HAND_ROT
		_:
			return &""

func _get_channel_weight(channel: StringName) -> float:
	return clampf(float(_channel_smoothed_weights.get(channel, 1.0)), 0.0, 1.0)

func set_channel_weight(channel: StringName, weight: float) -> void:
	var normalized := _normalize_channel_name(channel)
	if normalized == &"":
		return
	_channel_runtime_weights[normalized] = clampf(weight, 0.0, 1.0)

func set_runtime_ik_enabled(enabled: bool) -> void:
	runtime_ik_enabled = enabled
	if not auto_manage_influence:
		return
	if not runtime_ik_enabled:
		_set_all_modifier_influence(0.0)
	else:
		_update_modifier_influence()

func set_state_profile_enabled(enabled: bool) -> void:
	state_profile_enabled = enabled
	if auto_manage_influence:
		_update_modifier_influence()

func _cache_bones() -> void:
	left_upper_arm_bone = _read_two_bone_setting_int(left_arm_ik, "root_bone", "LeftUpperArm")
	left_lower_arm_bone = _read_two_bone_setting_int(left_arm_ik, "middle_bone", "LeftLowerArm")
	left_hand_bone = _read_two_bone_setting_int(left_arm_ik, "end_bone", "LeftHand")
	right_upper_arm_bone = _read_two_bone_setting_int(right_arm_ik, "root_bone", "RightUpperArm")
	right_lower_arm_bone = _read_two_bone_setting_int(right_arm_ik, "middle_bone", "RightLowerArm")
	right_hand_bone = _read_two_bone_setting_int(right_arm_ik, "end_bone", "RightHand")
	left_upper_leg_bone = _read_two_bone_setting_int(left_leg_ik, "root_bone", "LeftUpperLeg")
	left_lower_leg_bone = _read_two_bone_setting_int(left_leg_ik, "middle_bone", "LeftLowerLeg")
	left_foot_bone = _read_two_bone_setting_int(left_leg_ik, "end_bone", "LeftFoot")
	right_upper_leg_bone = _read_two_bone_setting_int(right_leg_ik, "root_bone", "RightUpperLeg")
	right_lower_leg_bone = _read_two_bone_setting_int(right_leg_ik, "middle_bone", "RightLowerLeg")
	right_foot_bone = _read_two_bone_setting_int(right_leg_ik, "end_bone", "RightFoot")

	spine_follow_bone = _read_ccdik_setting_int(spine_ccdik, "end_bone", String(spine_follow_bone_name))
	if spine_follow_bone == -1:
		spine_follow_bone = _find_bone_fallback(["UpperChest", "Chest"])

	look_at_follow_bone = _read_look_at_bone(head_look_at, String(look_at_follow_bone_name))
	if look_at_follow_bone == -1:
		look_at_follow_bone = _find_bone_fallback(["头部", "Head"])
	if look_at_follow_bone == -1:
		push_warning("IKTargetDriver could not find a LookAt follow bone.")

func _read_two_bone_setting_int(modifier: TwoBoneIK3D, key: String, fallback_bone_name: String) -> int:
	if modifier != null:
		var setting_key := "settings/0/%s" % key
		var raw_value: Variant = modifier.get(setting_key)
		if raw_value != null:
			var bone_idx := int(raw_value)
			if bone_idx >= 0:
				return bone_idx
	return skeleton.find_bone(fallback_bone_name)

func _read_ccdik_setting_int(modifier: CCDIK3D, key: String, fallback_bone_name: String) -> int:
	if modifier != null:
		var setting_key := "settings/0/%s" % key
		var raw_value: Variant = modifier.get(setting_key)
		if raw_value != null:
			var bone_idx := int(raw_value)
			if bone_idx >= 0:
				return bone_idx
	if fallback_bone_name.is_empty():
		return -1
	return skeleton.find_bone(fallback_bone_name)

func _read_look_at_bone(modifier: LookAtModifier3D, fallback_bone_name: String) -> int:
	if modifier != null:
		var bone_idx := int(modifier.get("bone"))
		if bone_idx >= 0:
			return bone_idx
		var bone_name := String(modifier.get("bone_name"))
		if not bone_name.is_empty():
			var resolved := skeleton.find_bone(bone_name)
			if resolved >= 0:
				return resolved
	if fallback_bone_name.is_empty():
		return -1
	return skeleton.find_bone(fallback_bone_name)

func _find_bone_fallback(candidates: Array[String]) -> int:
	for bone_name in candidates:
		var bone_idx := skeleton.find_bone(bone_name)
		if bone_idx >= 0:
			return bone_idx
	return -1

func _cache_pole_profiles() -> void:
	_left_elbow_pole_profile = _build_pole_profile(left_elbow_pole_auto, left_arm_ik, left_upper_arm_bone, left_lower_arm_bone, left_hand_bone, DEFAULT_ELBOW_POLE_DISTANCE_SCALE)
	_right_elbow_pole_profile = _build_pole_profile(right_elbow_pole_auto, right_arm_ik, right_upper_arm_bone, right_lower_arm_bone, right_hand_bone, DEFAULT_ELBOW_POLE_DISTANCE_SCALE)
	_left_knee_pole_profile = _build_pole_profile(left_knee_pole_auto, left_leg_ik, left_upper_leg_bone, left_lower_leg_bone, left_foot_bone, DEFAULT_KNEE_POLE_DISTANCE_SCALE)
	_right_knee_pole_profile = _build_pole_profile(right_knee_pole_auto, right_leg_ik, right_upper_leg_bone, right_lower_leg_bone, right_foot_bone, DEFAULT_KNEE_POLE_DISTANCE_SCALE)

func _build_pole_profile(target: Node3D, modifier: TwoBoneIK3D, root_bone_idx: int, middle_bone_idx: int, end_bone_idx: int, default_distance_scale: float) -> Dictionary:
	var profile := {
		"distance_scale": default_distance_scale,
		"fallback_local": Vector3.FORWARD,
	}
	if modifier != null:
		profile["distance_scale"] = _read_two_bone_meta_float(modifier, META_NODE_POLE_DISTANCE_SCALE, default_distance_scale)
		var meta_fallback := _read_two_bone_meta_vector3(modifier, META_NODE_POLE_FALLBACK_LOCAL, Vector3.ZERO)
		if meta_fallback.length_squared() > EPSILON:
			profile["fallback_local"] = meta_fallback.normalized()

	if target == null or root_bone_idx == -1 or middle_bone_idx == -1 or end_bone_idx == -1:
		return profile

	var root_transform: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(root_bone_idx)
	var middle_transform: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(middle_bone_idx)
	var end_transform: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(end_bone_idx)
	var upper_len: float = (middle_transform.origin - root_transform.origin).length()
	var lower_len: float = (end_transform.origin - middle_transform.origin).length()
	var max_len: float = maxf(maxf(upper_len, lower_len), EPSILON)
	var current_distance: float = (target.global_transform.origin - middle_transform.origin).length()
	if current_distance > EPSILON and not (modifier != null and modifier.has_meta(META_NODE_POLE_DISTANCE_SCALE)):
		profile["distance_scale"] = clampf(current_distance / max_len, 0.05, 4.0)

	var fallback_world: Vector3 = target.global_transform.origin - middle_transform.origin
	if fallback_world.length_squared() > EPSILON and not (modifier != null and modifier.has_meta(META_NODE_POLE_FALLBACK_LOCAL)):
		profile["fallback_local"] = (root_transform.basis.inverse() * fallback_world.normalized()).normalized()
	elif modifier != null and (profile["fallback_local"] as Vector3).length_squared() <= EPSILON:
		var secondary_dir := int(modifier.get("settings/0/pole_direction"))
		profile["fallback_local"] = _secondary_direction_to_local_axis(secondary_dir)

	return profile

func _read_two_bone_meta_float(modifier: TwoBoneIK3D, key: StringName, fallback: float) -> float:
	if modifier == null or not modifier.has_meta(key):
		return fallback
	return float(modifier.get_meta(key))

func _read_two_bone_meta_int(modifier: TwoBoneIK3D, key: StringName, fallback: int) -> int:
	if modifier == null or not modifier.has_meta(key):
		return fallback
	return int(modifier.get_meta(key))

func _read_two_bone_meta_bool(modifier: TwoBoneIK3D, key: StringName, fallback: bool) -> bool:
	if modifier == null or not modifier.has_meta(key):
		return fallback
	return bool(modifier.get_meta(key))

func _read_two_bone_meta_vector3(modifier: TwoBoneIK3D, key: StringName, fallback: Vector3) -> Vector3:
	if modifier == null or not modifier.has_meta(key):
		return fallback
	var raw_value: Variant = modifier.get_meta(key)
	if raw_value is Vector3:
		return raw_value as Vector3
	return fallback

func _ensure_ground_foot_state_defaults() -> void:
	if _left_foot_plant_state.is_empty():
		_left_foot_plant_state = _make_ground_foot_state()
	if _right_foot_plant_state.is_empty():
		_right_foot_plant_state = _make_ground_foot_state()

func _make_ground_foot_state() -> Dictionary:
	return {
		"planted": false,
		"lock_transform": Transform3D.IDENTITY,
		"last_auto_origin": Vector3.ZERO,
		"has_last_auto": false,
		"plant_time": 0.0,
	}

func _cache_ground_foot_profiles() -> void:
	_left_ground_foot_profile = _build_ground_foot_profile(left_leg_ik)
	_right_ground_foot_profile = _build_ground_foot_profile(right_leg_ik)

func _build_ground_foot_profile(modifier: TwoBoneIK3D) -> Dictionary:
	return {
		"auto_enabled": _read_two_bone_meta_bool(modifier, META_NODE_GROUND_FOOT_AUTO, false),
		"collision_mask": _read_two_bone_meta_int(modifier, META_NODE_GROUND_COLLISION_MASK, DEFAULT_GROUND_COLLISION_MASK),
		"raycast_up": maxf(_read_two_bone_meta_float(modifier, META_NODE_GROUND_RAYCAST_UP, DEFAULT_GROUND_RAYCAST_UP), 0.01),
		"raycast_down": maxf(_read_two_bone_meta_float(modifier, META_NODE_GROUND_RAYCAST_DOWN, DEFAULT_GROUND_RAYCAST_DOWN), 0.05),
		"foot_height": _read_two_bone_meta_float(modifier, META_NODE_GROUND_FOOT_HEIGHT, DEFAULT_GROUND_FOOT_HEIGHT),
		"max_target_distance": maxf(_read_two_bone_meta_float(modifier, META_NODE_GROUND_MAX_TARGET_DISTANCE, DEFAULT_GROUND_MAX_TARGET_DISTANCE), 0.0),
		"position_lerp_speed": maxf(_read_two_bone_meta_float(modifier, META_NODE_GROUND_POSITION_LERP_SPEED, DEFAULT_GROUND_POSITION_LERP_SPEED), 0.0),
		"rotation_lerp_speed": maxf(_read_two_bone_meta_float(modifier, META_NODE_GROUND_ROTATION_LERP_SPEED, DEFAULT_GROUND_ROTATION_LERP_SPEED), 0.0),
		"influence_blend_speed": maxf(_read_two_bone_meta_float(modifier, META_NODE_GROUND_INFLUENCE_BLEND_SPEED, DEFAULT_GROUND_INFLUENCE_BLEND_SPEED), 0.0),
		"disable_speed": maxf(_read_two_bone_meta_float(modifier, META_NODE_GROUND_DISABLE_SPEED, DEFAULT_GROUND_DISABLE_SPEED), 0.0),
		"align_to_normal": _read_two_bone_meta_bool(modifier, META_NODE_GROUND_ALIGN_TO_NORMAL, DEFAULT_GROUND_ALIGN_TO_NORMAL),
		"plant_enabled": _read_two_bone_meta_bool(modifier, META_NODE_PLANT_ENABLED, DEFAULT_PLANT_ENABLED),
		"plant_height_threshold": maxf(_read_two_bone_meta_float(modifier, META_NODE_PLANT_HEIGHT_THRESHOLD, DEFAULT_PLANT_HEIGHT_THRESHOLD), 0.0),
		"plant_vertical_speed_threshold": maxf(_read_two_bone_meta_float(modifier, META_NODE_PLANT_VERTICAL_SPEED_THRESHOLD, DEFAULT_PLANT_VERTICAL_SPEED_THRESHOLD), 0.0),
		"plant_release_distance": maxf(_read_two_bone_meta_float(modifier, META_NODE_PLANT_RELEASE_DISTANCE, DEFAULT_PLANT_RELEASE_DISTANCE), 0.0),
		"plant_release_height": maxf(_read_two_bone_meta_float(modifier, META_NODE_PLANT_RELEASE_HEIGHT, DEFAULT_PLANT_RELEASE_HEIGHT), 0.0),
		"plant_min_hold_time": maxf(_read_two_bone_meta_float(modifier, META_NODE_PLANT_MIN_HOLD_TIME, DEFAULT_PLANT_MIN_HOLD_TIME), 0.0),
	}

func _secondary_direction_to_local_axis(secondary_direction: int) -> Vector3:
	match secondary_direction:
		1:
			return Vector3.RIGHT
		2:
			return Vector3.LEFT
		3:
			return Vector3.UP
		4:
			return Vector3.DOWN
		5:
			return Vector3.BACK
		6:
			return Vector3.FORWARD
		_:
			return Vector3.FORWARD

func _read_node_meta_float(node: Node, key: StringName, fallback: float) -> float:
	if node == null or not node.has_meta(key):
		return fallback
	return float(node.get_meta(key))

func _on_skeleton_pose_updated() -> void:
	if not _ensure_initialized():
		return
	_set_auto_from_bone(left_hand_auto, left_hand_bone)
	_set_auto_from_bone(right_hand_auto, right_hand_bone)
	_set_auto_from_bone(left_hand_rot_auto, left_hand_bone)
	_set_auto_from_bone(right_hand_rot_auto, right_hand_bone)
	_set_auto_from_bone(left_foot_auto, left_foot_bone)
	_set_auto_from_bone(right_foot_auto, right_foot_bone)
	_set_auto_from_bone(spine_bend_auto, spine_follow_bone)
	var look_forward_offset := _read_node_meta_float(look_at_auto, META_NODE_FORWARD_OFFSET, 0.0)
	_set_auto_from_bone_with_forward_offset(look_at_auto, look_at_follow_bone, look_forward_offset)

	_update_pole_auto(left_elbow_pole_auto, left_upper_arm_bone, left_lower_arm_bone, left_hand_bone, _left_elbow_pole_profile)
	_update_pole_auto(right_elbow_pole_auto, right_upper_arm_bone, right_lower_arm_bone, right_hand_bone, _right_elbow_pole_profile)
	_update_pole_auto(left_knee_pole_auto, left_upper_leg_bone, left_lower_leg_bone, left_foot_bone, _left_knee_pole_profile)
	_update_pole_auto(right_knee_pole_auto, right_upper_leg_bone, right_lower_leg_bone, right_foot_bone, _right_knee_pole_profile)

func _set_auto_from_bone(target: Node3D, bone_idx: int) -> void:
	if target == null or bone_idx == -1:
		return
	var bone_global: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)
	target.global_transform = bone_global

func _set_auto_from_bone_with_forward_offset(target: Node3D, bone_idx: int, forward_offset: float) -> void:
	if target == null or bone_idx == -1:
		return

	var bone_global: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)
	var forward: Vector3 = -bone_global.basis.z.normalized()
	bone_global.origin += forward * forward_offset
	target.global_transform = bone_global

func _update_pole_auto(target: Node3D, root_bone_idx: int, middle_bone_idx: int, end_bone_idx: int, profile: Dictionary) -> void:
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
	var distance_scale := clampf(float(profile.get("distance_scale", 1.0)), 0.05, 4.0)
	var fallback_local := profile.get("fallback_local", Vector3.FORWARD) as Vector3
	if fallback_local.length_squared() <= EPSILON:
		fallback_local = Vector3.FORWARD
	var fallback_direction: Vector3 = (root_transform.basis * fallback_local).normalized()
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
	spine_bend_target_base = _safe_local_transform(spine_bend_target)
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
		_blend_spine_target_towards(look_world)
	else:
		_blend_to_base_global(mark_look_at_target, mark_look_at_target_base, false, true)
		_blend_to_base_global(spine_bend_target, spine_bend_target_base, false, true)

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
	_restore_local_transform(spine_bend_target, spine_bend_target_base)
	_restore_local_transform(left_hand_rot_target, left_hand_rot_target_base)
	_restore_local_transform(right_hand_rot_target, right_hand_rot_target_base)
	_apply_arm_target_offsets(_idle_arm_offset_weight)
	if auto_manage_influence:
		_update_modifier_influence()

func _blend_spine_target_towards(look_world: Vector3) -> void:
	if spine_bend_target == null:
		return
	var parent_node := spine_bend_target.get_parent_node_3d()
	if parent_node == null:
		return
	var base_global: Transform3D = parent_node.global_transform * spine_bend_target_base
	var weight := clampf(spine_ccdik_look_weight, 0.0, 1.0)
	var spine_world: Vector3 = base_global.origin.lerp(look_world, weight)
	_blend_global_pose(spine_bend_target, spine_bend_target_base, spine_world, Basis.IDENTITY, false, true)

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

func _update_ground_foot_targets(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	var leg_ground_channel_weight := _get_channel_weight(IK_CHANNEL_LEG_GROUND)
	var left_manual := _has_position_offset(left_foot_target, left_foot_target_base) or _has_position_offset(left_knee_pole_target, left_knee_pole_target_base)
	var right_manual := _has_position_offset(right_foot_target, right_foot_target_base) or _has_position_offset(right_knee_pole_target, right_knee_pole_target_base)
	var left_blend_step := _get_ground_profile_float(_left_ground_foot_profile, "influence_blend_speed", DEFAULT_GROUND_INFLUENCE_BLEND_SPEED) * maxf(delta, 0.0)
	var right_blend_step := _get_ground_profile_float(_right_ground_foot_profile, "influence_blend_speed", DEFAULT_GROUND_INFLUENCE_BLEND_SPEED) * maxf(delta, 0.0)
	if leg_ground_channel_weight <= EPSILON:
		_clear_foot_plant_lock(_left_foot_plant_state)
		_clear_foot_plant_lock(_right_foot_plant_state)
		if not left_manual:
			_move_target_to_base(left_foot_target, left_foot_target_base, _left_ground_foot_profile, delta)
		if not right_manual:
			_move_target_to_base(right_foot_target, right_foot_target_base, _right_ground_foot_profile, delta)
		_left_leg_auto_weight = move_toward(_left_leg_auto_weight, 0.0, left_blend_step)
		_right_leg_auto_weight = move_toward(_right_leg_auto_weight, 0.0, right_blend_step)
		if auto_manage_influence:
			_update_modifier_influence()
		return

	if _owner_body == null or not is_instance_valid(_owner_body):
		_owner_body = _resolve_owner_body()

	var left_active := _update_ground_leg_target(left_foot_target, left_foot_target_base, left_foot_auto, left_leg_ik, _left_ground_foot_profile, _left_foot_plant_state, left_manual, delta)
	var right_active := _update_ground_leg_target(right_foot_target, right_foot_target_base, right_foot_auto, right_leg_ik, _right_ground_foot_profile, _right_foot_plant_state, right_manual, delta)

	_left_leg_auto_weight = move_toward(_left_leg_auto_weight, 1.0 if left_active else 0.0, left_blend_step)
	_right_leg_auto_weight = move_toward(_right_leg_auto_weight, 1.0 if right_active else 0.0, right_blend_step)

	if auto_manage_influence:
		_update_modifier_influence()

func _is_leg_ground_auto_enabled(modifier: TwoBoneIK3D) -> bool:
	if modifier == null or not modifier.has_meta(META_NODE_GROUND_FOOT_AUTO):
		return false
	return bool(modifier.get_meta(META_NODE_GROUND_FOOT_AUTO))

func _update_ground_leg_target(target_node: Node3D, base_local: Transform3D, foot_auto_node: Node3D, modifier: TwoBoneIK3D, profile: Dictionary, plant_state: Dictionary, manual_active: bool, delta: float) -> bool:
	if target_node == null or foot_auto_node == null:
		return false
	if manual_active:
		_clear_foot_plant_lock(plant_state)
		_remember_foot_auto_origin(plant_state, foot_auto_node)
		return false
	if not _is_leg_ground_auto_enabled(modifier):
		_clear_foot_plant_lock(plant_state)
		_remember_foot_auto_origin(plant_state, foot_auto_node)
		return false

	var disable_speed := _get_ground_profile_float(profile, "disable_speed", DEFAULT_GROUND_DISABLE_SPEED)
	if disable_speed > EPSILON and _get_owner_horizontal_speed() > disable_speed:
		_clear_foot_plant_lock(plant_state)
		_remember_foot_auto_origin(plant_state, foot_auto_node)
		_move_target_to_base(target_node, base_local, profile, delta)
		return false

	var hit: Dictionary = _sample_ground_hit(foot_auto_node.global_transform.origin, profile)
	if hit.is_empty():
		_clear_foot_plant_lock(plant_state)
		_remember_foot_auto_origin(plant_state, foot_auto_node)
		_move_target_to_base(target_node, base_local, profile, delta)
		return false

	var parent_node := target_node.get_parent_node_3d()
	if parent_node == null:
		return false

	var base_global: Transform3D = parent_node.global_transform * base_local
	var desired_global := _build_ground_target_transform(base_global, hit, profile)
	_update_foot_plant_state(plant_state, foot_auto_node, desired_global, profile, delta)

	var target_global := desired_global
	if _is_foot_planted(plant_state):
		target_global = _get_foot_lock_transform(plant_state, desired_global)
	_apply_ground_target_global(target_node, target_global, profile, delta)
	return true

func _build_ground_target_transform(base_global: Transform3D, hit: Dictionary, profile: Dictionary) -> Transform3D:
	var hit_position: Vector3 = hit["position"]
	var hit_normal: Vector3 = (hit["normal"] as Vector3).normalized()
	if hit_normal.length_squared() <= EPSILON:
		hit_normal = Vector3.UP

	var desired_origin := hit_position + hit_normal * _get_ground_profile_float(profile, "foot_height", DEFAULT_GROUND_FOOT_HEIGHT)
	var desired_delta: Vector3 = desired_origin - base_global.origin
	var max_distance := _get_ground_profile_float(profile, "max_target_distance", DEFAULT_GROUND_MAX_TARGET_DISTANCE)
	if max_distance > EPSILON and desired_delta.length() > max_distance:
		desired_origin = base_global.origin + desired_delta.normalized() * max_distance

	var desired_basis := base_global.basis
	if _get_ground_profile_bool(profile, "align_to_normal", DEFAULT_GROUND_ALIGN_TO_NORMAL):
		desired_basis = _build_ground_aligned_basis(base_global.basis, hit_normal)

	return Transform3D(desired_basis, desired_origin)

func _sample_ground_hit(origin: Vector3, profile: Dictionary) -> Dictionary:
	var world_3d := get_world_3d()
	if world_3d == null:
		return {}

	var up_distance := _get_ground_profile_float(profile, "raycast_up", DEFAULT_GROUND_RAYCAST_UP)
	var down_distance := _get_ground_profile_float(profile, "raycast_down", DEFAULT_GROUND_RAYCAST_DOWN)
	var from := origin + Vector3.UP * up_distance
	var to := origin - Vector3.UP * down_distance
	var collision_mask := _get_ground_profile_int(profile, "collision_mask", DEFAULT_GROUND_COLLISION_MASK)
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if _owner_body != null and is_instance_valid(_owner_body):
		query.exclude = [_owner_body.get_rid()]
	return world_3d.direct_space_state.intersect_ray(query)

func _apply_ground_target_global(target_node: Node3D, desired_global: Transform3D, profile: Dictionary, delta: float) -> void:
	if target_node == null:
		return

	var current_global: Transform3D = target_node.global_transform
	var next_global := current_global
	var position_weight := clampf(_get_ground_profile_float(profile, "position_lerp_speed", DEFAULT_GROUND_POSITION_LERP_SPEED) * maxf(delta, 0.0), 0.0, 1.0)
	var rotation_weight := clampf(_get_ground_profile_float(profile, "rotation_lerp_speed", DEFAULT_GROUND_ROTATION_LERP_SPEED) * maxf(delta, 0.0), 0.0, 1.0)
	next_global.origin = current_global.origin.lerp(desired_global.origin, position_weight)
	next_global.basis = _slerp_basis(current_global.basis, desired_global.basis, rotation_weight)
	target_node.global_transform = next_global

func _move_target_to_base(target_node: Node3D, base_local: Transform3D, profile: Dictionary, delta: float) -> void:
	if target_node == null:
		return

	var parent_node := target_node.get_parent_node_3d()
	if parent_node == null:
		target_node.transform = target_node.transform.interpolate_with(base_local, clampf(_get_ground_profile_float(profile, "position_lerp_speed", DEFAULT_GROUND_POSITION_LERP_SPEED) * maxf(delta, 0.0), 0.0, 1.0))
		return

	var base_global: Transform3D = parent_node.global_transform * base_local
	_apply_ground_target_global(target_node, base_global, profile, delta)

func _update_foot_plant_state(state: Dictionary, foot_auto_node: Node3D, desired_global: Transform3D, profile: Dictionary, delta: float) -> void:
	if foot_auto_node == null:
		_clear_foot_plant_lock(state)
		return

	var current_auto_origin: Vector3 = foot_auto_node.global_transform.origin
	var last_auto_origin := _get_state_vector3(state, "last_auto_origin", current_auto_origin)
	var has_last_auto := bool(state.get("has_last_auto", false))
	var vertical_speed := 0.0
	if has_last_auto and delta > EPSILON:
		vertical_speed = absf(current_auto_origin.y - last_auto_origin.y) / delta

	var up_axis := desired_global.basis.y.normalized()
	if up_axis.length_squared() <= EPSILON:
		up_axis = Vector3.UP
	var distance_to_ground_target := current_auto_origin.distance_to(desired_global.origin)
	var planted := _is_foot_planted(state)
	var plant_time := _get_state_float(state, "plant_time", 0.0)

	if planted:
		plant_time += maxf(delta, 0.0)
		var lock_transform := _get_foot_lock_transform(state, desired_global)
		var release_distance := desired_global.origin.distance_to(lock_transform.origin)
		var release_height := absf((current_auto_origin - lock_transform.origin).dot(lock_transform.basis.y.normalized()))
		var min_hold_time := _get_ground_profile_float(profile, "plant_min_hold_time", DEFAULT_PLANT_MIN_HOLD_TIME)
		if plant_time >= min_hold_time:
			var release_distance_limit := _get_ground_profile_float(profile, "plant_release_distance", DEFAULT_PLANT_RELEASE_DISTANCE)
			var release_height_limit := _get_ground_profile_float(profile, "plant_release_height", DEFAULT_PLANT_RELEASE_HEIGHT)
			if release_distance > release_distance_limit or release_height > release_height_limit:
				planted = false
				plant_time = 0.0

	if not planted and _get_ground_profile_bool(profile, "plant_enabled", DEFAULT_PLANT_ENABLED):
		var height_threshold := _get_ground_profile_float(profile, "plant_height_threshold", DEFAULT_PLANT_HEIGHT_THRESHOLD)
		var vertical_speed_threshold := _get_ground_profile_float(profile, "plant_vertical_speed_threshold", DEFAULT_PLANT_VERTICAL_SPEED_THRESHOLD)
		if distance_to_ground_target <= height_threshold and vertical_speed <= vertical_speed_threshold:
			planted = true
			plant_time = 0.0
			state["lock_transform"] = desired_global

	state["planted"] = planted
	state["plant_time"] = plant_time
	state["last_auto_origin"] = current_auto_origin
	state["has_last_auto"] = true

func _clear_foot_plant_lock(state: Dictionary) -> void:
	state["planted"] = false
	state["plant_time"] = 0.0

func _remember_foot_auto_origin(state: Dictionary, foot_auto_node: Node3D) -> void:
	if foot_auto_node == null:
		state["has_last_auto"] = false
		state["last_auto_origin"] = Vector3.ZERO
		return
	state["last_auto_origin"] = foot_auto_node.global_transform.origin
	state["has_last_auto"] = true

func _is_foot_planted(state: Dictionary) -> bool:
	return bool(state.get("planted", false))

func _get_foot_lock_transform(state: Dictionary, fallback: Transform3D) -> Transform3D:
	if not state.has("lock_transform"):
		return fallback
	var raw_value: Variant = state["lock_transform"]
	if raw_value is Transform3D:
		return raw_value as Transform3D
	return fallback

func _get_state_vector3(state: Dictionary, key: String, fallback: Vector3) -> Vector3:
	if not state.has(key):
		return fallback
	var raw_value: Variant = state[key]
	if raw_value is Vector3:
		return raw_value as Vector3
	return fallback

func _get_state_float(state: Dictionary, key: String, fallback: float) -> float:
	if not state.has(key):
		return fallback
	return float(state[key])

func _get_ground_profile_float(profile: Dictionary, key: String, fallback: float) -> float:
	if not profile.has(key):
		return fallback
	return float(profile[key])

func _get_ground_profile_int(profile: Dictionary, key: String, fallback: int) -> int:
	if not profile.has(key):
		return fallback
	return int(profile[key])

func _get_ground_profile_bool(profile: Dictionary, key: String, fallback: bool) -> bool:
	if not profile.has(key):
		return fallback
	return bool(profile[key])

func _build_ground_aligned_basis(base_basis: Basis, up_direction: Vector3) -> Basis:
	var up: Vector3 = up_direction.normalized()
	if up.length_squared() <= EPSILON:
		return base_basis

	var forward: Vector3 = -base_basis.z.normalized()
	var projected_forward: Vector3 = forward - up * forward.dot(up)
	if projected_forward.length_squared() <= EPSILON:
		projected_forward = base_basis.x.cross(up)
	if projected_forward.length_squared() <= EPSILON:
		projected_forward = Vector3.FORWARD
	projected_forward = projected_forward.normalized()

	var right: Vector3 = up.cross(projected_forward).normalized()
	if right.length_squared() <= EPSILON:
		right = base_basis.x.normalized()
	return Basis(right, up, -projected_forward).orthonormalized()

func _get_owner_horizontal_speed() -> float:
	if _owner_body == null or not is_instance_valid(_owner_body):
		return 0.0
	return Vector2(_owner_body.velocity.x, _owner_body.velocity.z).length()

func _resolve_owner_body() -> CharacterBody3D:
	var cursor: Node = self
	while cursor != null:
		if cursor is CharacterBody3D:
			return cursor as CharacterBody3D
		cursor = cursor.get_parent()
	return null

func _update_modifier_influence() -> void:
	if not runtime_ik_enabled:
		_set_all_modifier_influence(0.0)
		return

	var look_channel := _get_channel_weight(IK_CHANNEL_LOOK)
	var spine_channel := _get_channel_weight(IK_CHANNEL_SPINE)
	var arm_reach_channel := _get_channel_weight(IK_CHANNEL_ARM_REACH)
	var arm_idle_channel := _get_channel_weight(IK_CHANNEL_ARM_IDLE)
	var leg_ground_channel := _get_channel_weight(IK_CHANNEL_LEG_GROUND)
	var hand_rot_channel := _get_channel_weight(IK_CHANNEL_HAND_ROT)

	var left_arm_active: bool = _has_position_offset(left_hand_target, left_hand_target_base) or _has_position_offset(left_elbow_pole_target, left_elbow_pole_target_base)
	var right_arm_active: bool = _has_position_offset(right_hand_target, right_hand_target_base) or _has_position_offset(right_elbow_pole_target, right_elbow_pole_target_base)
	var left_leg_active: bool = _has_position_offset(left_foot_target, left_foot_target_base) or _has_position_offset(left_knee_pole_target, left_knee_pole_target_base)
	var right_leg_active: bool = _has_position_offset(right_foot_target, right_foot_target_base) or _has_position_offset(right_knee_pole_target, right_knee_pole_target_base)
	var left_hand_rot_active: bool = _has_rotation_offset(left_hand_rot_target, left_hand_rot_target_base)
	var right_hand_rot_active: bool = _has_rotation_offset(right_hand_rot_target, right_hand_rot_target_base)

	var left_reach_active: bool = _interaction_left_hand_enabled and _interaction_weight > EPSILON
	var right_reach_active: bool = _interaction_right_hand_enabled and _interaction_weight > EPSILON
	var left_idle_active: bool = not left_reach_active and _idle_arm_offset_weight > EPSILON
	var right_idle_active: bool = not right_reach_active and _idle_arm_offset_weight > EPSILON

	var left_arm_weight := 0.0
	var right_arm_weight := 0.0
	if left_reach_active:
		left_arm_weight = maxf(left_arm_weight, arm_reach_channel)
	if left_idle_active:
		left_arm_weight = maxf(left_arm_weight, arm_idle_channel)
	if left_arm_weight <= EPSILON and left_arm_active:
		left_arm_weight = arm_reach_channel

	if right_reach_active:
		right_arm_weight = maxf(right_arm_weight, arm_reach_channel)
	if right_idle_active:
		right_arm_weight = maxf(right_arm_weight, arm_idle_channel)
	if right_arm_weight <= EPSILON and right_arm_active:
		right_arm_weight = arm_reach_channel

	var left_leg_manual_weight: float = 1.0 if left_leg_active else 0.0
	var right_leg_manual_weight: float = 1.0 if right_leg_active else 0.0
	var left_leg_weight: float = clampf(left_leg_manual_weight + _left_leg_auto_weight * leg_ground_channel, 0.0, 1.0)
	var right_leg_weight: float = clampf(right_leg_manual_weight + _right_leg_auto_weight * leg_ground_channel, 0.0, 1.0)

	_set_influence(left_arm_ik, (1.0 if left_arm_active else 0.0) * left_arm_weight)
	_set_influence(right_arm_ik, (1.0 if right_arm_active else 0.0) * right_arm_weight)
	_set_influence(left_leg_ik, left_leg_weight)
	_set_influence(right_leg_ik, right_leg_weight)
	_set_influence(left_hand_copy_rotation, (1.0 if left_hand_rot_active else 0.0) * hand_rot_channel)
	_set_influence(right_hand_copy_rotation, (1.0 if right_hand_rot_active else 0.0) * hand_rot_channel)

	if enable_spine_ccdik and spine_ccdik != null:
		var spine_active: bool = _has_position_offset(spine_bend_target, spine_bend_target_base)
		var spine_weight := 0.0
		if spine_active:
			if _interaction_look_enabled and _interaction_weight > EPSILON:
				spine_weight = clampf(_interaction_weight * clampf(spine_ccdik_look_weight, 0.0, 1.0), 0.0, 1.0)
			else:
				spine_weight = 1.0
		_set_influence(spine_ccdik, spine_weight * spine_channel)

	if manage_head_look_at:
		var head_active: bool = _has_position_offset(mark_look_at_target, mark_look_at_target_base)
		_set_influence(head_look_at, (1.0 if head_active else 0.0) * look_channel)

func _set_all_modifier_influence(value: float) -> void:
	_set_influence(left_arm_ik, value)
	_set_influence(right_arm_ik, value)
	_set_influence(left_leg_ik, value)
	_set_influence(right_leg_ik, value)
	_set_influence(left_hand_copy_rotation, value)
	_set_influence(right_hand_copy_rotation, value)
	_set_influence(spine_ccdik, value)
	_set_influence(head_look_at, value)

func _set_influence(modifier: SkeletonModifier3D, value: float) -> void:
	if modifier == null:
		return
	modifier.influence = value

func debug_left_arm_state() -> Dictionary:
	var target_node := left_hand_target
	var pole_node := left_elbow_pole_target
	var active := _has_position_offset(target_node, left_hand_target_base) or _has_position_offset(pole_node, left_elbow_pole_target_base)
	var arm_reach_channel := _get_channel_weight(IK_CHANNEL_ARM_REACH)
	var weight := arm_reach_channel if active else 0.0
	return {
		"target": str(target_node),
		"pole": str(pole_node),
		"ik": str(left_arm_ik),
		"active": active,
		"channel": arm_reach_channel,
		"weight": weight,
	}

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
