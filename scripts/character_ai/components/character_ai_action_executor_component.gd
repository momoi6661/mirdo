extends Node
class_name CharacterAIActionExecutorComponent

signal ai_response_application_started(ai_data: Dictionary)
signal ai_response_application_finished(report: Dictionary)
signal navigation_started(target_marker_path: NodePath, arrival_action: StringName)
signal navigation_finished(arrival_action: StringName)
signal navigation_cancelled()
signal stand_up_finished()

@export var intent_interpreter_path: NodePath
@export var perception_component_path: NodePath
@export var animation_behavior_path: NodePath
@export var face_component_path: NodePath
@export var navigation_motor_path: NodePath
@export var actor_path: NodePath
@export var navigation_agent_path: NodePath
@export var world_object_group: StringName = &"ai_world_object"
@export var ai_nav_point_group: StringName = &"ai_nav_point"
@export var default_idle_action: StringName = &"idle_normal"
@export var default_talk_action: StringName = &"cute_explain"
@export var walk_action: StringName = &"walk"
@export var run_action: StringName = &"run"
@export var stop_action: StringName = &"idle_normal"
@export_range(0.1, 8.0, 0.05) var move_speed: float = 1.8
@export_range(0.1, 8.0, 0.05) var run_speed: float = 3.6
@export_range(0.05, 2.0, 0.01) var arrival_distance: float = 0.35
@export_range(0.1, 5.0, 0.05) var follow_distance: float = 1.4
@export_range(0.0, 30.0, 0.1) var turn_lerp_speed: float = 4.0
@export_range(0.0, 3.0, 0.01) var look_at_player_face_hold_sec: float = 1.05
@export_category("Seat Exit")
@export_range(0.0, 3.0, 0.01) var stand_relocate_delay_sec: float = 0.92
@export_range(0.0, 1.0, 0.01) var stand_relocate_duration_sec: float = 0.16
@export_range(0.0, 2.0, 0.01) var stand_relocate_max_planar_distance: float = 1.25
@export_range(0.0, 4.0, 0.01) var stand_root_motion_wait_sec: float = 1.15
@export_range(0.0, 1.0, 0.01) var stand_root_motion_end_margin_sec: float = 0.08
@export_range(0.0, 4.0, 0.01) var stand_resume_navigation_delay_sec: float = 0.45
@export_range(0.0, 2.0, 0.01) var stand_ready_max_planar_distance: float = 0.22
@export var stand_align_after_root_motion: bool = true
@export var stand_preserve_yaw_after_root_motion: bool = true
@export var stand_snap_after_root_motion_if_far: bool = true
@export_category("Seat Pose")
@export var seat_use_root_motion: bool = true
@export_range(0.0, 1.0, 0.01) var seat_pre_align_duration_sec: float = 0.12
@export_range(0.0, 3.0, 0.01) var seat_pre_align_max_planar_distance: float = 1.6
@export_range(0.0, 2.0, 0.01) var seat_exact_navigation_min_distance: float = 0.28
@export var seat_force_attach_before_action: bool = true
@export var require_semantic_sit_marker: bool = true
@export var seat_snap_if_no_root_motion: bool = false
@export var stand_use_root_motion: bool = true
@export var stand_snap_if_no_root_motion: bool = false
@export var auto_stand_before_navigation: bool = true
@export var debug_log: bool = false

var _intent_interpreter: Node
var _animation_behavior: Node
var _face_component: Node
var _navigation_motor: Node
var _actor: CharacterBody3D
var _navigation_agent: NavigationAgent3D
var _navigation_active: bool = false
var _follow_active: bool = false
var _navigation_target_position: Vector3 = Vector3.ZERO
var _navigation_target_marker_path: NodePath
var _pending_arrival_action: StringName = &""
var _moving_action: StringName = &""
var _pending_sit_marker_path: NodePath
var _active_sit_marker_path: NodePath
var _active_stand_marker_path: NodePath
var _pending_seat_marker_after_approach_path: NodePath
var _pending_seat_action_after_approach: StringName = &""
var _seat_exact_navigation_active: bool = false
var _seat_alignment_active: bool = false
var _stand_transition_active: bool = false
var _seat_alignment_serial: int = 0
var _stand_relocate_serial: int = 0
var _queued_navigation_after_stand: Dictionary = {}
var _face_player_hold_left: float = 0.0

func _ready() -> void:
	_refresh_refs()
	_bind_navigation_motor_signals()
	set_physics_process(true)

func execute_intent(intent: Dictionary) -> Dictionary:
	var intent_name := String(intent.get("intent", "")).strip_edges()
	var report := {
		"ok": false,
		"intent": intent_name,
		"target_object_id": "",
		"target_object_type": "",
		"target_object_tags": [],
		"target_marker_path": "",
		"chosen_action": "",
		"errors": [],
	}
	if intent_name.is_empty():
		report["errors"].append("intent_empty")
		return report
	match intent_name:
		"go_to_nav_point":
			_resolve_nav_point_marker(intent, report)
		"go_to_object", "sit_down":
			if _resolve_direct_marker_from_intent(intent, report):
				if report.get("ok", false):
					report["chosen_action"] = _choose_body_action_for_target(report, intent)
				return report
			_resolve_object_marker(intent, report)
			if report.get("ok", false):
				report["chosen_action"] = _choose_body_action_for_target(report, intent)
		"follow_player":
			report["ok"] = true
			report["chosen_action"] = walk_action
		"stop_follow":
			report["ok"] = true
			report["chosen_action"] = stop_action
		"look_at_player":
			report["ok"] = true
			report["chosen_action"] = StringName(String(intent.get("action", "listen")).strip_edges())
		"stand_up":
			if not _resolve_stand_marker_from_active_seat(intent, report):
				report["ok"] = true
				report["chosen_action"] = &"stand_up"
		"pick_up_item", "use_item", "eat_item":
			if _resolve_pickable_item_marker(intent, report):
				report["chosen_action"] = &"work_take_item"
		_:
			report["ok"] = true
	return report

func apply_ai_response(ai_data: Dictionary) -> Dictionary:
	ai_response_application_started.emit(ai_data.duplicate(true))
	_refresh_refs()
	var payload := _normalize_ai_payload(ai_data)
	var report := {
		"ok": true,
		"action_applied": false,
		"action": "",
		"intent": "",
		"intent_report": {},
		"expression_applied": false,
		"viseme_applied": false,
		"navigation_started": false,
		"errors": [],
	}

	_apply_face_payload(payload, report)

	var intent := _interpret_payload(payload)
	if bool(intent.get("ok", false)):
		report["intent"] = String(intent.get("intent", ""))
		var intent_report := execute_intent(intent)
		report["intent_report"] = intent_report
		if bool(intent_report.get("ok", false)):
			match String(intent.get("intent", "")):
				"follow_player":
					_clear_active_sit_marker()
					report["navigation_started"] = _start_follow_player()
					report["action_applied"] = report["navigation_started"]
					report["action"] = String(walk_action)
					ai_response_application_finished.emit(report.duplicate(true))
					return report
				"stop_follow":
					_stop_navigation()
					report["action_applied"] = _request_body_action(stop_action)
					report["action"] = String(stop_action)
					ai_response_application_finished.emit(report.duplicate(true))
					return report
				"look_at_player":
					_face_player()
				"stand_up":
					var stand_path_text := String(intent_report.get("target_marker_path", "")).strip_edges()
					_start_stand_up_from_active_seat(NodePath(stand_path_text) if not stand_path_text.is_empty() else NodePath())
					report["action_applied"] = true
					report["action"] = "stand_up"
					ai_response_application_finished.emit(report.duplicate(true))
					return report
			var chosen := StringName(String(intent_report.get("chosen_action", "")))
			var marker_path := String(intent_report.get("target_marker_path", "")).strip_edges()
			if not marker_path.is_empty():
				report["navigation_started"] = _start_navigation_to_marker(NodePath(marker_path), chosen)
				if report["navigation_started"]:
					report["action_applied"] = true
					report["action"] = String(walk_action)
					ai_response_application_finished.emit(report.duplicate(true))
					return report
			if chosen != &"":
				report["action_applied"] = _request_body_action(chosen)
				report["action"] = String(chosen)
			ai_response_application_finished.emit(report.duplicate(true))
			return report
		else:
			report["errors"].append_array(intent_report.get("errors", []))

	var action := _extract_body_action(payload)
	if action != &"":
		report["action_applied"] = _request_body_action(action)
		report["action"] = String(action)
	ai_response_application_finished.emit(report.duplicate(true))
	return report

func is_navigating() -> bool:
	var motor_active := _navigation_motor != null and _navigation_motor.has_method("is_navigating") and bool(_navigation_motor.call("is_navigating"))
	return motor_active or _navigation_active or _follow_active or _seat_exact_navigation_active or _seat_alignment_active or _stand_transition_active

func is_busy() -> bool:
	return is_navigating()

func stop_navigation_from_external() -> void:
	_stop_navigation(true)

func get_active_sit_marker() -> Marker3D:
	if _active_sit_marker_path == NodePath():
		return null
	return _get_marker_from_path(String(_active_sit_marker_path))

func get_active_sit_marker_path() -> String:
	return String(_active_sit_marker_path)

func clear_active_sit_marker() -> void:
	_clear_active_sit_marker()

func _physics_process(delta: float) -> void:
	if _navigation_motor != null and _navigation_motor.has_method("is_navigating"):
		_update_face_player_hold(delta)
		return
	if _follow_active:
		_update_follow_target()
	if not _navigation_active:
		_update_face_player_hold(delta)
		return
	_refresh_refs()
	if _actor == null:
		_stop_navigation(false)
		return

	var target_position := _navigation_target_position
	if _navigation_agent != null:
		target_position = _navigation_agent.get_next_path_position()
	var to_target := target_position - _actor.global_position
	to_target.y = 0.0
	var final_distance := _actor.global_position.distance_to(_navigation_target_position)
	if final_distance <= arrival_distance:
		_finish_navigation()
		return
	var direction := to_target.normalized() if to_target.length() > 0.01 else Vector3.ZERO
	if direction == Vector3.ZERO:
		return

	var speed := run_speed if final_distance > 5.0 else move_speed
	var moving_action := run_action if final_distance > 5.0 else walk_action
	if moving_action != _moving_action:
		_request_body_action(moving_action)
		_moving_action = moving_action

	_actor.velocity.x = direction.x * speed
	_actor.velocity.z = direction.z * speed
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	if not _actor.is_on_floor():
		_actor.velocity.y -= gravity * delta
	else:
		_actor.velocity.y = 0.0
	_actor.move_and_slide()
	_face_direction(direction, delta)

func _update_face_player_hold(delta: float) -> void:
	if _face_player_hold_left <= 0.0:
		return
	_face_player_hold_left = maxf(0.0, _face_player_hold_left - delta)
	_smooth_face_player(delta)

func _resolve_object_marker(intent: Dictionary, report: Dictionary) -> void:
	var target_ref := String(intent.get("target_ref", intent.get("target_object_id", ""))).strip_edges()
	if target_ref.is_empty():
		report["errors"].append("target_ref_empty")
		return
	var target := _find_world_object(target_ref)
	if target == null:
		report["errors"].append("target_object_not_found")
		return
	var role := String(intent.get("marker_role", "approach")).strip_edges()
	if role.is_empty():
		role = "approach"
	var marker: Marker3D = null
	if target.has_method("get_marker_for_role"):
		marker = target.call("get_marker_for_role", role) as Marker3D
	if marker == null and target.has_method("get_nav_marker"):
		marker = target.call("get_nav_marker") as Marker3D
	if _is_sit_action(StringName(String(intent.get("action", "")))) or role.to_lower() == "sit":
		marker = _resolve_sit_marker_for_point(marker) if marker != null else null
	if marker == null:
		report["errors"].append("target_marker_not_found")
		return
	report["ok"] = true
	var summary := _build_world_object_summary(target)
	report["target_object_id"] = String(summary.get("id", _get_world_object_id(target)))
	report["target_object_type"] = String(summary.get("type", _safe_get(target, "object_type", ""))).strip_edges()
	report["target_object_tags"] = _to_string_array(summary.get("tags", _safe_get(target, "tags", [])))
	report["target_marker_path"] = String(marker.get_path())
	report["marker_role"] = _get_marker_role(marker)

func _resolve_nav_point_marker(intent: Dictionary, report: Dictionary) -> void:
	var target_ref := String(intent.get("target_nav_point", intent.get("target_ref", ""))).strip_edges()
	if target_ref.is_empty():
		report["errors"].append("target_nav_point_empty")
		return
	var marker := _find_ai_nav_point(target_ref)
	if marker == null:
		report["errors"].append("target_nav_point_not_found")
		return
	var marker_role := String(_safe_get(marker, "marker_role", "")).strip_edges()
	report["ok"] = true
	report["target_object_id"] = target_ref
	report["target_object_type"] = String(_safe_get(marker, "point_type", "")).strip_edges()
	report["target_object_tags"] = _to_string_array(_safe_get(marker, "tags", []))
	report["target_marker_path"] = String(marker.get_path())
	report["marker_role"] = marker_role
	var action := String(intent.get("action", "")).strip_edges()
	if action.is_empty():
		action = String(_safe_get(marker, "arrival_action", "")).strip_edges()
	report["chosen_action"] = action

func _resolve_direct_marker_from_intent(intent: Dictionary, report: Dictionary) -> bool:
	var raw_path := String(intent.get("target_marker_path", intent.get("target_ref", ""))).strip_edges()
	if raw_path.is_empty():
		return false
	var marker := _get_marker_from_path(raw_path)
	if marker == null:
		return false
	report["ok"] = true
	report["target_object_id"] = raw_path
	report["target_object_type"] = "seat" if String(intent.get("intent", "")) == "sit_down" else "marker"
	report["target_object_tags"] = ["seat"] if String(intent.get("intent", "")) == "sit_down" else []
	report["target_marker_path"] = String(marker.get_path())
	report["marker_role"] = _get_marker_role(marker)
	return true

func _resolve_stand_marker_from_active_seat(intent: Dictionary, report: Dictionary) -> bool:
	var raw_path := String(intent.get("target_marker_path", intent.get("target_ref", ""))).strip_edges()
	if raw_path.is_empty() and _active_stand_marker_path != NodePath():
		raw_path = String(_active_stand_marker_path)
	var marker := _get_marker_from_path(raw_path) if not raw_path.is_empty() else null
	if marker == null:
		report["ok"] = true
		report["chosen_action"] = &"stand_up"
		return false
	var stand_marker := marker
	if _get_marker_role(marker) == "sit" or _has_tag(_to_string_array(_safe_get(marker, "tags", [])), "seat"):
		var resolved := _resolve_stand_marker_for_seat(marker)
		if resolved != null:
			stand_marker = resolved
	report["ok"] = true
	report["target_object_id"] = String(stand_marker.get_path())
	report["target_object_type"] = "stand_marker"
	report["target_object_tags"] = ["stand"]
	report["target_marker_path"] = String(stand_marker.get_path())
	report["chosen_action"] = &"stand_up"
	return true

func _resolve_pickable_item_marker(intent: Dictionary, report: Dictionary) -> bool:
	var target_ref := String(intent.get("target_ref", intent.get("target_object_id", ""))).strip_edges()
	if target_ref.is_empty():
		report["errors"].append("target_ref_empty")
		return false
	var target := _find_pickable_item(target_ref)
	if target == null:
		report["errors"].append("pickable_item_not_found")
		return false
	var marker: Marker3D = null
	if target.has_method("get_nav_marker"):
		marker = target.call("get_nav_marker") as Marker3D
	elif target.has_method("get_marker_for_role"):
		marker = target.call("get_marker_for_role", "approach") as Marker3D
	if marker == null and target is Marker3D:
		marker = target as Marker3D
	if marker == null:
		report["errors"].append("pickable_marker_not_found")
		return false
	report["ok"] = true
	report["target_object_id"] = target_ref
	report["target_object_type"] = "food"
	report["target_object_tags"] = ["food", "pickable", "usable"]
	report["target_marker_path"] = String(marker.get_path())
	return true

func _start_navigation_to_marker(marker_path: NodePath, arrival_action: StringName) -> bool:
	_refresh_refs()
	if marker_path == NodePath():
		return false
	if auto_stand_before_navigation and _should_stand_before_navigation(arrival_action):
		_queue_navigation_after_stand(marker_path, arrival_action)
		return true
	if not _ensure_seat_exit_completed_before_navigation(arrival_action):
		_queue_navigation_after_stand(marker_path, arrival_action)
		return true
	_seat_alignment_serial += 1
	_seat_alignment_active = false
	var marker := _get_marker_from_path(String(marker_path))
	if marker == null:
		_log("navigation marker missing: %s" % String(marker_path))
		return false
	var actual_marker := marker
	var actual_arrival_action := arrival_action
	if _is_sit_action(arrival_action):
		var seat_marker := _resolve_sit_marker_for_point(marker)
		if seat_marker == null:
			_log("sit navigation skipped: semantic sit marker missing for %s" % String(marker.get_path()))
			return false
		var approach_marker := _resolve_approach_marker_for_seat(seat_marker)
		if approach_marker == null and seat_marker != marker:
			approach_marker = marker
		if approach_marker != null and approach_marker != seat_marker:
			actual_marker = approach_marker
			actual_arrival_action = &""
			_pending_seat_marker_after_approach_path = seat_marker.get_path()
			_pending_seat_action_after_approach = arrival_action
		else:
			actual_marker = seat_marker
			_pending_seat_marker_after_approach_path = NodePath()
			_pending_seat_action_after_approach = &""
		_pending_sit_marker_path = seat_marker.get_path()
		var stand_marker := _resolve_stand_marker_for_seat(seat_marker)
		_active_stand_marker_path = stand_marker.get_path() if stand_marker != null else NodePath()
	else:
		_pending_sit_marker_path = NodePath()
		_pending_seat_marker_after_approach_path = NodePath()
		_pending_seat_action_after_approach = &""
	_pending_arrival_action = actual_arrival_action
	_navigation_target_marker_path = actual_marker.get_path()
	_navigation_target_position = actual_marker.global_position
	_navigation_active = true
	_follow_active = false
	_moving_action = &""
	if _navigation_motor != null and _navigation_motor.has_method("move_to_marker"):
		if not bool(_navigation_motor.call("move_to_marker", actual_marker, actual_arrival_action, false)):
			_navigation_active = false
			_navigation_target_marker_path = NodePath()
			_seat_exact_navigation_active = false
			return false
	elif _navigation_agent != null:
		_navigation_agent.target_desired_distance = arrival_distance
		_navigation_agent.path_desired_distance = maxf(0.05, arrival_distance * 0.5)
		_navigation_agent.target_position = _navigation_target_position
	if _navigation_motor == null:
		_request_body_action(walk_action)
	_log("navigation started marker=%s arrival_action=%s" % [String(actual_marker.get_path()), String(actual_arrival_action)])
	navigation_started.emit(actual_marker.get_path(), actual_arrival_action)
	return true

func _start_follow_player() -> bool:
	_refresh_refs()
	var player := _find_player()
	if player == null:
		return false
	if _navigation_motor != null and _navigation_motor.has_method("start_follow"):
		_follow_active = true
		_navigation_active = false
		return bool(_navigation_motor.call("start_follow", player, follow_distance))
	_follow_active = true
	_pending_arrival_action = &""
	_update_follow_target()
	_request_body_action(walk_action)
	return true

func _update_follow_target() -> void:
	var player := _find_player()
	if player == null or _actor == null:
		_stop_navigation()
		return
	var offset := _actor.global_position - player.global_position
	offset.y = 0.0
	if offset.length() < 0.01:
		offset = player.global_basis.z
	var desired := player.global_position + offset.normalized() * follow_distance
	_navigation_target_position = desired
	_navigation_active = _actor.global_position.distance_to(desired) > arrival_distance
	if _navigation_agent != null:
		_navigation_agent.target_position = desired

func _finish_navigation() -> void:
	var finished_action := _pending_arrival_action
	var finished_marker_path := _navigation_target_marker_path
	_stop_navigation(false)
	if _pending_seat_marker_after_approach_path != NodePath():
		_start_seat_exact_navigation_after_approach()
		return
	if finished_action != &"":
		_request_body_action(finished_action)
	else:
		_request_body_action(stop_action)
	_update_seat_state_after_arrival(finished_action, finished_marker_path)
	_pending_arrival_action = &""
	navigation_finished.emit(finished_action)

func _bind_navigation_motor_signals() -> void:
	if _navigation_motor == null:
		return
	var finished_cb := Callable(self, "_on_motor_navigation_finished")
	if _navigation_motor.has_signal("navigation_finished") and not _navigation_motor.is_connected("navigation_finished", finished_cb):
		_navigation_motor.connect("navigation_finished", finished_cb)
	var cancelled_cb := Callable(self, "_on_motor_navigation_cancelled")
	if _navigation_motor.has_signal("navigation_cancelled") and not _navigation_motor.is_connected("navigation_cancelled", cancelled_cb):
		_navigation_motor.connect("navigation_cancelled", cancelled_cb)

func _on_motor_navigation_finished(finished_action: StringName = &"") -> void:
	var finished_marker_path := _navigation_target_marker_path
	_navigation_active = false
	_follow_active = false
	_navigation_target_marker_path = NodePath()
	_moving_action = &""
	_pending_arrival_action = &""
	if _navigation_motor != null and _navigation_motor.has_method("stop_navigation"):
		_navigation_motor.call("stop_navigation", false)
	if _seat_exact_navigation_active:
		_seat_exact_navigation_active = false
		_start_seat_after_approach()
		return
	if _pending_seat_marker_after_approach_path != NodePath():
		_start_seat_exact_navigation_after_approach()
		return
	_update_seat_state_after_arrival(finished_action, finished_marker_path)
	navigation_finished.emit(finished_action)

func _on_motor_navigation_cancelled() -> void:
	_navigation_active = false
	_follow_active = false
	_seat_alignment_active = false
	_seat_exact_navigation_active = false
	_stand_transition_active = false
	_seat_alignment_serial += 1
	_navigation_target_marker_path = NodePath()
	_moving_action = &""
	navigation_cancelled.emit()

func _stop_navigation(play_stop: bool = true) -> void:
	if play_stop:
		_queued_navigation_after_stand = {}
	if _navigation_motor != null and _navigation_motor.has_method("stop_navigation") and bool(_navigation_motor.call("is_navigating") if _navigation_motor.has_method("is_navigating") else true):
		_navigation_motor.call("stop_navigation", play_stop)
	_navigation_active = false
	_follow_active = false
	_seat_alignment_active = false
	_seat_exact_navigation_active = false
	_stand_transition_active = false
	_seat_alignment_serial += 1
	_navigation_target_marker_path = NodePath()
	_moving_action = &""
	if play_stop:
		_pending_sit_marker_path = NodePath()
		_pending_seat_marker_after_approach_path = NodePath()
		_pending_seat_action_after_approach = &""
	if _actor != null:
		_actor.velocity.x = 0.0
		_actor.velocity.z = 0.0
	if play_stop:
		_request_body_action(stop_action)
		navigation_cancelled.emit()

func _face_player() -> void:
	var player := _find_player()
	if player == null or _actor == null:
		return
	_face_player_hold_left = maxf(_face_player_hold_left, look_at_player_face_hold_sec)
	if _navigation_motor != null and _navigation_motor.has_method("request_turn_toward_position"):
		if bool(_navigation_motor.call("request_turn_toward_position", player.global_position)):
			return
	_smooth_face_player(0.12)

func _smooth_face_player(delta: float) -> void:
	var player := _find_player()
	if player == null or _actor == null:
		return
	var direction := player.global_position - _actor.global_position
	direction.y = 0.0
	if direction.length() < 0.01:
		return
	_face_direction(direction.normalized(), delta)

func _face_direction(direction: Vector3, delta: float) -> void:
	if _actor == null or direction.length() < 0.01:
		return
	if _navigation_motor != null and _navigation_motor.has_method("face_direction"):
		_navigation_motor.call("face_direction", direction, delta)
		return
	var target_basis := Basis.looking_at(direction.normalized(), Vector3.UP)
	var amount := clampf(delta * turn_lerp_speed, 0.0, 1.0)
	_actor.global_basis = _actor.global_basis.orthonormalized().slerp(target_basis, amount).orthonormalized()

func _normalize_ai_payload(ai_data: Dictionary) -> Dictionary:
	var out := ai_data.duplicate(true)
	var command_payload_value: Variant = out.get("command_payload", {})
	if command_payload_value is Dictionary:
		var command_payload := command_payload_value as Dictionary
		for key in command_payload.keys():
			if not out.has(key) or String(out.get(key, "")).strip_edges().is_empty():
				out[key] = command_payload[key]
		if String(out.get("command", "")).strip_edges().is_empty():
			var nested_command := String(command_payload.get("command", command_payload.get("intent", ""))).strip_edges()
			if not nested_command.is_empty():
				out["command"] = nested_command
		if String(out.get("target_object", "")).strip_edges().is_empty():
			var nested_target := String(command_payload.get("target_object", command_payload.get("target_ref", ""))).strip_edges()
			if not nested_target.is_empty():
				out["target_object"] = nested_target
		if String(out.get("target_nav_point", "")).strip_edges().is_empty():
			var nested_point := String(command_payload.get("target_nav_point", command_payload.get("nav_point", command_payload.get("point_id", "")))).strip_edges()
			if not nested_point.is_empty():
				out["target_nav_point"] = nested_point
		if String(out.get("marker_role", "")).strip_edges().is_empty():
			var nested_role := String(command_payload.get("marker_role", command_payload.get("role", ""))).strip_edges()
			if not nested_role.is_empty():
				out["marker_role"] = nested_role
		if String(out.get("target_marker_path", "")).strip_edges().is_empty():
			var nested_marker_path := String(command_payload.get("target_marker_path", command_payload.get("marker_path", ""))).strip_edges()
			if not nested_marker_path.is_empty():
				out["target_marker_path"] = nested_marker_path
	for nested_key in ["face", "facial", "mouth", "lip_sync", "lipsync"]:
		var nested_face: Variant = out.get(nested_key, {})
		if nested_face is Dictionary:
			if String(out.get("expression", "")).strip_edges().is_empty():
				var nested_expression := String((nested_face as Dictionary).get("expression", (nested_face as Dictionary).get("emotion", ""))).strip_edges()
				if not nested_expression.is_empty():
					out["expression"] = nested_expression
			if String(out.get("visemes", out.get("viseme_sequence", ""))).strip_edges().is_empty():
				var nested_visemes: Variant = (nested_face as Dictionary).get("visemes", (nested_face as Dictionary).get("viseme_sequence", ""))
				if nested_visemes is Array:
					out["visemes"] = "、".join(_to_string_array(nested_visemes))
				else:
					var nested_viseme_text := String(nested_visemes).strip_edges()
					if not nested_viseme_text.is_empty():
						out["visemes"] = nested_viseme_text
	return out

func _interpret_payload(payload: Dictionary) -> Dictionary:
	if _intent_interpreter != null and _intent_interpreter.has_method("interpret_payload"):
		return _intent_interpreter.call("interpret_payload", payload) as Dictionary
	var command := String(payload.get("command", payload.get("intent", ""))).strip_edges()
	if command.is_empty():
		var nested_payload: Variant = payload.get("command_payload", {})
		if nested_payload is Dictionary:
			command = String((nested_payload as Dictionary).get("command", (nested_payload as Dictionary).get("intent", ""))).strip_edges()
	if command.is_empty():
		return {"ok": false, "intent": "", "error": "no_command"}
	return {
		"ok": true,
		"intent": command,
		"target_ref": String(payload.get("target_object", payload.get("target_ref", ""))).strip_edges(),
		"target_nav_point": String(payload.get("target_nav_point", payload.get("nav_point", payload.get("point_id", "")))).strip_edges(),
		"marker_role": String(payload.get("marker_role", "approach")).strip_edges(),
		"action": String(payload.get("action", "")).strip_edges(),
		"raw": payload.duplicate(true),
	}

func _extract_body_action(payload: Dictionary) -> StringName:
	var action_text := String(payload.get("body_action", payload.get("action", ""))).strip_edges()
	if action_text.is_empty():
		return &""
	var lowered := action_text.to_lower()
	if lowered == "idle":
		return default_idle_action
	if lowered == "talk":
		return default_talk_action
	if lowered in ["none", "noop", "no_action"]:
		return &""
	return StringName(action_text)

func _request_body_action(action_name: StringName) -> bool:
	if action_name == &"":
		return false
	if _animation_behavior == null or not _animation_behavior.has_method("request_action"):
		_log("body action skipped, animation behavior missing: %s" % String(action_name))
		return false
	var ok := false
	if _animation_behavior.has_method("request_state"):
		ok = bool(_animation_behavior.call("request_state", action_name))
	if not ok:
		ok = bool(_animation_behavior.call("request_action", action_name))
	_log("body action %s ok=%s" % [String(action_name), str(ok)])
	return ok

func _apply_face_payload(payload: Dictionary, report: Dictionary) -> void:
	if _face_component == null:
		return
	var expression := String(payload.get("expression", "")).strip_edges()
	if expression.is_empty():
		expression = _expression_from_emotion(String(payload.get("emotion", "")).strip_edges())
	if not expression.is_empty() and _face_component.has_method("set_face_expression"):
		report["expression_applied"] = bool(_face_component.call("set_face_expression", StringName(expression)))

	var viseme_text := String(payload.get("visemes", payload.get("viseme_sequence", ""))).strip_edges()
	if not viseme_text.is_empty():
		if _face_component.has_method("play_external_visemes"):
			report["viseme_applied"] = bool(_face_component.call("play_external_visemes", viseme_text))
		elif _face_component.has_method("set_external_viseme_sequence"):
			report["viseme_applied"] = bool(_face_component.call("set_external_viseme_sequence", viseme_text))

func _expression_from_emotion(emotion: String) -> String:
	var e := emotion.to_lower()
	if e.is_empty():
		return ""
	if _contains_any(e, ["开心", "高兴", "愉快", "温和", "happy", "joy", "smile"]):
		return "joy"
	if _contains_any(e, ["有趣", "调皮", "fun"]):
		return "fun"
	if _contains_any(e, ["生气", "愤怒", "angry"]):
		return "angry"
	if _contains_any(e, ["难过", "伤心", "疲惫", "害怕", "sad", "tired", "afraid", "fear"]):
		return "sorrow"
	if _contains_any(e, ["惊讶", "疑惑", "困惑", "surprised", "confused"]):
		return "surprised"
	return "neutral"

func _choose_body_action_for_target(report: Dictionary, intent: Dictionary) -> StringName:
	var role := String(intent.get("marker_role", report.get("marker_role", "approach"))).strip_edges().to_lower()
	var object_type := String(report.get("target_object_type", "")).strip_edges().to_lower()
	var tags := _to_string_array(report.get("target_object_tags", []))
	var tag_text := ",".join(tags).to_lower()
	if role == "sit" or object_type == "seat" or _has_tag(tags, "seat"):
		return &"sit_down"
	if object_type == "food" or _has_tag(tags, "food"):
		return &"work_count_supplies"
	if object_type == "medical" or _has_tag(tags, "medical"):
		return &"work_check_shelf"
	if object_type == "weapon" or _has_tag(tags, "weapon") or _has_tag(tags, "equipment"):
		return &"work_inspect_cabinet"
	if object_type == "tool" or _has_tag(tags, "tool") or _has_tag(tags, "material") or _has_tag(tags, "utility"):
		return &"work_check_lower"
	if object_type == "storage" or _has_tag(tags, "storage") or tag_text.find("cabinet") >= 0 or role == "open":
		return &"work_inspect_cabinet"
	if object_type == "table" or _has_tag(tags, "table") or _has_tag(tags, "social"):
		return &"look_around"
	return StringName(String(intent.get("action", "")).strip_edges())

func _find_world_object(target_ref: String) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for candidate in tree.get_nodes_in_group(world_object_group):
		var node := candidate as Node
		if node == null or not is_instance_valid(node):
			continue
		if _get_world_object_id(node) == target_ref:
			return node
		if String(node.name) == target_ref:
			return node
	return null

func _find_ai_nav_point(target_ref: String) -> Marker3D:
	var tree := get_tree()
	if tree == null:
		return null
	for candidate in tree.get_nodes_in_group(ai_nav_point_group):
		var node := candidate as Node
		if node == null or not is_instance_valid(node):
			continue
		var id := ""
		if node.has_method("build_ai_nav_point_summary"):
			var value: Variant = node.call("build_ai_nav_point_summary", _actor)
			if value is Dictionary:
				id = String((value as Dictionary).get("id", "")).strip_edges()
		if id.is_empty():
			id = String(_safe_get(node, "point_id", "")).strip_edges()
		if id == target_ref or String(node.name) == target_ref:
			return node as Marker3D
	return null

func _find_pickable_item(target_ref: String) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for group_name in [&"ai_pickable_item", world_object_group]:
		for candidate in tree.get_nodes_in_group(group_name):
			var node := candidate as Node
			if node == null or not is_instance_valid(node):
				continue
			if _node_matches_pickable_ref(node, target_ref):
				return node
			var parent := node.get_parent()
			if parent != null and _node_matches_pickable_ref(parent, target_ref):
				return node
	return null

func _node_matches_pickable_ref(node: Node, target_ref: String) -> bool:
	if String(node.name) == target_ref or (node.is_inside_tree() and String(node.get_path()) == target_ref):
		return true
	if node.has_method("build_ai_pickable_summary"):
		var summary_value: Variant = node.call("build_ai_pickable_summary", _actor)
		if summary_value is Dictionary:
			var summary := summary_value as Dictionary
			if String(summary.get("id", "")).strip_edges() == target_ref:
				return true
			if String(summary.get("path", "")).strip_edges() == target_ref:
				return true
	if node.has_method("build_ai_object_summary"):
		var object_summary: Variant = node.call("build_ai_object_summary", _actor)
		if object_summary is Dictionary:
			if String((object_summary as Dictionary).get("id", "")).strip_edges() == target_ref:
				return true
	return false

func _get_marker_from_path(path_text: String) -> Marker3D:
	var clean := path_text.strip_edges()
	if clean.is_empty():
		return null
	var marker := get_node_or_null(NodePath(clean)) as Marker3D
	if marker != null:
		return marker
	var tree := get_tree()
	if tree != null:
		if clean.begins_with("/"):
			marker = tree.root.get_node_or_null(NodePath(clean)) as Marker3D
		elif tree.current_scene != null:
			marker = tree.current_scene.get_node_or_null(NodePath(clean)) as Marker3D
	return marker

func _is_sit_action(action: StringName) -> bool:
	var text := String(action).strip_edges().to_lower()
	return text in ["sit", "sit_down", "sittingidle", "sitting_idle", "seated_idle", "seated_sleepy"]

func _clear_active_sit_marker() -> void:
	if _active_sit_marker_path != NodePath():
		_set_marker_seat_occupied_state(_get_marker_from_path(String(_active_sit_marker_path)), false)
	_active_sit_marker_path = NodePath()
	_active_stand_marker_path = NodePath()
	_pending_sit_marker_path = NodePath()
	_pending_seat_marker_after_approach_path = NodePath()
	_pending_seat_action_after_approach = &""

func _update_seat_state_after_arrival(finished_action: StringName, fallback_marker_path: NodePath) -> void:
	if _is_sit_action(finished_action):
		_active_sit_marker_path = _pending_sit_marker_path if _pending_sit_marker_path != NodePath() else fallback_marker_path
		_set_marker_seat_occupied_state(_get_marker_from_path(String(_active_sit_marker_path)), true)
	elif String(finished_action).strip_edges().to_lower() in ["stand", "stand_up", "idle", "idle_normal"]:
		_clear_active_sit_marker()

func _start_stand_up_from_active_seat(stand_marker_path: NodePath = NodePath()) -> void:
	if _stand_transition_active:
		return
	_stop_navigation(false)
	_stand_relocate_serial += 1
	var serial := _stand_relocate_serial
	_stand_transition_active = true
	var seat_path := _active_sit_marker_path
	var resolved_stand_path := stand_marker_path
	if resolved_stand_path == NodePath():
		resolved_stand_path = _active_stand_marker_path
	if resolved_stand_path == NodePath() and seat_path != NodePath():
		var seat_marker := _get_marker_from_path(String(seat_path))
		var stand_marker := _resolve_stand_marker_for_seat(seat_marker)
		if stand_marker != null:
			resolved_stand_path = stand_marker.get_path()
			_active_stand_marker_path = resolved_stand_path
	var ok := _request_body_action(&"stand_up")
	_log("stand up requested ok=%s seat=%s stand=%s" % [str(ok), String(seat_path), String(resolved_stand_path)])
	call_deferred("_finish_stand_up_after_root_motion", resolved_stand_path, seat_path, serial)

func _finish_stand_up_after_root_motion(stand_marker_path: NodePath, seat_marker_path: NodePath, serial: int) -> void:
	var tree := get_tree()
	var wait_time := _resolve_stand_root_motion_wait_time()
	if tree != null and wait_time > 0.0:
		await tree.create_timer(wait_time).timeout
	if serial != _stand_relocate_serial:
		return
	_refresh_refs()
	var stand_marker := _get_marker_from_path(String(stand_marker_path))
	if stand_marker != null and stand_align_after_root_motion:
		var relocated := await _relocate_actor_to_stand_marker(stand_marker)
		if not relocated:
			_log("stand relocate skipped: %s" % String(stand_marker_path))
	_set_marker_seat_occupied_state(_get_marker_from_path(String(seat_marker_path)), false)
	_active_sit_marker_path = NodePath()
	_active_stand_marker_path = NodePath()
	_pending_sit_marker_path = NodePath()
	_request_body_action(default_idle_action)
	if _navigation_motor != null and _navigation_motor.has_method("reset_navigation_state"):
		_navigation_motor.call("reset_navigation_state")
	if _navigation_motor != null and _navigation_motor.has_method("suppress_next_navigation_turn_state"):
		_navigation_motor.call("suppress_next_navigation_turn_state")
	if tree != null and stand_resume_navigation_delay_sec > 0.0:
		await tree.create_timer(stand_resume_navigation_delay_sec).timeout
	if serial != _stand_relocate_serial:
		return
	_stand_transition_active = false
	stand_up_finished.emit()
	_start_queued_navigation_after_stand()

func _relocate_actor_to_stand_marker(stand_marker: Marker3D) -> bool:
	if stand_marker == null:
		return false
	if stand_preserve_yaw_after_root_motion and _navigation_motor != null and _navigation_motor.has_method("align_position_to_marker_async"):
		var ok := bool(await _navigation_motor.call("align_position_to_marker_async", stand_marker, true, stand_relocate_duration_sec))
		if ok:
			return true
	elif not stand_preserve_yaw_after_root_motion and _navigation_motor != null and _navigation_motor.has_method("align_to_marker_async"):
		var align_ok := bool(await _navigation_motor.call("align_to_marker_async", stand_marker, true, stand_relocate_duration_sec))
		if align_ok:
			return true
	if _actor == null:
		return false
	var planar := stand_marker.global_position - _actor.global_position
	planar.y = 0.0
	if stand_relocate_max_planar_distance <= 0.0 or planar.length() <= stand_relocate_max_planar_distance:
		if stand_preserve_yaw_after_root_motion:
			_snap_actor_position_to_marker(stand_marker, true)
		else:
			_snap_actor_to_marker(stand_marker, true)
		return true
	if stand_snap_after_root_motion_if_far:
		if stand_preserve_yaw_after_root_motion:
			_snap_actor_position_to_marker(stand_marker, true)
		else:
			_snap_actor_to_marker(stand_marker, true)
		return true
	return false

func _should_stand_before_navigation(arrival_action: StringName) -> bool:
	if _is_sit_action(arrival_action):
		return false
	if _active_sit_marker_path != NodePath():
		return true
	return _stand_transition_active

func _queue_navigation_after_stand(marker_path: NodePath, arrival_action: StringName) -> void:
	_queued_navigation_after_stand = {
		"marker_path": marker_path,
		"arrival_action": arrival_action,
	}
	if not _stand_transition_active:
		_start_stand_up_from_active_seat()
	_log("queued navigation after stand marker=%s arrival=%s" % [String(marker_path), String(arrival_action)])

func _start_queued_navigation_after_stand() -> void:
	if _queued_navigation_after_stand.is_empty():
		return
	var queued := _queued_navigation_after_stand.duplicate(true)
	_queued_navigation_after_stand = {}
	var marker_path: NodePath = queued.get("marker_path", NodePath()) as NodePath
	var arrival_action := StringName(String(queued.get("arrival_action", "")))
	if marker_path == NodePath():
		return
	call_deferred("_start_navigation_to_marker", marker_path, arrival_action)

func _ensure_seat_exit_completed_before_navigation(arrival_action: StringName) -> bool:
	if _is_sit_action(arrival_action):
		return true
	if _stand_transition_active:
		return false
	if _active_sit_marker_path != NodePath():
		return false
	if _active_stand_marker_path == NodePath():
		return true
	var stand_marker := _get_marker_from_path(String(_active_stand_marker_path))
	if stand_marker == null or _actor == null:
		return true
	var offset := stand_marker.global_position - _actor.global_position
	offset.y = 0.0
	return offset.length() <= maxf(0.02, stand_ready_max_planar_distance)

func _resolve_stand_root_motion_wait_time() -> float:
	var fallback := maxf(stand_root_motion_wait_sec, stand_relocate_delay_sec)
	if _animation_behavior != null and _animation_behavior.has_method("get_action_duration"):
		var duration := float(_animation_behavior.call("get_action_duration", &"stand_up", fallback))
		if duration > 0.0:
			return maxf(0.0, duration - stand_root_motion_end_margin_sec)
	return fallback

func _start_seat_after_approach() -> void:
	var seat_path := _pending_seat_marker_after_approach_path
	var sit_action := _pending_seat_action_after_approach
	_pending_seat_marker_after_approach_path = NodePath()
	_pending_seat_action_after_approach = &""
	_seat_alignment_serial += 1
	var serial := _seat_alignment_serial
	_seat_alignment_active = true
	var seat_marker := _get_marker_from_path(String(seat_path))
	if seat_marker == null:
		_request_body_action(sit_action)
		_update_seat_state_after_arrival(sit_action, seat_path)
		_seat_alignment_active = false
		navigation_finished.emit(sit_action)
		return
	if not seat_use_root_motion:
		if _navigation_motor != null and _navigation_motor.has_method("align_to_marker"):
			if _navigation_motor.has_method("align_to_marker_async"):
				await _navigation_motor.call("align_to_marker_async", seat_marker, true, -1.0, seat_force_attach_before_action)
			else:
				_navigation_motor.call("align_to_marker", seat_marker, true, -1.0, seat_force_attach_before_action)
		elif seat_snap_if_no_root_motion and _navigation_motor != null and _navigation_motor.has_method("snap_to_marker"):
			_navigation_motor.call("snap_to_marker", seat_marker, true)
		elif seat_snap_if_no_root_motion:
			_snap_actor_to_marker(seat_marker, true)
	else:
		await _pre_align_for_root_motion_seat(seat_marker)
	if serial != _seat_alignment_serial:
		return
	_request_body_action(sit_action)
	_update_seat_state_after_arrival(sit_action, seat_path)
	_seat_alignment_active = false
	navigation_finished.emit(sit_action)

func _start_seat_exact_navigation_after_approach() -> void:
	var seat_path := _pending_seat_marker_after_approach_path
	var sit_action := _pending_seat_action_after_approach
	var seat_marker := _get_marker_from_path(String(seat_path))
	if seat_marker == null:
		_start_seat_after_approach()
		return
	if _actor == null:
		_refresh_refs()
	if _actor == null:
		_start_seat_after_approach()
		return
	var delta := seat_marker.global_position - _actor.global_position
	delta.y = 0.0
	if delta.length() <= seat_exact_navigation_min_distance:
		_start_seat_after_approach()
		return
	if _navigation_motor != null and _navigation_motor.has_method("move_to_marker"):
		_seat_exact_navigation_active = true
		_navigation_target_marker_path = seat_marker.get_path()
		_pending_arrival_action = sit_action
		var moved := false
		if _navigation_motor.has_method("move_to_seat_marker_precise"):
			moved = bool(_navigation_motor.call("move_to_seat_marker_precise", seat_marker, &"", false))
		else:
			moved = bool(_navigation_motor.call("move_to_marker", seat_marker, &"", false))
		if moved:
			_log("seat exact navigation started marker=%s distance=%.2f" % [String(seat_marker.get_path()), delta.length()])
			return
	_seat_exact_navigation_active = false
	_start_seat_after_approach()

func _pre_align_for_root_motion_seat(seat_marker: Marker3D) -> void:
	if seat_marker == null or _actor == null:
		return
	var delta := seat_marker.global_position - _actor.global_position
	delta.y = 0.0
	if delta.length() > seat_pre_align_max_planar_distance:
		if _navigation_motor != null and _navigation_motor.has_method("align_yaw_to_marker_async"):
			await _navigation_motor.call("align_yaw_to_marker_async", seat_marker, seat_pre_align_duration_sec)
		else:
			_face_marker_forward(seat_marker)
		return
	if _navigation_motor != null and _navigation_motor.has_method("align_to_marker"):
		if _navigation_motor.has_method("align_to_marker_async"):
			await _navigation_motor.call("align_to_marker_async", seat_marker, true, seat_pre_align_duration_sec, seat_force_attach_before_action)
		else:
			_navigation_motor.call("align_to_marker", seat_marker, true, seat_pre_align_duration_sec, seat_force_attach_before_action)
	else:
		_snap_actor_to_marker(seat_marker, true)

func _resolve_sit_marker_for_point(marker: Marker3D) -> Marker3D:
	if marker == null:
		return null
	var linked := _linked_marker_from_nav_point(marker, "sit_marker_path")
	if linked != null:
		return linked
	var meta_value: Variant = marker.get_meta("sit_marker_path", NodePath())
	linked = _marker_from_meta_or_sibling(meta_value, marker, "Sit_Mark3D")
	if linked != null:
		return linked
	var role := _get_marker_role(marker)
	if role == "sit" or role == "seat":
		return marker
	if not require_semantic_sit_marker and _has_tag(_to_string_array(_safe_get(marker, "tags", [])), "seat"):
		return marker
	return null

func _resolve_approach_marker_for_seat(seat_marker: Marker3D) -> Marker3D:
	if seat_marker == null:
		return null
	var linked := _linked_marker_from_nav_point(seat_marker, "approach_marker_path")
	if linked != null:
		return linked
	var from_meta: Variant = seat_marker.get_meta("approach_marker_path", NodePath())
	var marker := _marker_from_meta_or_sibling(from_meta, seat_marker, "Approach_Mark3D")
	if marker == null:
		marker = _find_named_nav_point_near_seat(seat_marker, ["approach", "side", "near"])
	return marker

func _resolve_stand_marker_for_seat(seat_marker: Marker3D) -> Marker3D:
	if seat_marker == null:
		return null
	var linked := _linked_marker_from_nav_point(seat_marker, "stand_marker_path")
	if linked != null:
		return linked
	var from_meta: Variant = seat_marker.get_meta("stand_marker_path", NodePath())
	var marker := _marker_from_meta_or_sibling(from_meta, seat_marker, "Stand_Mark3D")
	if marker == null:
		marker = _find_named_nav_point_near_seat(seat_marker, ["stand", "side", "near", "approach"])
	return marker

func _marker_from_meta_or_sibling(value: Variant, base_marker: Marker3D, sibling_name: String) -> Marker3D:
	var path_text := ""
	if value is NodePath:
		path_text = String(value)
	else:
		path_text = String(value).strip_edges()
	if not path_text.is_empty():
		var by_path := base_marker.get_node_or_null(NodePath(path_text)) as Marker3D
		if by_path != null:
			return by_path
		by_path = _get_marker_from_path(path_text)
		if by_path != null:
			return by_path
	var parent := base_marker.get_parent()
	if parent != null:
		var sibling := parent.get_node_or_null(sibling_name) as Marker3D
		if sibling != null:
			return sibling
	return null

func _linked_marker_from_nav_point(marker: Marker3D, property_name: String) -> Marker3D:
	if marker == null or property_name.is_empty():
		return null
	if not property_name in marker:
		return null
	var value: Variant = marker.get(property_name)
	var path_text := String(value).strip_edges()
	if path_text.is_empty():
		return null
	var by_path := marker.get_node_or_null(NodePath(path_text)) as Marker3D
	if by_path != null:
		return by_path
	return _get_marker_from_path(path_text)

func _get_marker_role(marker: Marker3D) -> String:
	if marker == null:
		return ""
	if "marker_role" in marker:
		return String(marker.get("marker_role")).strip_edges().to_lower()
	return String(marker.get_meta("marker_role", "")).strip_edges().to_lower()

func _find_named_nav_point_near_seat(seat_marker: Marker3D, name_tokens: Array) -> Marker3D:
	if seat_marker == null:
		return null
	var seat_name := String(seat_marker.name).to_lower()
	var seat_id := ""
	if "point_id" in seat_marker:
		seat_id = String(seat_marker.get("point_id")).to_lower()
	var best: Marker3D = null
	var best_score := -INF
	for node in get_tree().get_nodes_in_group(ai_nav_point_group):
		var marker := node as Marker3D
		if marker == null or marker == seat_marker:
			continue
		var marker_name := String(marker.name).to_lower()
		var marker_id := ""
		if "point_id" in marker:
			marker_id = String(marker.get("point_id")).to_lower()
		var text := "%s %s" % [marker_name, marker_id]
		var token_match := false
		for token in name_tokens:
			if text.find(String(token).to_lower()) >= 0:
				token_match = true
				break
		if not token_match:
			continue
		var semantic_match := false
		for stem in _seat_name_stems(seat_name, seat_id):
			if not stem.is_empty() and text.find(stem) >= 0:
				semantic_match = true
				break
		if not semantic_match and marker.global_position.distance_to(seat_marker.global_position) > 2.0:
			continue
		var distance := marker.global_position.distance_to(seat_marker.global_position)
		var score := -distance
		if semantic_match:
			score += 3.0
		if best == null or score > best_score:
			best = marker
			best_score = score
	return best

func _seat_name_stems(seat_name: String, seat_id: String) -> Array[String]:
	var result: Array[String] = []
	for raw in [seat_name, seat_id]:
		var text := String(raw).to_lower()
		if text.is_empty():
			continue
		for suffix in ["seat", "sit", "bench", "chair", "point", "marker", "mark", "side", "approach", "_", "-"]:
			text = text.replace(suffix, " ")
		for part in text.split(" ", false):
			var stem := String(part).strip_edges()
			if stem.length() >= 4 and not result.has(stem):
				result.append(stem)
	return result

func _face_marker_forward(marker: Marker3D) -> void:
	if marker == null:
		return
	var forward := marker.global_basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		return
	if _navigation_motor != null and _navigation_motor.has_method("face_direction"):
		_navigation_motor.call("face_direction", forward.normalized(), 1.0)
	else:
		_face_direction(forward.normalized(), 1.0)

func _snap_actor_to_marker(marker: Marker3D, preserve_height: bool) -> void:
	if marker == null or _actor == null:
		return
	var scale := _actor.global_transform.basis.get_scale()
	var forward := marker.global_basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		forward = Vector3.FORWARD
	var basis := Basis(Vector3.UP, atan2(forward.x, forward.z)).orthonormalized().scaled(scale)
	var origin := marker.global_position
	if preserve_height:
		origin.y = _actor.global_position.y
	_actor.global_transform = Transform3D(basis, origin)
	_actor.velocity = Vector3.ZERO

func _snap_actor_position_to_marker(marker: Marker3D, preserve_height: bool) -> void:
	if marker == null or _actor == null:
		return
	var next := _actor.global_transform
	next.origin = marker.global_position
	if preserve_height:
		next.origin.y = _actor.global_position.y
	_actor.global_transform = next
	_actor.velocity = Vector3.ZERO

func _set_marker_seat_occupied_state(marker: Marker3D, occupied: bool) -> void:
	if marker == null or not is_instance_valid(marker):
		return
	marker.set_meta("xiaokong_seat_occupied", occupied)
	marker.set_meta("character_seat_occupied", occupied)
	var occupant_text := String(_actor.name) if _actor != null else ""
	marker.set_meta("xiaokong_seat_occupant", occupant_text if occupied else "")
	marker.set_meta("character_seat_occupant", occupant_text if occupied else "")

func _refresh_refs() -> void:
	_intent_interpreter = get_node_or_null(intent_interpreter_path) if intent_interpreter_path != NodePath() else null
	_animation_behavior = get_node_or_null(animation_behavior_path) if animation_behavior_path != NodePath() else null
	_face_component = get_node_or_null(face_component_path) if face_component_path != NodePath() else null
	_navigation_motor = get_node_or_null(navigation_motor_path) if navigation_motor_path != NodePath() else null
	_actor = get_node_or_null(actor_path) as CharacterBody3D if actor_path != NodePath() else null
	_navigation_agent = get_node_or_null(navigation_agent_path) as NavigationAgent3D if navigation_agent_path != NodePath() else null
	if _intent_interpreter == null:
		_intent_interpreter = _find_sibling_with_method(&"interpret_payload")
	if _animation_behavior == null:
		_animation_behavior = _find_sibling_with_method(&"request_action")
	if _face_component == null:
		_face_component = _find_sibling_with_method(&"set_face_expression")
	if _navigation_motor == null:
		_navigation_motor = _find_sibling_with_method(&"move_to_marker")
	if _actor == null:
		_actor = _find_actor_from_parent()
	if _navigation_agent == null and _actor != null:
		_navigation_agent = _actor.get_node_or_null("NavigationAgent3D") as NavigationAgent3D

func _find_sibling_with_method(method_name: StringName) -> Node:
	var parent_node := get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var node := child as Node
		if node != null and node != self and node.has_method(method_name):
			return node
	return null

func _find_actor_from_parent() -> CharacterBody3D:
	var current := get_parent()
	while current != null:
		if current is CharacterBody3D:
			return current as CharacterBody3D
		current = current.get_parent()
	return null

func _find_player() -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	for group_name in [&"Player", &"player"]:
		for entry in tree.get_nodes_in_group(group_name):
			var node := entry as Node3D
			if node != null and is_instance_valid(node):
				return node
	return null

func _get_world_object_id(node: Node) -> String:
	if node == null:
		return ""
	var value: Variant = _safe_get(node, "object_id", "")
	var clean := String(value).strip_edges()
	if not clean.is_empty():
		return clean
	return String(node.name)

func _build_world_object_summary(node: Node) -> Dictionary:
	if node != null and node.has_method("build_ai_object_summary"):
		var value: Variant = node.call("build_ai_object_summary", _actor)
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	return {}

func _safe_get(node: Object, property_name: String, fallback: Variant = null) -> Variant:
	if node == null:
		return fallback
	for info in node.get_property_list():
		if String((info as Dictionary).get("name", "")) == property_name:
			return node.get(property_name)
	return fallback


func _to_string_array(values: Variant) -> Array:
	var result: Array = []
	if values is PackedStringArray or values is Array:
		for value in values:
			var clean := String(value).strip_edges()
			if not clean.is_empty():
				result.append(clean)
	return result

func _has_tag(tags: Array, tag_name: String) -> bool:
	for tag in tags:
		if String(tag).strip_edges().to_lower() == tag_name:
			return true
	return false

func _contains_any(text: String, needles: Array) -> bool:
	for needle in needles:
		if text.find(String(needle).to_lower()) >= 0:
			return true
	return false

func _log(message: String) -> void:
	if debug_log:
		print("[CharacterAIActionExecutor] %s" % message)
