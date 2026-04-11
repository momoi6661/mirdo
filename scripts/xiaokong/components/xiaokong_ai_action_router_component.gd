extends Node
class_name XiaokongAIActionRouterComponent

signal ai_response_applied(summary: Dictionary)

const KNOWN_ACTIONS: PackedStringArray = [
	"Idle",
	"StandingGreeting",
	"Drinking",
	"Salute",
	"Kiss",
	"SittingIdle",
	"Laying",
	"LeftTurn",
	"RightTurn",
]

const ALLOWED_DIRECT_ACTIONS: PackedStringArray = [
	"Idle",
	"SittingIdle",
]

const DEFER_ACTIONS_UNTIL_ARRIVAL: PackedStringArray = [
	"SittingIdle",
]

const COMMAND_FOLLOW_PLAYER := "follow_player"
const COMMAND_STOP_FOLLOW := "stop_follow"
const COMMAND_LOOK_AT_PLAYER := "look_at_player"
const COMMAND_SIT_DOWN := "sit_down"
const COMMAND_GO_TO_MARKER := "go_to_marker"

const LOCATION_KEYWORD_MARKERS: Dictionary = {}

const COMMAND_ALIASES: Dictionary = {
	"follow": COMMAND_FOLLOW_PLAYER,
	"follow_me": COMMAND_FOLLOW_PLAYER,
	"follow_player": COMMAND_FOLLOW_PLAYER,
	"follow_user": COMMAND_FOLLOW_PLAYER,
	"跟着我": COMMAND_FOLLOW_PLAYER,
	"跟我走": COMMAND_FOLLOW_PLAYER,
	"跟随": COMMAND_FOLLOW_PLAYER,
	"跟随我": COMMAND_FOLLOW_PLAYER,
	"stop_follow": COMMAND_STOP_FOLLOW,
	"stop_following": COMMAND_STOP_FOLLOW,
	"stop": COMMAND_STOP_FOLLOW,
	"停止跟随": COMMAND_STOP_FOLLOW,
	"停止跟着我": COMMAND_STOP_FOLLOW,
	"别跟了": COMMAND_STOP_FOLLOW,
	"look_at_player": COMMAND_LOOK_AT_PLAYER,
	"look_player": COMMAND_LOOK_AT_PLAYER,
	"look_at_me": COMMAND_LOOK_AT_PLAYER,
	"看着我": COMMAND_LOOK_AT_PLAYER,
	"看我": COMMAND_LOOK_AT_PLAYER,
	"面向我": COMMAND_LOOK_AT_PLAYER,
	"sit": COMMAND_SIT_DOWN,
	"sit_down": COMMAND_SIT_DOWN,
	"坐下": COMMAND_SIT_DOWN,
	"坐着": COMMAND_SIT_DOWN,
	"坐一会": COMMAND_SIT_DOWN,
	"去坐下": COMMAND_SIT_DOWN,
	"go_to_marker": COMMAND_GO_TO_MARKER,
	"goto_marker": COMMAND_GO_TO_MARKER,
	"go_marker": COMMAND_GO_TO_MARKER,
	"go_to": COMMAND_GO_TO_MARKER,
	"去这里": COMMAND_GO_TO_MARKER,
	"去那边": COMMAND_GO_TO_MARKER,
}

@export var action_controller_path: NodePath = NodePath("..")
@export var state_component_path: NodePath
@export var follow_target_path: NodePath
@export var markers_root_path: NodePath
@export var ik_target_driver_path: NodePath = NodePath("../../根/IKTargets")
@export var sit_anchor_path: NodePath = NodePath("根/GeneralSkeleton/SitAnchorAttachment/SitAnchor_Mark3D")
@export var fallback_action: StringName = &"Idle"
@export var snap_to_marker_position_on_arrival: bool = true
@export var snap_position_for_sit_action: bool = false
@export var snap_to_marker_rotation_on_arrival: bool = true
@export var marker_position_snap_offset: Vector3 = Vector3.ZERO
@export_range(-180.0, 180.0, 1.0) var marker_rotation_yaw_offset_deg: float = 0.0
@export var go_to_marker_respect_marker_action: bool = true
@export var reinforce_snap_for_arrival_actions: bool = true
@export var reinforce_snap_actions: PackedStringArray = PackedStringArray()
@export_range(0.0, 0.5, 0.01) var reinforce_snap_delay_sec: float = 0.12
@export var temporarily_disable_collision_on_snap: bool = true
@export var temporarily_disable_collision_on_snap_for_sit_action: bool = false
@export_range(0.0, 0.8, 0.01) var collision_restore_delay_sec: float = 0.2
@export var sit_use_approach_marker_pipeline: bool = true
@export var sit_auto_generate_approach_when_missing: bool = true
@export_range(0.2, 2.0, 0.01) var sit_auto_approach_distance: float = 0.42
@export var sit_virtual_approach_use_positive_marker_z: bool = true
@export var sit_virtual_approach_auto_choose_side: bool = true
@export_range(0.05, 1.2, 0.01) var sit_attach_duration_sec: float = 0.38
@export_range(0.0, 1.2, 0.01) var sit_collision_restore_extra_sec: float = 0.16
@export var sit_force_align_to_seat_marker_before_attach: bool = true
@export var sit_use_turn_alignment_before_action: bool = true
@export_range(0.0, 180.0, 1.0) var sit_turn_alignment_threshold_deg: float = 10.0
@export_range(0.05, 2.0, 0.01) var sit_turn_alignment_timeout_sec: float = 1.1
@export_range(0.0, 0.8, 0.01) var sit_attach_start_delay_sec: float = 0.32
@export_range(0.15, 2.0, 0.01) var sit_attach_max_distance: float = 0.5
@export var sit_attach_preserve_current_height: bool = true
@export var sit_navigation_precision_enabled: bool = true
@export_range(0.03, 0.8, 0.01) var sit_navigation_path_desired_distance: float = 0.08
@export_range(0.03, 1.2, 0.01) var sit_navigation_target_desired_distance: float = 0.12
@export var sit_toggle_stand_when_in_sit_state: bool = true

@export var sleep_marker_priority: PackedStringArray = PackedStringArray(["Bed_Lie_Mark3D", "Bed2_Lie_Mark3D"])
@export var sleep_marker_keywords: PackedStringArray = PackedStringArray(["bed", "lay", "lie", "sleep"])
@export var table_sit_marker_keywords: PackedStringArray = PackedStringArray(["bench", "table", "chair", "stool"])
@export_range(0.2, 3.0, 0.05) var stand_toggle_distance_default: float = 0.9

@export var action_aliases: Dictionary = {
	"idle": "Idle",
	"sit": "SittingIdle",
	"sit_idle": "SittingIdle",
	"坐下": "SittingIdle",
	"坐着": "SittingIdle",
}

var _action_controller: Node
var _state_component: XiaokongStateComponent
var _navigation_component: XiaokongNavigationComponent
var _navigation_agent: NavigationAgent3D
var _ik_target_driver: Node
var _sit_anchor: Node3D

var _pending_action_on_arrival: StringName = &""
var _pending_marker_name: String = ""
var _pending_sit_approach_marker_name: String = ""
var _pending_sit_seat_marker_name: String = ""
var _pending_sit_action_on_arrival: StringName = &"SittingIdle"
var _pending_sit_virtual_approach: bool = false
var _snap_request_serial: int = 0
var _active_sit_marker_path: String = ""
var _collision_restore_serial: int = 0
var _collision_override_active: bool = false
var _collision_saved_layer: int = 0
var _collision_saved_mask: int = 0
var _sit_nav_precision_override_active: bool = false
var _saved_nav_path_desired_distance: float = 0.0
var _saved_nav_target_desired_distance: float = 0.0

func _ready() -> void:
	_refresh_refs()

func apply_ai_response(final_data: Dictionary) -> Dictionary:
	_refresh_refs()

	var summary: Dictionary = {
		"moved": false,
		"move_target": Vector3.ZERO,
		"navigation_mode": "",
		"target_marker": "",
		"command_requested": "",
		"command_applied": false,
		"action_requested": "",
		"action_applied": false,
		"action_queued": false,
		"queued_action": "",
		"stat_change_applied": {},
		"errors": [],
	}

	if final_data.is_empty():
		summary["errors"].append("empty_payload")
		ai_response_applied.emit(summary)
		return summary

	var command_handled: bool = _apply_navigation_command(final_data, summary)

	if not command_handled:
		# Intentionally ignore free-form move targets for now to avoid
		# fixed-location conflicts with scene interactions.
		pass

	var skip_direct_action: bool = String(summary.get("command_requested", "")).strip_edges() != "" and not bool(summary.get("command_applied", false))
	var action_value: Variant = ""
	if not skip_direct_action:
		action_value = _extract_action_value(final_data)
	if not _normalize_command_name(action_value).is_empty():
		# Some backends use "action" to deliver navigation intents.
		# Command handling above has already consumed that case.
		action_value = ""

	var normalized_action: StringName = _normalize_action(action_value)
	if normalized_action != &"":
		summary["action_requested"] = String(normalized_action)
		if bool(summary.get("action_queued", false)):
			# Keep command-queued action untouched.
			pass
		elif bool(summary.get("moved", false)) and _should_defer_action_until_arrival(normalized_action):
			_set_pending_arrival_action(normalized_action, String(summary.get("target_marker", "")))
			summary["action_queued"] = true
			summary["queued_action"] = String(normalized_action)
		else:
			if _action_controller != null and _action_controller.has_method("trigger_action"):
				_invalidate_pending_snap()
				_clear_pending_arrival_state()
				_clear_marker_interaction_ik()
				summary["action_applied"] = bool(_action_controller.call("trigger_action", normalized_action))
			else:
				summary["errors"].append("action_controller_has_no_trigger_action")

	if _state_component != null and final_data.has("stat_change") and final_data["stat_change"] is Dictionary:
		var normalized_delta: Dictionary = _normalize_stat_change(final_data["stat_change"])
		summary["stat_change_applied"] = _state_component.apply_delta(normalized_delta, "ai_response")

	ai_response_applied.emit(summary)
	return summary

func _refresh_refs() -> void:
	_action_controller = get_node_or_null(action_controller_path)
	var previous_navigation: XiaokongNavigationComponent = _navigation_component
	_navigation_component = _resolve_navigation_component()
	_navigation_agent = _resolve_navigation_agent()
	_ik_target_driver = _resolve_ik_target_driver()
	_sit_anchor = _resolve_sit_anchor()
	_rebind_navigation_signal(previous_navigation, _navigation_component)

	_state_component = get_node_or_null(state_component_path) as XiaokongStateComponent
	if _state_component == null:
		_state_component = _find_state_component()

func _resolve_navigation_component() -> XiaokongNavigationComponent:
	if _action_controller == null:
		return null
	var by_components := _action_controller.get_node_or_null("Components/AutoNavigation") as XiaokongNavigationComponent
	if by_components != null:
		return by_components
	return _action_controller.get_node_or_null("AutoNavigation") as XiaokongNavigationComponent

func _resolve_navigation_agent() -> NavigationAgent3D:
	if _action_controller == null:
		return null
	return _action_controller.get_node_or_null("AutoNavAgent") as NavigationAgent3D

func _resolve_ik_target_driver() -> Node:
	if _action_controller == null:
		return null
	if ik_target_driver_path != NodePath():
		var by_export := _action_controller.get_node_or_null(ik_target_driver_path)
		if by_export != null and by_export.has_method("apply_marker_interaction"):
			return by_export
	return _find_node_with_method_recursive(_action_controller, &"apply_marker_interaction")

func _resolve_sit_anchor() -> Node3D:
	if _action_controller == null:
		return null
	if sit_anchor_path != NodePath():
		var by_export: Node = _action_controller.get_node_or_null(sit_anchor_path)
		if by_export is Node3D:
			return by_export as Node3D
	var by_default: Node3D = _action_controller.get_node_or_null("根/SitAnchor_Mark3D") as Node3D
	if by_default != null:
		return by_default
	return _find_node3d_by_name_recursive(_action_controller, "sitanchor_mark3d")

func _rebind_navigation_signal(previous_navigation: XiaokongNavigationComponent, next_navigation: XiaokongNavigationComponent) -> void:
	var callback := Callable(self, "_on_navigation_destination_reached")
	if previous_navigation != null and previous_navigation != next_navigation and previous_navigation.destination_reached.is_connected(callback):
		previous_navigation.destination_reached.disconnect(callback)
	if next_navigation != null and not next_navigation.destination_reached.is_connected(callback):
		next_navigation.destination_reached.connect(callback)

func _on_navigation_destination_reached() -> void:
	if _try_handle_pending_sit_arrival():
		return
	if _pending_action_on_arrival == &"" and _pending_marker_name.strip_edges().is_empty():
		return
	var arrival_action: StringName = _pending_action_on_arrival
	var marker: Marker3D = _resolve_pending_arrival_marker()
	_snap_action_controller_to_marker(marker, arrival_action)
	if _should_reinforce_snap(arrival_action):
		_reinforce_arrival_snap(marker, arrival_action)
	_apply_marker_interaction_ik(marker)
	if arrival_action != &"" and _action_controller != null and _action_controller.has_method("trigger_action"):
		_action_controller.call("trigger_action", arrival_action)
	if arrival_action == &"Idle":
		_active_sit_marker_path = ""
	_clear_pending_arrival_state()

func _try_handle_pending_sit_arrival() -> bool:
	if _pending_sit_seat_marker_name.strip_edges().is_empty():
		return false

	if not _pending_sit_virtual_approach:
		var approach_marker: Marker3D = _resolve_pending_sit_approach_marker()
		if approach_marker == null:
			_clear_pending_sit_state()
			return false
		var arrived_marker: Marker3D = _resolve_pending_arrival_marker()
		if arrived_marker == null:
			arrived_marker = approach_marker
		if arrived_marker == null:
			return false
		var arrived_path: String = String(arrived_marker.get_path())
		var expected_path: String = String(approach_marker.get_path())
		if arrived_path != expected_path:
			return false

	var seat_marker: Marker3D = _resolve_pending_sit_seat_marker()
	_clear_pending_arrival_state()
	if seat_marker == null:
		_clear_pending_sit_state()
		return false

	if _action_controller != null and _action_controller.has_method("stop_navigation"):
		_action_controller.call("stop_navigation")

	var sit_action: StringName = _pending_sit_action_on_arrival
	var seat_marker_path: String = String(seat_marker.get_path())
	_clear_pending_sit_state()
	_start_sit_arrival_sequence(seat_marker_path, sit_action)
	return true

func _resolve_pending_sit_approach_marker() -> Marker3D:
	if _pending_sit_approach_marker_name.strip_edges().is_empty():
		return null
	var marker: Marker3D = _find_marker_by_path(_pending_sit_approach_marker_name)
	if marker != null:
		return marker
	marker = _find_marker_by_name(_pending_sit_approach_marker_name)
	if marker != null:
		return marker
	return null

func _resolve_pending_sit_seat_marker() -> Marker3D:
	if _pending_sit_seat_marker_name.strip_edges().is_empty():
		return null
	var marker: Marker3D = _find_marker_by_path(_pending_sit_seat_marker_name, &"SittingIdle")
	if marker != null:
		return marker
	marker = _find_marker_by_name(_pending_sit_seat_marker_name, &"SittingIdle")
	if marker != null:
		return marker
	return _find_marker_by_name(_pending_sit_seat_marker_name)

func _set_pending_arrival_action(action_name: StringName, marker_name: String = "") -> void:
	_pending_action_on_arrival = action_name
	if not marker_name.strip_edges().is_empty():
		_pending_marker_name = marker_name.strip_edges()

func _set_pending_arrival_marker(marker_name: String) -> void:
	_pending_marker_name = marker_name.strip_edges()

func _clear_pending_arrival_state() -> void:
	_pending_action_on_arrival = &""
	_pending_marker_name = ""

func _clear_pending_sit_state() -> void:
	_pending_sit_approach_marker_name = ""
	_pending_sit_seat_marker_name = ""
	_pending_sit_action_on_arrival = &"SittingIdle"
	_pending_sit_virtual_approach = false
	_restore_sit_navigation_precision()

func _start_sit_arrival_sequence(seat_marker_path: String, sit_action: StringName) -> void:
	if seat_marker_path.strip_edges().is_empty():
		return
	call_deferred("_run_sit_arrival_sequence", seat_marker_path, sit_action)

func _run_sit_arrival_sequence(seat_marker_path: String, sit_action: StringName) -> void:
	var seat_marker: Marker3D = _find_marker_by_path(seat_marker_path, &"SittingIdle")
	if seat_marker == null:
		var seat_marker_name: String = seat_marker_path.get_file()
		seat_marker = _find_marker_by_name(seat_marker_name, &"SittingIdle")
	if seat_marker == null:
		return

	var serial: int = _begin_pending_snap()
	await _align_body_for_sit_before_action(seat_marker, serial)
	if not is_inside_tree() or not _is_snap_serial_valid(serial):
		return

	_active_sit_marker_path = String(seat_marker.get_path())
	if sit_action != &"" and _action_controller != null and _action_controller.has_method("trigger_action"):
		_action_controller.call("trigger_action", sit_action)
	_apply_marker_interaction_ik(seat_marker)

	var tree: SceneTree = get_tree()
	if tree != null and sit_attach_start_delay_sec > 0.0:
		await tree.create_timer(sit_attach_start_delay_sec).timeout
		if not is_inside_tree() or not _is_snap_serial_valid(serial):
			return

	if _is_body_close_enough_for_sit_attach(seat_marker):
		_smooth_attach_action_controller_to_marker(seat_marker, sit_action, sit_attach_duration_sec)

func _align_body_for_sit_before_action(seat_marker: Marker3D, serial: int) -> void:
	if seat_marker == null:
		return
	if not (_action_controller is Node3D):
		return

	if not sit_use_turn_alignment_before_action:
		if sit_force_align_to_seat_marker_before_attach:
			var direct_body := _action_controller as Node3D
			direct_body.global_transform = _compute_body_transform_for_marker(seat_marker, false, true)
		return

	if _action_controller == null or not _action_controller.has_method("trigger_action"):
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	var timeout_sec: float = maxf(0.05, sit_turn_alignment_timeout_sec)
	var elapsed_sec: float = 0.0
	var threshold_rad: float = deg_to_rad(clampf(sit_turn_alignment_threshold_deg, 0.0, 180.0))
	while elapsed_sec < timeout_sec:
		if not is_inside_tree() or not _is_snap_serial_valid(serial):
			return
		var signed_angle: float = _compute_signed_angle_to_marker_forward(seat_marker)
		if absf(signed_angle) <= threshold_rad:
			return

		var use_negative_forward: bool = _navigation_component != null and _navigation_component.use_negative_z_forward
		var is_right_turn: bool = signed_angle > 0.0
		if use_negative_forward:
			is_right_turn = signed_angle < 0.0
		var turn_action: StringName = &"RightTurn" if is_right_turn else &"LeftTurn"
		var accepted: bool = bool(_action_controller.call("trigger_action", turn_action))
		if not accepted:
			break

		var wait_sec: float = 0.18
		if _action_controller.has_method("get_turn_animation_duration"):
			var measured: float = float(_action_controller.call("get_turn_animation_duration", turn_action))
			wait_sec = clampf(measured * 0.75, 0.08, 0.6)
		await tree.create_timer(wait_sec).timeout
		elapsed_sec += wait_sec

	if sit_force_align_to_seat_marker_before_attach and (_action_controller is Node3D):
		var body := _action_controller as Node3D
		body.global_transform = _compute_body_transform_for_marker(seat_marker, false, true)

func _compute_signed_angle_to_marker_forward(marker: Marker3D) -> float:
	if marker == null:
		return 0.0
	if not (_action_controller is Node3D):
		return 0.0
	var body := _action_controller as Node3D
	var body_forward: Vector3 = body.global_transform.basis.z
	var use_negative_forward: bool = _navigation_component != null and _navigation_component.use_negative_z_forward
	if use_negative_forward:
		body_forward = -body_forward
	body_forward.y = 0.0
	if body_forward.length_squared() <= 0.0001:
		return 0.0
	body_forward = body_forward.normalized()

	var marker_forward: Vector3 = _extract_marker_flat_forward(marker)
	if marker_forward.length_squared() <= 0.0001:
		return 0.0
	var cross_y: float = body_forward.cross(marker_forward).y
	var dot: float = clampf(body_forward.dot(marker_forward), -1.0, 1.0)
	return atan2(cross_y, dot)

func _is_body_close_enough_for_sit_attach(seat_marker: Marker3D) -> bool:
	if seat_marker == null:
		return false
	if not (_action_controller is Node3D):
		return false
	var body := _action_controller as Node3D
	var body_pos: Vector3 = body.global_position
	var seat_pos: Vector3 = seat_marker.global_position
	var dx: float = body_pos.x - seat_pos.x
	var dz: float = body_pos.z - seat_pos.z
	var planar_distance: float = sqrt(dx * dx + dz * dz)
	return planar_distance <= maxf(0.15, sit_attach_max_distance)

func _invalidate_pending_snap() -> void:
	_snap_request_serial += 1
	_clear_pending_sit_state()
	_restore_sit_navigation_precision()

func _begin_pending_snap() -> int:
	_snap_request_serial += 1
	return _snap_request_serial

func _is_snap_serial_valid(serial: int) -> bool:
	return serial == _snap_request_serial

func _apply_sit_navigation_precision() -> void:
	if not sit_navigation_precision_enabled:
		return
	if _navigation_agent == null:
		return
	if not is_instance_valid(_navigation_agent):
		return
	if not _sit_nav_precision_override_active:
		_saved_nav_path_desired_distance = _navigation_agent.path_desired_distance
		_saved_nav_target_desired_distance = _navigation_agent.target_desired_distance
		_sit_nav_precision_override_active = true
	_navigation_agent.path_desired_distance = minf(_navigation_agent.path_desired_distance, maxf(0.03, sit_navigation_path_desired_distance))
	_navigation_agent.target_desired_distance = minf(_navigation_agent.target_desired_distance, maxf(0.03, sit_navigation_target_desired_distance))

func _restore_sit_navigation_precision() -> void:
	if not _sit_nav_precision_override_active:
		return
	if _navigation_agent != null and is_instance_valid(_navigation_agent):
		_navigation_agent.path_desired_distance = _saved_nav_path_desired_distance
		_navigation_agent.target_desired_distance = _saved_nav_target_desired_distance
	_sit_nav_precision_override_active = false

func _resolve_pending_arrival_marker() -> Marker3D:
	if _pending_marker_name.strip_edges().is_empty():
		return null
	var by_path: Marker3D = _find_marker_by_path(_pending_marker_name, _pending_action_on_arrival)
	if by_path != null:
		return by_path
	var marker: Marker3D = _find_marker_by_name(_pending_marker_name, _pending_action_on_arrival)
	if marker != null:
		return marker
	return _find_marker_by_name(_pending_marker_name)

func _snap_action_controller_to_marker(marker: Marker3D, action_name: StringName = &"") -> void:
	if marker == null:
		return
	if not (_action_controller is Node3D):
		return
	var should_snap_position: bool = snap_to_marker_position_on_arrival
	if action_name == &"SittingIdle":
		should_snap_position = snap_position_for_sit_action
	if not should_snap_position and not snap_to_marker_rotation_on_arrival:
		return

	var body := _action_controller as Node3D
	var next_transform: Transform3D = _compute_body_transform_for_marker(marker, should_snap_position, snap_to_marker_rotation_on_arrival)
	body.global_transform = next_transform

func _compute_body_transform_for_marker(marker: Marker3D, should_snap_position: bool, should_snap_rotation: bool) -> Transform3D:
	if not (_action_controller is Node3D):
		return Transform3D.IDENTITY
	var body := _action_controller as Node3D
	var next_transform: Transform3D = body.global_transform
	if marker == null:
		return next_transform
	if not should_snap_position and not should_snap_rotation:
		return next_transform

	var body_scale: Vector3 = next_transform.basis.get_scale()
	var marker_forward: Vector3 = _extract_marker_flat_forward(marker)
	var target_yaw: float = atan2(marker_forward.x, marker_forward.z) + deg_to_rad(marker_rotation_yaw_offset_deg)
	var desired_marker_basis: Basis = Basis(Vector3.UP, target_yaw)
	var desired_anchor_position: Vector3 = marker.global_position + marker_position_snap_offset
	var use_anchor: bool = _sit_anchor != null and is_instance_valid(_sit_anchor)

	if use_anchor and (should_snap_position or should_snap_rotation):
		var anchor_local: Transform3D = body.global_transform.affine_inverse() * _sit_anchor.global_transform
		if should_snap_rotation:
			var desired_body_basis: Basis = desired_marker_basis * anchor_local.basis.orthonormalized().inverse()
			next_transform.basis = desired_body_basis.orthonormalized().scaled(body_scale)
		if should_snap_position:
			var anchor_local_position: Vector3 = anchor_local.origin
			next_transform.origin = desired_anchor_position - (next_transform.basis * anchor_local_position)
	else:
		if should_snap_rotation:
			next_transform.basis = desired_marker_basis.scaled(body_scale)
		if should_snap_position:
			next_transform.origin = desired_anchor_position
	return next_transform

func _smooth_attach_action_controller_to_marker(marker: Marker3D, action_name: StringName, duration_sec: float) -> void:
	if marker == null:
		return
	if not (_action_controller is Node3D):
		return
	var body := _action_controller as Node3D
	var start_transform: Transform3D = body.global_transform
	var target_transform: Transform3D = _compute_body_transform_for_marker(marker, true, true)
	if action_name == &"SittingIdle":
		if sit_attach_preserve_current_height:
			target_transform.origin.y = start_transform.origin.y
		var planar_delta := target_transform.origin - start_transform.origin
		planar_delta.y = 0.0
		if planar_delta.length() > maxf(0.15, sit_attach_max_distance):
			return
	var safe_duration: float = maxf(0.05, duration_sec)
	var serial: int = _begin_pending_snap()

	if _action_controller is CharacterBody3D:
		var char_body := _action_controller as CharacterBody3D
		char_body.velocity = Vector3.ZERO

	if _should_temporarily_disable_collision_on_snap(action_name):
		var restore_delay: float = safe_duration + maxf(0.01, sit_collision_restore_extra_sec)
		_temporarily_disable_controller_collision(restore_delay)

	var tree: SceneTree = get_tree()
	if tree == null:
		body.global_transform = target_transform
		return

	var step_count: int = maxi(2, int(round(safe_duration * 60.0)))
	var start_basis: Basis = start_transform.basis.orthonormalized()
	var target_basis: Basis = target_transform.basis.orthonormalized()
	var body_scale: Vector3 = start_transform.basis.get_scale()

	for step in range(step_count):
		await tree.physics_frame
		if not is_inside_tree():
			return
		if not _is_snap_serial_valid(serial):
			return

		var t: float = float(step + 1) / float(step_count)
		t = t * t * (3.0 - 2.0 * t)
		var next_origin: Vector3 = start_transform.origin.lerp(target_transform.origin, t)
		var next_basis: Basis = start_basis.slerp(target_basis, t).scaled(body_scale)
		body.global_transform = Transform3D(next_basis, next_origin)
		if _action_controller is CharacterBody3D:
			var loop_body := _action_controller as CharacterBody3D
			loop_body.velocity = Vector3.ZERO

	if _is_snap_serial_valid(serial):
		body.global_transform = target_transform
		if _action_controller is CharacterBody3D:
			var final_body := _action_controller as CharacterBody3D
			final_body.velocity = Vector3.ZERO

func _should_reinforce_snap(action_name: StringName) -> bool:
	if not reinforce_snap_for_arrival_actions:
		return false
	if action_name == &"":
		return false
	if action_name == &"SittingIdle":
		return false
	return reinforce_snap_actions.has(String(action_name))

func _reinforce_arrival_snap(marker: Marker3D, action_name: StringName) -> void:
	if marker == null:
		return
	var serial: int = _begin_pending_snap()
	_snap_action_controller_to_marker(marker, action_name)
	if _action_controller is CharacterBody3D:
		var body := _action_controller as CharacterBody3D
		body.velocity = Vector3.ZERO
	call_deferred("_snap_action_controller_deferred_if_valid", marker, action_name, serial)
	if reinforce_snap_delay_sec > 0.0:
		_snap_action_controller_later(marker, action_name, reinforce_snap_delay_sec, serial)
	if _should_temporarily_disable_collision_on_snap(action_name):
		_temporarily_disable_controller_collision()

func _snap_action_controller_deferred_if_valid(marker: Marker3D, action_name: StringName, serial: int) -> void:
	if marker == null:
		return
	if not _is_snap_serial_valid(serial):
		return
	_snap_action_controller_to_marker(marker, action_name)
	if _action_controller is CharacterBody3D:
		var body := _action_controller as CharacterBody3D
		body.velocity = Vector3.ZERO

func _snap_action_controller_later(marker: Marker3D, action_name: StringName, delay_sec: float, serial: int) -> void:
	if marker == null:
		return
	if not _is_snap_serial_valid(serial):
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	await tree.create_timer(delay_sec).timeout
	if not is_inside_tree():
		return
	if not _is_snap_serial_valid(serial):
		return
	_snap_action_controller_to_marker(marker, action_name)
	if _action_controller is CharacterBody3D:
		var body := _action_controller as CharacterBody3D
		body.velocity = Vector3.ZERO

func _should_temporarily_disable_collision_on_snap(action_name: StringName) -> bool:
	if action_name == &"SittingIdle":
		return false
	return temporarily_disable_collision_on_snap

func _temporarily_disable_controller_collision(restore_delay_override: float = -1.0) -> void:
	if not (_action_controller is CollisionObject3D):
		return
	var body := _action_controller as CollisionObject3D
	_collision_restore_serial += 1
	var serial: int = _collision_restore_serial
	if not _collision_override_active:
		_collision_saved_layer = body.collision_layer
		_collision_saved_mask = body.collision_mask
		_collision_override_active = true
	body.collision_layer = 0
	body.collision_mask = 0

	var tree: SceneTree = get_tree()
	if tree == null:
		_restore_controller_collision_if_latest(serial)
		return
	var restore_delay: float = collision_restore_delay_sec
	if restore_delay_override >= 0.0:
		restore_delay = restore_delay_override
	await tree.create_timer(maxf(0.01, restore_delay)).timeout
	if not is_inside_tree():
		return
	_restore_controller_collision_if_latest(serial)

func _restore_controller_collision_if_latest(serial: int) -> void:
	if serial != _collision_restore_serial:
		return
	if not (_action_controller is CollisionObject3D):
		_collision_override_active = false
		return
	var body := _action_controller as CollisionObject3D
	if not is_instance_valid(body):
		return
	body.collision_layer = _collision_saved_layer
	body.collision_mask = _collision_saved_mask
	_collision_override_active = false

func _extract_move_target_value(payload: Dictionary) -> Variant:
	if payload.has("move_target"):
		return payload["move_target"]
	if payload.has("target_position"):
		return payload["target_position"]
	if payload.has("nav_target"):
		return payload["nav_target"]
	for nested_key in ["action_hint", "navigation", "intent_payload", "command_payload"]:
		if not payload.has(nested_key):
			continue
		var nested_value: Variant = payload[nested_key]
		if nested_value is not Dictionary:
			continue
		var nested_dict: Dictionary = nested_value as Dictionary
		if nested_dict.has("move_target"):
			return nested_dict["move_target"]
		if nested_dict.has("target_position"):
			return nested_dict["target_position"]
		if nested_dict.has("nav_target"):
			return nested_dict["nav_target"]
	return null

func _extract_action_value(payload: Dictionary) -> Variant:
	if payload.has("action"):
		return payload["action"]
	for nested_key in ["action_hint", "navigation", "intent_payload", "command_payload"]:
		if not payload.has(nested_key):
			continue
		var nested_value: Variant = payload[nested_key]
		if nested_value is not Dictionary:
			continue
		var nested_dict: Dictionary = nested_value as Dictionary
		if nested_dict.has("action"):
			return nested_dict["action"]
	return ""

func _parse_move_target(value: Variant) -> Variant:
	if value == null:
		return null

	if value is Vector3:
		return value

	if value is Dictionary:
		var dict_value = value as Dictionary
		if dict_value.has("x") and dict_value.has("y") and dict_value.has("z"):
			return Vector3(float(dict_value["x"]), float(dict_value["y"]), float(dict_value["z"]))

	if value is Array:
		var arr = value as Array
		if arr.size() >= 3:
			return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))

	if value is String:
		var text = String(value).strip_edges()
		if text.is_empty():
			return null
		var parts = text.split(",", false)
		if parts.size() == 3:
			return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))

	return null

func _project_to_navigation_target(world_position: Vector3) -> Vector3:
	var body_node: Node3D = _action_controller as Node3D
	var body_world_ready: bool = body_node != null and body_node.is_inside_tree() and body_node.get_world_3d() != null
	if _navigation_agent != null and _navigation_agent.is_inside_tree() and body_world_ready:
		var nav_map: RID = _navigation_agent.get_navigation_map()
		if nav_map.is_valid():
			var projected: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, world_position)
			var body_pos: Vector3 = _get_action_controller_world_position()
			if body_pos != Vector3.INF:
				var floor_probe := Vector3(world_position.x, body_pos.y, world_position.z)
				var projected_floor: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, floor_probe)
				var direct_delta: float = absf(projected.y - body_pos.y)
				var floor_delta: float = absf(projected_floor.y - body_pos.y)
				if floor_delta + 0.05 < direct_delta:
					return projected_floor
			return projected

	if body_node != null:
		var body_pos: Vector3 = body_node.global_position
		return Vector3(world_position.x, body_pos.y, world_position.z)
	return world_position

func _get_action_controller_world_position() -> Vector3:
	if _action_controller is Node3D:
		return (_action_controller as Node3D).global_position
	return Vector3.INF

func _apply_navigation_command(payload: Dictionary, summary: Dictionary) -> bool:
	var command_value: Variant = _extract_command_value(payload)
	if command_value == null:
		return false
	var command_name: String = _normalize_command_name(command_value)
	if command_name.is_empty():
		summary["command_requested"] = String(command_value)
		summary["errors"].append("unsupported_command:" + String(command_value))
		return true

	summary["command_requested"] = command_name

	match command_name:
		COMMAND_FOLLOW_PLAYER:
			var target_node: Node3D = _resolve_follow_target(payload)
			if target_node == null:
				summary["errors"].append("follow_target_not_found")
				return true
			if _action_controller == null or not _action_controller.has_method("follow_target"):
				summary["errors"].append("action_controller_has_no_follow_target")
				return true
			_invalidate_pending_snap()
			_action_controller.call("follow_target", target_node)
			_clear_pending_arrival_state()
			_apply_follow_look_ik(target_node)
			if _action_controller.has_method("trigger_action"):
				_action_controller.call("trigger_action", &"Idle")
			summary["command_applied"] = true
			summary["moved"] = true
			summary["move_target"] = target_node.global_position
			summary["navigation_mode"] = COMMAND_FOLLOW_PLAYER
			return true

		COMMAND_STOP_FOLLOW:
			if _action_controller == null:
				summary["errors"].append("action_controller_missing")
				return true
			_invalidate_pending_snap()
			if _action_controller.has_method("stop_navigation"):
				_action_controller.call("stop_navigation")
			else:
				summary["errors"].append("action_controller_has_no_stop_navigation")
			_clear_pending_arrival_state()
			_clear_marker_interaction_ik()
			summary["command_applied"] = true
			summary["navigation_mode"] = COMMAND_STOP_FOLLOW
			return true

		COMMAND_LOOK_AT_PLAYER:
			var look_target: Node3D = _resolve_follow_target(payload)
			if look_target == null:
				summary["errors"].append("look_target_not_found")
				return true
			_invalidate_pending_snap()
			if _action_controller != null and _action_controller.has_method("stop_navigation"):
				_action_controller.call("stop_navigation")
			_clear_pending_arrival_state()
			_apply_follow_look_ik(look_target)
			if _action_controller != null and _action_controller.has_method("trigger_action"):
				_action_controller.call("trigger_action", &"Idle")
			summary["command_applied"] = true
			summary["navigation_mode"] = COMMAND_LOOK_AT_PLAYER
			return true

		COMMAND_SIT_DOWN:
			if _action_controller == null:
				summary["errors"].append("action_controller_missing")
				return true
			if not _action_controller.has_method("navigate_to"):
				summary["errors"].append("action_controller_has_no_navigate_to")
				return true

			_invalidate_pending_snap()
			var sit_marker: Marker3D = _extract_target_marker(payload, &"SittingIdle")
			if sit_marker == null:
				sit_marker = _find_best_marker_for_action(&"SittingIdle", table_sit_marker_keywords, PackedStringArray())
			if sit_marker == null:
				summary["errors"].append("table_sit_marker_not_found")
				return true

			var toggle_stand: bool = bool(payload.get("toggle_stand_if_seated", false))
			var stand_check_distance: float = float(payload.get("stand_toggle_distance", stand_toggle_distance_default))
			var is_sitting_state: bool = _is_sitting_context_state_name(_get_action_controller_state_name())
			var is_near_requested_seat: bool = _is_currently_sitting_near_marker(sit_marker, stand_check_distance)
			var has_explicit_stand_target: bool = payload.has("stand_marker") or payload.has("stand_marker_path")
			var same_active_seat: bool = String(sit_marker.get_path()) == _active_sit_marker_path
			var allow_state_toggle: bool = sit_toggle_stand_when_in_sit_state and is_sitting_state and has_explicit_stand_target and same_active_seat
			if toggle_stand and (is_near_requested_seat or allow_state_toggle):
				_clear_pending_sit_state()
				_active_sit_marker_path = ""
				var stand_marker: Marker3D = _extract_stand_marker(payload)
				if stand_marker == null:
					stand_marker = sit_marker
				var stand_action_name: StringName = _normalize_action_name_for_command(payload.get("stand_action", "Idle"), &"Idle")
				_navigate_to_marker_and_queue_action(stand_marker, stand_action_name, "stand_up", summary)
				return true

			var sit_action_name: StringName = _normalize_action_name_for_command(payload.get("action", "SittingIdle"), &"SittingIdle")
			var approach_marker: Marker3D = _extract_approach_marker(payload, sit_marker)
			_apply_sit_navigation_precision()
			if sit_use_approach_marker_pipeline:
				if approach_marker != null:
					_navigate_to_sit_with_approach(approach_marker, sit_marker, sit_action_name, summary)
					return true
				if sit_auto_generate_approach_when_missing:
					_navigate_to_sit_with_virtual_approach(sit_marker, sit_action_name, summary)
					return true

			_clear_pending_sit_state()
			_navigate_to_marker_and_queue_action(sit_marker, sit_action_name, COMMAND_SIT_DOWN, summary)
			return true

		COMMAND_GO_TO_MARKER:
			if _action_controller == null:
				summary["errors"].append("action_controller_missing")
				return true
			if not _action_controller.has_method("navigate_to"):
				summary["errors"].append("action_controller_has_no_navigate_to")
				return true

			_invalidate_pending_snap()
			var target_marker: Marker3D = _extract_target_marker(payload)
			if target_marker == null:
				summary["errors"].append("target_marker_not_found")
				return true
			_navigate_to_marker(target_marker, COMMAND_GO_TO_MARKER, summary)
			return true

		_:
			summary["errors"].append("unsupported_command:" + command_name)
			return true

func _extract_command_value(payload: Dictionary) -> Variant:
	var top_value: Variant = _extract_command_value_from_dict(payload)
	if top_value != null:
		return top_value

	for nested_key in ["action_hint", "navigation", "intent_payload", "command_payload"]:
		if not payload.has(nested_key):
			continue
		var nested_value: Variant = payload[nested_key]
		if nested_value is Dictionary:
			var nested_dict: Dictionary = nested_value as Dictionary
			var nested_command: Variant = _extract_command_value_from_dict(nested_dict)
			if nested_command != null:
				return nested_command
	return null

func _extract_command_value_from_dict(source: Dictionary) -> Variant:
	for key in ["command", "intent", "navigation_command", "task", "operation", "navigation_intent"]:
		if source.has(key):
			return source[key]

	# Compatibility: some payloads put command words directly in "action".
	if source.has("action"):
		var action_value: Variant = source["action"]
		if not _normalize_command_name(action_value).is_empty():
			return action_value
	return null

func _normalize_command_name(command_value: Variant) -> String:
	if command_value == null:
		return ""

	var raw_command: String = ""
	if command_value is Dictionary:
		var command_dict: Dictionary = command_value as Dictionary
		for key in ["name", "command", "intent", "type", "task"]:
			if not command_dict.has(key):
				continue
			raw_command = String(command_dict[key]).strip_edges()
			if not raw_command.is_empty():
				break
	else:
		raw_command = String(command_value).strip_edges()

	raw_command = raw_command.strip_edges()
	if raw_command.is_empty():
		return ""

	var command_key: String = _canonicalize_command_key(raw_command)
	if COMMAND_ALIASES.has(command_key):
		return String(COMMAND_ALIASES[command_key])

	var guessed: String = _guess_command_from_text(raw_command)
	if not guessed.is_empty():
		return guessed
	return ""

func _canonicalize_command_key(raw_text: String) -> String:
	var normalized: String = raw_text.strip_edges().to_lower()
	for token in [" ", "-", ".", ",", ";", ":", "/", "\\", "\n", "\t"]:
		normalized = normalized.replace(token, "_")
	while normalized.find("__") >= 0:
		normalized = normalized.replace("__", "_")
	return normalized.strip_edges()

func _guess_command_from_text(raw_text: String) -> String:
	var lower_text: String = raw_text.strip_edges().to_lower()
	if lower_text.is_empty():
		return ""

	var canonical: String = _canonicalize_command_key(lower_text)
	if canonical.contains("stop") and canonical.contains("follow"):
		return COMMAND_STOP_FOLLOW
	if canonical.contains("follow"):
		return COMMAND_FOLLOW_PLAYER

	if lower_text.find("停止") >= 0 and (lower_text.find("跟") >= 0 or lower_text.find("follow") >= 0):
		return COMMAND_STOP_FOLLOW
	if (lower_text.find("跟着") >= 0 or lower_text.find("跟随") >= 0) and lower_text.find("别") < 0:
		return COMMAND_FOLLOW_PLAYER

	if canonical.contains("look") and (canonical.contains("me") or canonical.contains("player")):
		return COMMAND_LOOK_AT_PLAYER
	if lower_text.find("看着我") >= 0 or lower_text.find("看我") >= 0 or lower_text.find("面向我") >= 0:
		return COMMAND_LOOK_AT_PLAYER

	if canonical == "sit" or canonical == "sit_down" or canonical == "sitdown" or canonical == "go_sit":
		return COMMAND_SIT_DOWN
	if lower_text.find("坐下") >= 0 or lower_text.find("坐着") >= 0:
		return COMMAND_SIT_DOWN
	if canonical.contains("go_to") or canonical.contains("goto") or canonical.contains("marker"):
		return COMMAND_GO_TO_MARKER
	if lower_text.find("去") >= 0 and (lower_text.find("标记") >= 0 or lower_text.find("位置") >= 0):
		return COMMAND_GO_TO_MARKER

	return ""

func _extract_marker_name_from_command_value(command_value: Variant) -> String:
	if command_value == null:
		return ""

	if command_value is Dictionary:
		return _extract_target_marker_name_from_dict(command_value as Dictionary)

	var raw_text: String = String(command_value).strip_edges()
	if raw_text.is_empty():
		return ""

	for splitter in [":", "/", "|", "->"]:
		if raw_text.find(splitter) < 0:
			continue
		var parts: PackedStringArray = raw_text.split(splitter, false)
		if parts.size() < 2:
			continue
		var tail: String = parts[parts.size() - 1].strip_edges()
		if tail.is_empty():
			continue
		if _normalize_command_name(tail).is_empty():
			return tail

	return _infer_marker_name_from_text(raw_text)

func _infer_marker_name_from_text(raw_text: String) -> String:
	var lower_text: String = raw_text.to_lower()

	for key in LOCATION_KEYWORD_MARKERS.keys():
		var key_text: String = String(key)
		if key_text.is_empty():
			continue
		if lower_text.find(key_text.to_lower()) >= 0:
			return String(LOCATION_KEYWORD_MARKERS[key])

	var markers: Array[Marker3D] = _collect_scene_markers()
	for marker in markers:
		var marker_name: String = String(marker.name)
		if marker_name.is_empty():
			continue
		if lower_text.find(marker_name.to_lower()) >= 0:
			return marker_name
	return ""

func _extract_target_marker(payload: Dictionary, preferred_action: StringName = &"") -> Marker3D:
	var marker_path: String = _extract_target_marker_path(payload)
	if not marker_path.is_empty():
		var by_path: Marker3D = _find_marker_by_path(marker_path, preferred_action)
		if by_path != null:
			return by_path

	var marker_name: String = _extract_target_marker_name(payload)
	if marker_name.is_empty():
		return null
	return _find_marker_by_name(marker_name, preferred_action)

func _extract_stand_marker(payload: Dictionary) -> Marker3D:
	var stand_path: String = _extract_marker_path(payload, PackedStringArray(["stand_marker_path", "exit_marker_path"]))
	if not stand_path.is_empty():
		var by_path: Marker3D = _find_marker_by_path(stand_path, &"")
		if by_path != null:
			return by_path

	var stand_name: String = _extract_marker_name_by_keys(payload, PackedStringArray(["stand_marker", "exit_marker"]))
	if stand_name.is_empty():
		return null
	return _find_marker_by_name(stand_name)

func _extract_approach_marker(payload: Dictionary, seat_marker: Marker3D = null) -> Marker3D:
	var approach_path: String = _extract_marker_path(payload, PackedStringArray(["approach_marker_path", "approach_path", "entry_marker_path"]))
	if not approach_path.is_empty():
		var by_path: Marker3D = _find_marker_by_path(approach_path, &"")
		if by_path != null:
			return by_path

	var approach_name: String = _extract_marker_name_by_keys(payload, PackedStringArray(["approach_marker", "approach_marker_name", "entry_marker", "entry_marker_name"]))
	if not approach_name.is_empty():
		var by_name: Marker3D = _find_marker_by_name(approach_name)
		if by_name != null:
			return by_name

	var sibling_marker: Marker3D = _resolve_marker_sibling(seat_marker, "Approach_Mark3D")
	if sibling_marker != null:
		return sibling_marker
	return null

func _resolve_marker_sibling(reference_marker: Marker3D, sibling_name: String) -> Marker3D:
	if reference_marker == null:
		return null
	var parent: Node = reference_marker.get_parent()
	if parent == null:
		return null
	var direct: Node = parent.get_node_or_null(NodePath(sibling_name))
	if direct is Marker3D:
		return direct as Marker3D
	var sibling_lower: String = sibling_name.to_lower()
	for child in parent.get_children():
		var child_node: Node = child as Node
		if child_node == null:
			continue
		if not (child_node is Marker3D):
			continue
		if String(child_node.name).to_lower() == sibling_lower:
			return child_node as Marker3D
	return null

func _extract_target_marker_path(payload: Dictionary) -> String:
	return _extract_marker_path(payload, PackedStringArray(["target_marker_path", "marker_path", "destination_marker_path"]))

func _extract_marker_path(payload: Dictionary, keys: PackedStringArray) -> String:
	var top_value: String = _extract_marker_path_from_dict(payload, keys)
	if not top_value.is_empty():
		return top_value

	var command_value: Variant = _extract_command_value(payload)
	if command_value is Dictionary:
		var command_dict: Dictionary = command_value as Dictionary
		var nested_value: String = _extract_marker_path_from_dict(command_dict, keys)
		if not nested_value.is_empty():
			return nested_value

	for nested_key in ["action_hint", "navigation", "intent_payload", "command_payload"]:
		if not payload.has(nested_key):
			continue
		var nested_variant: Variant = payload[nested_key]
		if nested_variant is not Dictionary:
			continue
		var nested_dict: Dictionary = nested_variant as Dictionary
		var found: String = _extract_marker_path_from_dict(nested_dict, keys)
		if not found.is_empty():
			return found
	return ""

func _extract_marker_path_from_dict(source: Dictionary, keys: PackedStringArray) -> String:
	for key in keys:
		if not source.has(key):
			continue
		var raw_text: String = String(source[key]).strip_edges()
		if not raw_text.is_empty():
			return raw_text
	return ""

func _extract_marker_name_by_keys(payload: Dictionary, keys: PackedStringArray) -> String:
	var top_value: String = _extract_marker_name_by_keys_from_dict(payload, keys)
	if not top_value.is_empty():
		return top_value

	var command_value: Variant = _extract_command_value(payload)
	if command_value is Dictionary:
		var command_dict: Dictionary = command_value as Dictionary
		var nested_value: String = _extract_marker_name_by_keys_from_dict(command_dict, keys)
		if not nested_value.is_empty():
			return nested_value

	for nested_key in ["action_hint", "navigation", "intent_payload", "command_payload"]:
		if not payload.has(nested_key):
			continue
		var nested_variant: Variant = payload[nested_key]
		if nested_variant is not Dictionary:
			continue
		var nested_dict: Dictionary = nested_variant as Dictionary
		var found: String = _extract_marker_name_by_keys_from_dict(nested_dict, keys)
		if not found.is_empty():
			return found
	return ""

func _extract_marker_name_by_keys_from_dict(source: Dictionary, keys: PackedStringArray) -> String:
	for key in keys:
		if not source.has(key):
			continue
		var raw_text: String = String(source[key]).strip_edges()
		if raw_text.is_empty():
			continue
		var inferred_marker: String = _infer_marker_name_from_text(raw_text)
		if not inferred_marker.is_empty():
			return inferred_marker
		return raw_text
	return ""

func _find_marker_by_path(marker_path: String, preferred_action: StringName = &"") -> Marker3D:
	var normalized_path: String = marker_path.strip_edges()
	if normalized_path.is_empty():
		return null

	var by_path: Node = get_node_or_null(NodePath(normalized_path))
	if by_path == null:
		var root: Node = _get_scene_search_root()
		if root != null:
			by_path = root.get_node_or_null(NodePath(normalized_path))
	if by_path is Marker3D:
		var marker := by_path as Marker3D
		if preferred_action == &"" or _marker_supports_action(marker, preferred_action):
			return marker
	return null

func _is_currently_sitting_near_marker(marker: Marker3D, check_distance: float) -> bool:
	if marker == null:
		return false
	if not (_action_controller is Node3D):
		return false
	var state_name: StringName = _get_action_controller_state_name()
	if not _is_sitting_context_state_name(state_name):
		return false
	var body: Node3D = _action_controller as Node3D
	var body_pos: Vector3 = body.global_position
	body_pos.y = 0.0
	var marker_pos: Vector3 = marker.global_position
	marker_pos.y = 0.0
	var safe_distance: float = maxf(0.1, check_distance)
	return body_pos.distance_to(marker_pos) <= safe_distance

func _get_action_controller_state_name() -> StringName:
	if _action_controller == null:
		return &""
	if _action_controller.has_method("get_current_state_name"):
		var value: Variant = _action_controller.call("get_current_state_name")
		if value != null:
			var state_text: String = String(value).strip_edges()
			if not state_text.is_empty():
				return StringName(state_text)
	return &""

func _is_sitting_context_state_name(state_name: StringName) -> bool:
	var state_text: String = String(state_name).to_lower()
	if state_text.is_empty():
		return false
	return state_text.find("sit") >= 0 or state_text.find("sitting") >= 0

func _normalize_action_name_for_command(action_value: Variant, fallback: StringName = &"Idle") -> StringName:
	var action_text: String = String(action_value).strip_edges()
	if action_text.is_empty():
		return fallback
	for known_action in KNOWN_ACTIONS:
		if known_action.to_lower() == action_text.to_lower():
			return StringName(known_action)
	return fallback

func _extract_target_marker_name(payload: Dictionary) -> String:
	var top_marker: String = _extract_target_marker_name_from_dict(payload)
	if not top_marker.is_empty():
		return top_marker

	var command_value: Variant = _extract_command_value(payload)
	if command_value is Dictionary:
		var command_dict: Dictionary = command_value as Dictionary
		var nested_marker: String = _extract_target_marker_name_from_dict(command_dict)
		if not nested_marker.is_empty():
			return nested_marker

	for nested_key in ["action_hint", "navigation", "intent_payload", "command_payload"]:
		if not payload.has(nested_key):
			continue
		var nested_value: Variant = payload[nested_key]
		if nested_value is not Dictionary:
			continue
		var marker_name: String = _extract_target_marker_name_from_dict(nested_value as Dictionary)
		if not marker_name.is_empty():
			return marker_name

	return ""

func _extract_target_marker_name_from_dict(source: Dictionary) -> String:
	var supported_keys: PackedStringArray = PackedStringArray([
		"target_marker",
		"marker_name",
		"marker",
		"destination_marker",
		"target_location",
		"location",
		"room",
		"destination",
		"poi",
		"place",
	])
	for source_key_variant in source.keys():
		var source_key: String = String(source_key_variant).strip_edges().to_lower()
		if source_key.is_empty():
			continue
		if supported_keys.find(source_key) < 0:
			continue

		var raw_text: String = String(source[source_key_variant]).strip_edges()
		if raw_text.is_empty():
			continue
		var inferred_marker: String = _infer_marker_name_from_text(raw_text)
		if not inferred_marker.is_empty():
			return inferred_marker
		return raw_text
	return ""

func _resolve_follow_target(payload: Dictionary) -> Node3D:
	if follow_target_path != NodePath():
		var by_export: Node3D = get_node_or_null(follow_target_path) as Node3D
		if by_export != null:
			return by_export

	var hint: String = _extract_follow_target_hint_from_dict(payload)

	var command_value: Variant = _extract_command_value(payload)
	if hint.is_empty() and command_value is Dictionary:
		var command_dict: Dictionary = command_value as Dictionary
		hint = _extract_follow_target_hint_from_dict(command_dict)

	if hint.is_empty():
		for nested_key in ["action_hint", "navigation", "intent_payload", "command_payload"]:
			if not payload.has(nested_key):
				continue
			var nested_value: Variant = payload[nested_key]
			if nested_value is not Dictionary:
				continue
			hint = _extract_follow_target_hint_from_dict(nested_value as Dictionary)
			if not hint.is_empty():
				break

	if not hint.is_empty():
		var by_hint: Node3D = _resolve_follow_target_by_hint(hint)
		if by_hint != null:
			return by_hint

	var global_node: Node = get_node_or_null("/root/Global")
	if global_node != null:
		var player_variant: Variant = global_node.get("player")
		if player_variant is Node3D and is_instance_valid(player_variant):
			return player_variant as Node3D

	var players: Array = get_tree().get_nodes_in_group(&"Player")
	for entry in players:
		if entry is Node3D and is_instance_valid(entry):
			return entry as Node3D

	return _resolve_follow_target_by_hint("player")

func _extract_follow_target_hint_from_dict(source: Dictionary) -> String:
	for key in ["follow_target", "follow_target_path", "target_node", "target_name"]:
		if not source.has(key):
			continue
		var hint: String = String(source[key]).strip_edges()
		if not hint.is_empty():
			return hint
	return ""

func _resolve_follow_target_by_hint(hint: String) -> Node3D:
	if hint.is_empty():
		return null

	var by_path: Node = get_node_or_null(NodePath(hint))
	if by_path is Node3D:
		return by_path as Node3D

	var root: Node = _get_scene_search_root()
	if root == null:
		return null
	return _find_node3d_by_name_recursive(root, hint.to_lower())

func _navigate_to_sit_with_approach(approach_marker: Marker3D, seat_marker: Marker3D, sit_action_name: StringName, summary: Dictionary) -> void:
	if _action_controller == null or not _action_controller.has_method("navigate_to"):
		summary["errors"].append("action_controller_has_no_navigate_to")
		return
	if approach_marker == null or seat_marker == null:
		summary["errors"].append("sit_markers_missing")
		return

	_apply_sit_navigation_precision()
	_navigate_to_marker(approach_marker, COMMAND_SIT_DOWN, summary)
	_pending_sit_approach_marker_name = String(approach_marker.get_path())
	_pending_sit_seat_marker_name = String(seat_marker.get_path())
	_pending_sit_action_on_arrival = sit_action_name
	summary["target_marker"] = _pending_sit_seat_marker_name
	summary["action_requested"] = String(sit_action_name)
	summary["action_queued"] = true
	summary["queued_action"] = String(sit_action_name)

func _navigate_to_sit_with_virtual_approach(seat_marker: Marker3D, sit_action_name: StringName, summary: Dictionary) -> void:
	if _action_controller == null or not _action_controller.has_method("navigate_to"):
		summary["errors"].append("action_controller_has_no_navigate_to")
		return
	if seat_marker == null:
		summary["errors"].append("sit_marker_missing")
		return

	_apply_sit_navigation_precision()
	var virtual_approach_target: Vector3 = _build_virtual_sit_approach_position(seat_marker)
	_action_controller.call("navigate_to", virtual_approach_target)
	_clear_pending_arrival_state()
	_clear_marker_interaction_ik()
	_pending_sit_virtual_approach = true
	_pending_sit_approach_marker_name = ""
	_pending_sit_seat_marker_name = String(seat_marker.get_path())
	_pending_sit_action_on_arrival = sit_action_name

	summary["command_applied"] = true
	summary["moved"] = true
	summary["move_target"] = virtual_approach_target
	summary["navigation_mode"] = COMMAND_SIT_DOWN
	summary["target_marker"] = _pending_sit_seat_marker_name
	summary["action_requested"] = String(sit_action_name)
	summary["action_queued"] = true
	summary["queued_action"] = String(sit_action_name)

func _build_virtual_sit_approach_position(seat_marker: Marker3D) -> Vector3:
	if seat_marker == null:
		return Vector3.ZERO

	var final_body_transform: Transform3D = _compute_body_transform_for_marker(seat_marker, true, true)
	var final_body_pos: Vector3 = final_body_transform.origin
	var marker_forward: Vector3 = _extract_marker_flat_forward(seat_marker)
	var approach_distance: float = maxf(0.2, sit_auto_approach_distance)
	var body_pos: Vector3 = _get_action_controller_world_position()

	var candidate_offsets: PackedFloat32Array = PackedFloat32Array()
	if sit_virtual_approach_auto_choose_side:
		candidate_offsets.append(1.0)
		candidate_offsets.append(-1.0)
	else:
		candidate_offsets.append(1.0 if sit_virtual_approach_use_positive_marker_z else -1.0)

	var best_target: Vector3 = final_body_pos
	var best_score: float = INF
	for offset_sign in candidate_offsets:
		var candidate: Vector3 = final_body_pos + marker_forward * float(offset_sign) * approach_distance
		if body_pos != Vector3.INF:
			candidate.y = body_pos.y
		var projected: Vector3 = _project_to_navigation_target(candidate)
		var score: float = _score_sit_approach_target(projected, body_pos)
		if score < best_score:
			best_score = score
			best_target = projected

	return best_target

func _score_sit_approach_target(candidate: Vector3, body_pos: Vector3) -> float:
	if body_pos == Vector3.INF:
		return 0.0
	var dx: float = candidate.x - body_pos.x
	var dz: float = candidate.z - body_pos.z
	return sqrt(dx * dx + dz * dz)

func _extract_marker_flat_forward(marker: Marker3D) -> Vector3:
	if marker == null:
		return Vector3(0.0, 0.0, 1.0)
	var marker_forward: Vector3 = marker.global_basis.z
	marker_forward.y = 0.0
	if marker_forward.length_squared() <= 0.0001:
		return Vector3(0.0, 0.0, 1.0)
	return marker_forward.normalized()

func _find_node3d_by_name_recursive(root_node: Node, lower_name: String) -> Node3D:
	if root_node == null:
		return null

	if root_node is Node3D and String(root_node.name).to_lower() == lower_name:
		return root_node as Node3D

	for child in root_node.get_children():
		var child_node: Node = child as Node
		if child_node == null:
			continue
		var nested: Node3D = _find_node3d_by_name_recursive(child_node, lower_name)
		if nested != null:
			return nested
	return null

func _navigate_to_marker_and_queue_action(marker: Marker3D, action_name: StringName, navigation_mode: String, summary: Dictionary) -> void:
	if _action_controller == null or not _action_controller.has_method("navigate_to"):
		summary["errors"].append("action_controller_has_no_navigate_to")
		return

	var marker_probe: Vector3 = _build_marker_navigation_probe(marker)
	var target_position: Vector3 = _project_to_navigation_target(marker_probe)
	_action_controller.call("navigate_to", target_position)
	_clear_pending_arrival_state()
	_clear_marker_interaction_ik()
	var marker_ref: String = String(marker.get_path())
	_set_pending_arrival_marker(marker_ref)
	_set_pending_arrival_action(action_name, marker_ref)

	summary["command_applied"] = true
	summary["moved"] = true
	summary["move_target"] = target_position
	summary["navigation_mode"] = navigation_mode
	summary["target_marker"] = marker_ref
	summary["action_requested"] = String(action_name)
	summary["action_queued"] = true
	summary["queued_action"] = String(action_name)

func _navigate_to_marker(marker: Marker3D, navigation_mode: String, summary: Dictionary) -> void:
	if _action_controller == null or not _action_controller.has_method("navigate_to"):
		summary["errors"].append("action_controller_has_no_navigate_to")
		return

	var marker_probe: Vector3 = _build_marker_navigation_probe(marker)
	var target_position: Vector3 = _project_to_navigation_target(marker_probe)
	_action_controller.call("navigate_to", target_position)
	_clear_pending_arrival_state()
	_clear_marker_interaction_ik()
	_set_pending_arrival_marker(String(marker.get_path()))

	summary["command_applied"] = true
	summary["moved"] = true
	summary["move_target"] = target_position
	summary["navigation_mode"] = navigation_mode
	summary["target_marker"] = String(marker.get_path())

	if not go_to_marker_respect_marker_action:
		return

	var marker_action: StringName = _get_marker_meta_action(marker)
	if marker_action == &"":
		return

	summary["action_requested"] = String(marker_action)
	if _should_defer_action_until_arrival(marker_action):
		_set_pending_arrival_action(marker_action, String(marker.get_path()))
		summary["action_queued"] = true
		summary["queued_action"] = String(marker_action)
	elif _action_controller != null and _action_controller.has_method("trigger_action"):
		summary["action_applied"] = bool(_action_controller.call("trigger_action", marker_action))
	else:
		summary["errors"].append("action_controller_has_no_trigger_action")
		_clear_pending_arrival_state()

func _get_marker_meta_action(marker: Marker3D) -> StringName:
	if marker == null or not marker.has_meta("xiaokong_action"):
		return &""
	var raw_action: String = String(marker.get_meta("xiaokong_action")).strip_edges()
	if raw_action.is_empty():
		return &""
	if KNOWN_ACTIONS.has(raw_action):
		return StringName(raw_action)
	return &""

func _build_marker_navigation_probe(marker: Marker3D) -> Vector3:
	var marker_position: Vector3 = marker.global_position
	var body_position: Vector3 = _get_action_controller_world_position()
	if body_position == Vector3.INF:
		return marker_position
	return Vector3(marker_position.x, body_position.y, marker_position.z)

func _find_marker_by_name(marker_name: String, preferred_action: StringName = &"") -> Marker3D:
	var trimmed_name: String = marker_name.strip_edges()
	if trimmed_name.is_empty():
		return null
	var lower_name: String = trimmed_name.to_lower()

	var markers: Array[Marker3D] = _collect_scene_markers()
	for marker in markers:
		if String(marker.name).to_lower() != lower_name:
			continue
		if preferred_action != &"" and not _marker_supports_action(marker, preferred_action):
			continue
		return marker
	return null

func _find_best_marker_for_action(action_name: StringName, keywords: PackedStringArray, priority_names: PackedStringArray) -> Marker3D:
	var markers: Array[Marker3D] = _collect_scene_markers()
	if markers.is_empty():
		return null

	var origin: Vector3 = Vector3.ZERO
	if _action_controller is Node3D:
		origin = (_action_controller as Node3D).global_position

	var best_marker: Marker3D = null
	var best_score: float = INF

	for pass_index in range(2):
		var require_keyword: bool = pass_index == 0 and not keywords.is_empty()
		best_marker = null
		best_score = INF

		for marker in markers:
			if not _marker_supports_action(marker, action_name):
				continue

			if require_keyword and not _marker_name_has_any_keyword(marker, keywords):
				continue

			var score: float = origin.distance_to(marker.global_position)
			var priority_idx: int = priority_names.find(String(marker.name))
			if priority_idx >= 0:
				score -= 10.0 - float(priority_idx) * 0.1

			if score < best_score:
				best_score = score
				best_marker = marker

		if best_marker != null:
			return best_marker

	return null

func _collect_scene_markers() -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	var search_root: Node = null
	if markers_root_path != NodePath():
		search_root = get_node_or_null(markers_root_path)
	if search_root == null:
		search_root = _get_scene_search_root()
	if search_root == null:
		return markers

	_collect_scene_markers_recursive(search_root, markers)
	return markers

func _collect_scene_markers_recursive(root_node: Node, out_markers: Array[Marker3D]) -> void:
	if root_node == null:
		return

	if root_node is Marker3D:
		var marker := root_node as Marker3D
		if _is_marker_candidate(marker):
			out_markers.append(marker)

	for child in root_node.get_children():
		var child_node: Node = child as Node
		if child_node == null:
			continue
		_collect_scene_markers_recursive(child_node, out_markers)

func _is_marker_candidate(marker: Marker3D) -> bool:
	if marker == null:
		return false

	if _action_controller != null and _action_controller.is_ancestor_of(marker):
		return false

	var marker_name: String = String(marker.name)
	if marker_name.findn("mark3d") >= 0:
		return true
	if marker.has_meta("xiaokong_action"):
		return true
	if marker.has_meta("xiaokong_ik_mode"):
		return true
	return false

func _apply_marker_interaction_ik(marker: Marker3D) -> void:
	if _ik_target_driver == null or not is_instance_valid(_ik_target_driver):
		return
	if not _ik_target_driver.has_method("apply_marker_interaction"):
		return
	_ik_target_driver.call("apply_marker_interaction", marker)

func _apply_follow_look_ik(target: Node3D) -> void:
	if _ik_target_driver == null or not is_instance_valid(_ik_target_driver):
		return
	if not _ik_target_driver.has_method("apply_look_at_target"):
		return
	_ik_target_driver.call("apply_look_at_target", target, Vector3(0.0, 1.35, 0.0), 0.0)

func _clear_marker_interaction_ik() -> void:
	if _ik_target_driver == null or not is_instance_valid(_ik_target_driver):
		return
	if not _ik_target_driver.has_method("clear_marker_interaction"):
		return
	_ik_target_driver.call("clear_marker_interaction")

func _marker_supports_action(marker: Marker3D, action_name: StringName) -> bool:
	if marker == null:
		return false

	if marker.has_meta("xiaokong_action"):
		var meta_action: StringName = StringName(String(marker.get_meta("xiaokong_action")).strip_edges())
		return meta_action == action_name

	var lower_name: String = String(marker.name).to_lower()
	if action_name == &"Laying":
		return lower_name.find("lay") >= 0 or lower_name.find("lie") >= 0 or lower_name.find("sleep") >= 0 or lower_name.find("bed") >= 0
	if action_name == &"SittingIdle":
		return lower_name.find("sit") >= 0 or lower_name.find("bench") >= 0 or lower_name.find("table") >= 0 or lower_name.find("chair") >= 0 or lower_name.find("stool") >= 0 or lower_name.find("bed") >= 0
	return true

func _marker_name_has_any_keyword(marker: Marker3D, keywords: PackedStringArray) -> bool:
	if marker == null:
		return false
	if keywords.is_empty():
		return true

	var lower_name: String = String(marker.name).to_lower()
	for keyword in keywords:
		var lower_keyword: String = String(keyword).to_lower()
		if lower_keyword.is_empty():
			continue
		if lower_name.find(lower_keyword) >= 0:
			return true
	return false

func _get_scene_search_root() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	if tree.current_scene != null:
		return tree.current_scene
	return tree.root

func _should_defer_action_until_arrival(action_name: StringName) -> bool:
	return DEFER_ACTIONS_UNTIL_ARRIVAL.has(String(action_name))

func _normalize_action(action_value: Variant) -> StringName:
	var raw: String = String(action_value).strip_edges()
	if raw.is_empty():
		return &""

	if KNOWN_ACTIONS.has(raw):
		if ALLOWED_DIRECT_ACTIONS.has(raw):
			return StringName(raw)
		return &""

	var alias_key: String = raw.to_lower()
	if action_aliases.has(alias_key):
		var mapped: String = String(action_aliases[alias_key]).strip_edges()
		if KNOWN_ACTIONS.has(mapped) and ALLOWED_DIRECT_ACTIONS.has(mapped):
			return StringName(mapped)

	return &""

func _normalize_stat_change(raw_delta: Dictionary) -> Dictionary:
	var delta: Dictionary = {}
	var supported: PackedStringArray = PackedStringArray(["hunger", "thirst", "mood", "favor", "ai_hunger", "ai_thirst", "ai_mood", "ai_favor"])
	for key in supported:
		if raw_delta.has(key):
			delta[key] = float(raw_delta[key])
	return delta

func _find_state_component() -> XiaokongStateComponent:
	var parent_node: Node = get_parent()
	if parent_node == null:
		return null

	for child in parent_node.get_children():
		var state: XiaokongStateComponent = child as XiaokongStateComponent
		if state != null:
			return state
	return null

func _find_node_with_method_recursive(root_node: Node, method_name: StringName) -> Node:
	if root_node == null:
		return null
	for child in root_node.get_children():
		var child_node: Node = child as Node
		if child_node == null:
			continue
		if child_node.has_method(method_name):
			return child_node
		var nested: Node = _find_node_with_method_recursive(child_node, method_name)
		if nested != null:
			return nested
	return null
