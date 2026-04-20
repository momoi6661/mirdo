extends Node
class_name XiaokongLadderClimbComponent

signal ladder_attached(ladder_path: NodePath, enter_from_top: bool)
signal ladder_move_finished(ladder_path: NodePath, progress: float)
signal ladder_exited(ladder_path: NodePath, exit_at_top: bool)
signal ladder_cancelled(ladder_path: NodePath)

const IK_CHANNEL_LOOK := &"look"
const IK_CHANNEL_SPINE := &"spine"
const IK_CHANNEL_ARM_REACH := &"arm_reach"
const IK_CHANNEL_ARM_IDLE := &"arm_idle"
const IK_CHANNEL_LEG_GROUND := &"leg_ground"
const IK_CHANNEL_HAND_ROT := &"hand_rot"
const EPSILON := 0.00001

@export_group("References")
@export var locomotion_path: NodePath = NodePath("../AutoLocomotion")
@export var navigation_path: NodePath = NodePath("../AutoNavigation")
@export var animation_controller_path: NodePath = NodePath("../..")
@export var ik_target_driver_path: NodePath = NodePath("../../根/IKTargets")

@export_group("Timing")
@export_range(0.0, 1.0, 0.01) var attach_duration_sec: float = 0.18
@export_range(0.0, 1.0, 0.01) var exit_duration_sec: float = 0.20
@export_range(0.05, 1.0, 0.01) var hand_step_duration_sec: float = 0.16
@export_range(0.05, 1.0, 0.01) var foot_step_duration_sec: float = 0.16
@export_range(0.05, 1.0, 0.01) var body_step_duration_sec: float = 0.14

@export_group("Layer Offsets")
@export var hand_start_layer_offset: int = 1
@export var foot_start_layer_offset: int = 0
@export var left_hand_extra_offset: int = 0
@export var right_hand_extra_offset: int = -1
@export var left_foot_extra_offset: int = 0
@export var right_foot_extra_offset: int = -1

@export_group("Pose")
@export var body_local_offset: Vector3 = Vector3.ZERO
@export var body_forward_axis: Vector3 = Vector3(0.0, 0.0, 1.0)

@export_group("IK Channels")
@export_range(0.0, 1.0, 0.01) var look_channel_weight: float = 0.0
@export_range(0.0, 1.0, 0.01) var spine_channel_weight: float = 0.05
@export_range(0.0, 1.0, 0.01) var arm_reach_channel_weight: float = 1.0
@export_range(0.0, 1.0, 0.01) var arm_idle_channel_weight: float = 0.0
@export_range(0.0, 1.0, 0.01) var leg_ground_channel_weight: float = 0.0
@export_range(0.0, 1.0, 0.01) var hand_rot_channel_weight: float = 0.0

@export_group("Targets")
@export var left_hand_target_path: NodePath = NodePath("../../根/IKTargets/LeftHandAuto/LeftHandTarget")
@export var right_hand_target_path: NodePath = NodePath("../../根/IKTargets/RightHandAuto/RightHandTarget")
@export var left_foot_target_path: NodePath = NodePath("../../根/IKTargets/LeftFootAuto/LeftFootTarget")
@export var right_foot_target_path: NodePath = NodePath("../../根/IKTargets/RightFootAuto/RightFootTarget")
@export var left_elbow_target_path: NodePath = NodePath("../../根/IKTargets/LeftElbowPoleAuto/LeftElbowPoleTarget")
@export var right_elbow_target_path: NodePath = NodePath("../../根/IKTargets/RightElbowPoleAuto/RightElbowPoleTarget")
@export var left_knee_target_path: NodePath = NodePath("../../根/IKTargets/LeftKneePoleAuto/LeftKneePoleTarget")
@export var right_knee_target_path: NodePath = NodePath("../../根/IKTargets/RightKneePoleAuto/RightKneePoleTarget")

var _body: CharacterBody3D
var _locomotion: Node
var _navigation: Node
var _animation_controller: Node
var _ik_target_driver: Node
var _left_hand_target: Node3D
var _right_hand_target: Node3D
var _left_foot_target: Node3D
var _right_foot_target: Node3D
var _left_elbow_target: Node3D
var _right_elbow_target: Node3D
var _left_knee_target: Node3D
var _right_knee_target: Node3D
var _pose_controller := XiaokongLadderPoseController.new()

var _phase: StringName = &"idle"
var _active_ladder: XiaokongLadderComponent
var _attached := false
var _enter_from_top := false
var _climb_direction := 1
var _left_hand_layer := 0
var _right_hand_layer := 0
var _left_foot_layer := 0
var _right_foot_layer := 0
var _lead_is_left := true
var _phase_elapsed := 0.0
var _phase_duration := 0.0
var _body_start := Transform3D.IDENTITY
var _body_target := Transform3D.IDENTITY
var _limb_target_start := Transform3D.IDENTITY
var _limb_target_end := Transform3D.IDENTITY
var _active_limb_slot: StringName = &""
var _active_limb_from_layer := 0
var _active_limb_to_layer := 0
var _pending_exit_at_top := false
var _saved_channel_weights: Dictionary = {}
var _last_step_ratio := 1.0

func _ready() -> void:
	_refresh_refs()
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	_refresh_refs()
	if _attached and (_active_ladder == null or not is_instance_valid(_active_ladder)):
		_cancel_ladder(true)
		return
	if _attached and _active_ladder != null:
		_apply_support_pose()
		if _body != null:
			_body.velocity = Vector3.ZERO
		if _phase == &"idle":
			if _body != null:
				_body_target = _compute_body_target()
				if _body_target != Transform3D.IDENTITY:
					_body.global_transform = _body_target
			return
	elif _phase == &"idle":
		return

	match _phase:
		&"attaching", &"body_step", &"exiting":
			_tick_body_phase(delta)
		&"hand_step", &"foot_step":
			_tick_limb_phase(delta)

func is_attached_to_ladder() -> bool:
	return _attached

func get_active_ladder() -> Node:
	return _active_ladder

func attach_to_ladder(ladder: Node, enter_from_top: bool = false) -> bool:
	_refresh_refs()
	if not _is_valid_ladder(ladder) or _body == null:
		return false

	_cancel_ladder(false)
	_active_ladder = ladder as XiaokongLadderComponent
	_enter_from_top = enter_from_top
	_climb_direction = -1 if enter_from_top else 1
	_pending_exit_at_top = not enter_from_top
	_pose_controller.configure(_active_ladder, _enter_from_top, body_forward_axis, body_local_offset)
	_initialize_support_layers(enter_from_top)
	_begin_control()
	_apply_support_pose()
	_begin_attach_phase()
	return true

func start_climb(exit_at_top: bool) -> bool:
	if not _attached or _active_ladder == null or _phase != &"idle":
		return false
	_pending_exit_at_top = exit_at_top
	_climb_direction = 1 if exit_at_top else -1
	_lead_is_left = true
	return _begin_hand_step()

func climb_ladder(exit_at_top: bool = true, travel_mode: String = "climb") -> bool:
	if travel_mode != "climb":
		return false
	return start_climb(exit_at_top)

func exit_ladder(exit_at_top: bool = false) -> bool:
	if not _attached or _active_ladder == null or _phase != &"idle":
		return false
	_pending_exit_at_top = exit_at_top
	_begin_exit_phase(exit_at_top)
	return true

func stop_ladder() -> void:
	_cancel_ladder(true)

func _refresh_refs() -> void:
	_body = _resolve_body()
	_locomotion = get_node_or_null(locomotion_path)
	_navigation = get_node_or_null(navigation_path)
	_animation_controller = get_node_or_null(animation_controller_path)
	_ik_target_driver = get_node_or_null(ik_target_driver_path)
	_left_hand_target = get_node_or_null(left_hand_target_path) as Node3D
	_right_hand_target = get_node_or_null(right_hand_target_path) as Node3D
	_left_foot_target = get_node_or_null(left_foot_target_path) as Node3D
	_right_foot_target = get_node_or_null(right_foot_target_path) as Node3D
	_left_elbow_target = get_node_or_null(left_elbow_target_path) as Node3D
	_right_elbow_target = get_node_or_null(right_elbow_target_path) as Node3D
	_left_knee_target = get_node_or_null(left_knee_target_path) as Node3D
	_right_knee_target = get_node_or_null(right_knee_target_path) as Node3D

func _resolve_body() -> CharacterBody3D:
	var cursor: Node = self
	while cursor != null:
		if cursor is CharacterBody3D:
			return cursor as CharacterBody3D
		cursor = cursor.get_parent()
	return null

func _is_valid_ladder(node: Node) -> bool:
	if node is not XiaokongLadderComponent:
		return false
	var ladder := node as XiaokongLadderComponent
	return ladder.get_layer_count() >= 2 \
		and ladder.get_attach_marker(false) != null \
		and ladder.get_attach_marker(true) != null \
		and ladder.get_exit_marker(false) != null \
		and ladder.get_exit_marker(true) != null

func _initialize_support_layers(enter_from_top: bool) -> void:
	var layer_count := _active_ladder.get_layer_count()
	var base_layer := layer_count - 1 if enter_from_top else 0
	_left_hand_layer = _find_nearest_valid_layer(base_layer + hand_start_layer_offset + left_hand_extra_offset, &"left_hand")
	_right_hand_layer = _find_nearest_valid_layer(base_layer + hand_start_layer_offset + right_hand_extra_offset, &"right_hand")
	_left_foot_layer = _find_nearest_valid_layer(base_layer + foot_start_layer_offset + left_foot_extra_offset, &"left_foot")
	_right_foot_layer = _find_nearest_valid_layer(base_layer + foot_start_layer_offset + right_foot_extra_offset, &"right_foot")

func _find_nearest_valid_layer(preferred_index: int, slot_name: StringName) -> int:
	var layer_count := _active_ladder.get_layer_count()
	if layer_count <= 0:
		return 0
	var clamped := clampi(preferred_index, 0, layer_count - 1)
	if _active_ladder.has_slot(clamped, slot_name, _enter_from_top):
		return clamped
	for offset in range(1, layer_count):
		var lower := clamped - offset
		if lower >= 0 and _active_ladder.has_slot(lower, slot_name, _enter_from_top):
			return lower
		var upper := clamped + offset
		if upper < layer_count and _active_ladder.has_slot(upper, slot_name, _enter_from_top):
			return upper
	return clamped

func _begin_control() -> void:
	if _navigation != null and _navigation.has_method("stop_navigation"):
		_navigation.call("stop_navigation")
	if _animation_controller != null and _animation_controller.has_method("trigger_action"):
		_animation_controller.call("trigger_action", &"Idle")
	if _locomotion != null and _locomotion.has_method("set_external_motion_lock"):
		_locomotion.call("set_external_motion_lock", true)
	if _body != null:
		_body.velocity = Vector3.ZERO

	_saved_channel_weights.clear()
	if _ik_target_driver != null:
		if _ik_target_driver.has_method("clear_marker_interaction"):
			_ik_target_driver.call("clear_marker_interaction", true)
		if _ik_target_driver.has_method("get_channel_weights"):
			_saved_channel_weights = _ik_target_driver.call("get_channel_weights")
		if _ik_target_driver.has_method("reset_all_targets_to_base"):
			_ik_target_driver.call("reset_all_targets_to_base")
		if _ik_target_driver.has_method("set_external_target_locks"):
			_ik_target_driver.call("set_external_target_locks", true, true)
	_apply_ladder_ik_profile()

func _apply_ladder_ik_profile() -> void:
	if _ik_target_driver == null or not _ik_target_driver.has_method("set_channel_weight"):
		return
	_ik_target_driver.call("set_channel_weight", IK_CHANNEL_LOOK, look_channel_weight)
	_ik_target_driver.call("set_channel_weight", IK_CHANNEL_SPINE, spine_channel_weight)
	_ik_target_driver.call("set_channel_weight", IK_CHANNEL_ARM_REACH, arm_reach_channel_weight)
	_ik_target_driver.call("set_channel_weight", IK_CHANNEL_ARM_IDLE, arm_idle_channel_weight)
	_ik_target_driver.call("set_channel_weight", IK_CHANNEL_LEG_GROUND, leg_ground_channel_weight)
	_ik_target_driver.call("set_channel_weight", IK_CHANNEL_HAND_ROT, hand_rot_channel_weight)

func _restore_ik_profile() -> void:
	if _ik_target_driver == null:
		return
	if _ik_target_driver.has_method("set_external_target_locks"):
		_ik_target_driver.call("set_external_target_locks", false, false)
	if _ik_target_driver.has_method("reset_all_targets_to_base"):
		_ik_target_driver.call("reset_all_targets_to_base")
	if not _saved_channel_weights.is_empty() and _ik_target_driver.has_method("set_channel_weights"):
		_ik_target_driver.call("set_channel_weights", _saved_channel_weights)

func _begin_attach_phase() -> void:
	_phase = &"attaching"
	_phase_elapsed = 0.0
	_phase_duration = maxf(attach_duration_sec, 0.0)
	_body_start = _body.global_transform
	_body_target = _pose_controller.get_attach_body_transform()
	if _phase_duration <= EPSILON:
		_body.global_transform = _body_target

func _begin_body_step() -> void:
	_phase = &"body_step"
	_phase_elapsed = 0.0
	_phase_duration = maxf(body_step_duration_sec * _last_step_ratio, 0.0)
	_body_start = _body.global_transform
	_body_target = _compute_body_target()
	if _phase_duration <= EPSILON:
		_body.global_transform = _body_target

func _begin_exit_phase(exit_at_top: bool) -> void:
	_phase = &"exiting"
	_phase_elapsed = 0.0
	_phase_duration = maxf(exit_duration_sec, 0.0)
	_body_start = _body.global_transform
	_body_target = _pose_controller.get_exit_body_transform(exit_at_top)
	if _phase_duration <= EPSILON:
		_body.global_transform = _body_target

func _begin_hand_step() -> bool:
	var slot: StringName = &"left_hand" if _lead_is_left else &"right_hand"
	var current_layer := _get_layer_for_slot(slot)
	var next_layer := current_layer + _climb_direction
	if not _is_valid_target_layer(slot, next_layer):
		_phase = &"idle"
		ladder_move_finished.emit(_active_ladder.get_path(), float(_get_support_progress_hint()))
		return false
	_prepare_limb_phase(&"hand_step", slot, current_layer, next_layer, hand_step_duration_sec)
	return true

func _begin_foot_step() -> bool:
	var slot: StringName = &"left_foot" if _lead_is_left else &"right_foot"
	var current_layer := _get_layer_for_slot(slot)
	var next_layer := current_layer + _climb_direction
	if not _is_valid_target_layer(slot, next_layer):
		_finish_cycle_or_stop()
		return false
	_prepare_limb_phase(&"foot_step", slot, current_layer, next_layer, foot_step_duration_sec)
	return true

func _prepare_limb_phase(phase_name: StringName, slot: StringName, from_layer: int, to_layer: int, base_duration: float) -> void:
	_phase = phase_name
	_phase_elapsed = 0.0
	_phase_duration = maxf(base_duration * _measure_step_ratio(from_layer, to_layer), 0.0)
	_active_limb_slot = slot
	_active_limb_from_layer = from_layer
	_active_limb_to_layer = to_layer
	_apply_support_pose()
	_limb_target_start = _active_ladder.get_slot_transform(from_layer, slot, _enter_from_top)
	_limb_target_end = _active_ladder.get_slot_transform(to_layer, slot, _enter_from_top)
	var target_node := _get_target_node_for_slot(slot)
	if _limb_target_start == Transform3D.IDENTITY and target_node != null:
		_limb_target_start = target_node.global_transform
	if _phase_duration <= EPSILON:
		_commit_active_limb_target()

func _measure_step_ratio(from_layer: int, to_layer: int) -> float:
	if _active_ladder == null:
		_last_step_ratio = 1.0
		return 1.0
	var average_spacing := _active_ladder.get_average_layer_spacing(_enter_from_top)
	if average_spacing <= EPSILON:
		_last_step_ratio = 1.0
		return 1.0
	var step_distance := _active_ladder.get_layer_step_distance(from_layer, to_layer, _enter_from_top)
	if step_distance <= EPSILON:
		_last_step_ratio = 1.0
		return 1.0
	_last_step_ratio = clampf(step_distance / average_spacing, 0.65, 1.6)
	return _last_step_ratio

func _tick_body_phase(delta: float) -> void:
	if _body == null:
		_cancel_ladder(true)
		return
	_apply_support_pose()
	_tick_phase_clock(delta)
	var weight := _get_phase_weight()
	_body.global_transform = _interpolate_transform(_body_start, _body_target, weight)
	_body.velocity = Vector3.ZERO
	if _phase_elapsed + EPSILON < _phase_duration:
		return
	_body.global_transform = _body_target
	_body.velocity = Vector3.ZERO
	match _phase:
		&"attaching":
			_attached = true
			_body_target = _compute_body_target()
			if _body_target != Transform3D.IDENTITY:
				_body.global_transform = _body_target
			_phase = &"idle"
			ladder_attached.emit(_active_ladder.get_path(), _enter_from_top)
		&"body_step":
			_phase = &"idle"
			_begin_foot_step()
		&"exiting":
			_finish_exit(true)

func _tick_limb_phase(delta: float) -> void:
	_apply_support_pose()
	_tick_phase_clock(delta)
	var weight := _get_phase_weight()
	var target := _get_target_node_for_slot(_active_limb_slot)
	if target != null:
		target.global_transform = _interpolate_transform(_limb_target_start, _limb_target_end, weight)
	if _phase_elapsed + EPSILON < _phase_duration:
		return
	_commit_active_limb_target()
	match _phase:
		&"hand_step":
			_phase = &"idle"
			_begin_body_step()
		&"foot_step":
			_phase = &"idle"
			_finish_cycle_or_stop()

func _commit_active_limb_target() -> void:
	_set_layer_for_slot(_active_limb_slot, _active_limb_to_layer)
	_apply_support_pose()

func _finish_cycle_or_stop() -> void:
	_lead_is_left = not _lead_is_left
	if not _can_advance_lead_hand():
		_phase = &"idle"
		ladder_move_finished.emit(_active_ladder.get_path(), float(_get_support_progress_hint()))
		return
	_begin_hand_step()

func _can_advance_lead_hand() -> bool:
	var slot: StringName = &"left_hand" if _lead_is_left else &"right_hand"
	return _is_valid_target_layer(slot, _get_layer_for_slot(slot) + _climb_direction)

func _is_valid_target_layer(slot: StringName, layer_index: int) -> bool:
	if _active_ladder == null or layer_index < 0 or layer_index >= _active_ladder.get_layer_count():
		return false
	return _active_ladder.has_slot(layer_index, slot, _enter_from_top)

func _get_support_progress_hint() -> int:
	var highest := maxi(_left_hand_layer, _right_hand_layer)
	highest = maxi(highest, _left_foot_layer)
	highest = maxi(highest, _right_foot_layer)
	return highest

func _compute_body_target() -> Transform3D:
	return _pose_controller.get_support_body_transform(_left_hand_layer, _right_hand_layer, _left_foot_layer, _right_foot_layer)

func _apply_support_pose() -> void:
	if not _pose_controller.is_ready():
		return
	_pose_controller.apply_support_pose({
		&"left_hand": _left_hand_target,
		&"right_hand": _right_hand_target,
		&"left_foot": _left_foot_target,
		&"right_foot": _right_foot_target,
		&"left_elbow": _left_elbow_target,
		&"right_elbow": _right_elbow_target,
		&"left_knee": _left_knee_target,
		&"right_knee": _right_knee_target,
	}, {
		&"left_hand": _left_hand_layer,
		&"right_hand": _right_hand_layer,
		&"left_foot": _left_foot_layer,
		&"right_foot": _right_foot_layer,
		&"left_elbow": _left_hand_layer,
		&"right_elbow": _right_hand_layer,
		&"left_knee": _left_foot_layer,
		&"right_knee": _right_foot_layer,
	})

func _get_layer_for_slot(slot: StringName) -> int:
	match slot:
		&"left_hand":
			return _left_hand_layer
		&"right_hand":
			return _right_hand_layer
		&"left_foot":
			return _left_foot_layer
		&"right_foot":
			return _right_foot_layer
		_:
			return 0

func _set_layer_for_slot(slot: StringName, layer_index: int) -> void:
	match slot:
		&"left_hand":
			_left_hand_layer = layer_index
		&"right_hand":
			_right_hand_layer = layer_index
		&"left_foot":
			_left_foot_layer = layer_index
		&"right_foot":
			_right_foot_layer = layer_index

func _get_target_node_for_slot(slot: StringName) -> Node3D:
	match slot:
		&"left_hand":
			return _left_hand_target
		&"right_hand":
			return _right_hand_target
		&"left_foot":
			return _left_foot_target
		&"right_foot":
			return _right_foot_target
		_:
			return null

func _tick_phase_clock(delta: float) -> void:
	_phase_elapsed = minf(_phase_elapsed + maxf(delta, 0.0), _phase_duration)

func _get_phase_weight() -> float:
	if _phase_duration <= EPSILON:
		return 1.0
	var weight := clampf(_phase_elapsed / _phase_duration, 0.0, 1.0)
	return weight * weight * (3.0 - 2.0 * weight)

func _interpolate_transform(from_transform: Transform3D, to_transform: Transform3D, weight: float) -> Transform3D:
	var start_basis := from_transform.basis.orthonormalized()
	var target_basis := to_transform.basis.orthonormalized()
	var next_basis := start_basis.slerp(target_basis, weight).orthonormalized()
	var next_origin := from_transform.origin.lerp(to_transform.origin, weight)
	return Transform3D(next_basis, next_origin)

func _finish_exit(emit_signal_enabled: bool) -> void:
	var previous_ladder := _active_ladder
	_restore_ik_profile()
	if _locomotion != null and _locomotion.has_method("set_external_motion_lock"):
		_locomotion.call("set_external_motion_lock", false)
	if _body != null:
		_body.velocity = Vector3.ZERO
	_active_ladder = null
	_pose_controller.clear()
	_attached = false
	_phase = &"idle"
	_phase_elapsed = 0.0
	_phase_duration = 0.0
	_active_limb_slot = &""
	_saved_channel_weights.clear()
	_last_step_ratio = 1.0
	if emit_signal_enabled and previous_ladder != null:
		ladder_exited.emit(previous_ladder.get_path(), _pending_exit_at_top)

func _cancel_ladder(emit_signal_enabled: bool) -> void:
	var previous_ladder := _active_ladder
	_restore_ik_profile()
	if _locomotion != null and _locomotion.has_method("set_external_motion_lock"):
		_locomotion.call("set_external_motion_lock", false)
	if _body != null:
		_body.velocity = Vector3.ZERO
	_active_ladder = null
	_pose_controller.clear()
	_attached = false
	_phase = &"idle"
	_phase_elapsed = 0.0
	_phase_duration = 0.0
	_active_limb_slot = &""
	_saved_channel_weights.clear()
	_last_step_ratio = 1.0
	if emit_signal_enabled and previous_ladder != null:
		ladder_cancelled.emit(previous_ladder.get_path())
