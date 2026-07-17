extends Node
class_name CharacterAIActionExecutorComponent

signal ai_response_application_started(ai_data: Dictionary)
signal ai_response_application_finished(report: Dictionary)
signal navigation_started(target_marker_path: NodePath, arrival_action: StringName)
signal navigation_finished(arrival_action: StringName)
signal navigation_goal_finished(report: Dictionary)
## 带 task_id 的导航任务结束时发出；无论抵达、取消还是启动失败，后端都能收到一次真实结果。
signal navigation_goal_resolved(report: Dictionary)
signal navigation_cancelled()
signal stand_up_finished()
signal sit_down_finished()

@export var intent_interpreter_path: NodePath
@export var perception_component_path: NodePath
@export var animation_behavior_path: NodePath
@export var face_component_path: NodePath
@export var navigation_motor_path: NodePath
@export var give_item_component_path: NodePath
@export var actor_path: NodePath
@export var navigation_agent_path: NodePath
@export_range(0.8, 4.0, 0.05) var give_item_approach_distance: float = 1.8
@export var give_item_approach_run: bool = false
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
@export var dialogue_listen_action: StringName = &"listen"
@export var dialogue_seated_action: StringName = &"seated_idle"
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
## 坐下和站起都属于 root-motion 姿态过渡；坐下沿用站起的等待/收敛策略。
@export_range(0.0, 4.0, 0.01) var seat_root_motion_wait_sec: float = 1.0
@export_range(0.0, 1.0, 0.01) var seat_root_motion_end_margin_sec: float = 0.08
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
@export var preserve_navigation_during_dialogue: bool = true

var _intent_interpreter: Node
var _animation_behavior: Node
var _face_component: Node
var _navigation_motor: Node
var _give_item_component: Node
var _actor: CharacterBody3D
var _navigation_agent: NavigationAgent3D
var _navigation_active: bool = false
var _follow_active: bool = false
var _navigation_target_position: Vector3 = Vector3.ZERO
var _navigation_target_marker_path: NodePath
var _navigation_goal_context: Dictionary = {}
var _navigation_goal_result_sent: bool = false
var _pending_arrival_action: StringName = &""
var _moving_action: StringName = &""
var _pending_sit_marker_path: NodePath
var _active_sit_marker_path: NodePath
var _active_stand_marker_path: NodePath
var _pending_seat_marker_after_approach_path: NodePath
var _pending_seat_action_after_approach: StringName = &""
var _pending_give_after_navigation: Dictionary = {}
var _seat_exact_navigation_active: bool = false
var _seat_alignment_active: bool = false
var _stand_transition_active: bool = false
var _seat_alignment_serial: int = 0
var _stand_relocate_serial: int = 0
var _queued_navigation_after_stand: Dictionary = {}
var _face_player_hold_left: float = 0.0
var _carried_item: ItemData
var _carried_amount: int = 0

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
		"take_from_container":
			_resolve_object_marker(intent, report)
			if bool(report.get("ok", false)):
				report["chosen_action"] = &"work_take_item"
		"give_item_to_player":
			report["ok"] = _resolve_gift_item(intent) != null
			if report["ok"]:
				report["chosen_action"] = &"work_reach"
			else:
				report["errors"].append("gift_item_missing")
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
				"give_item_to_player":
					var give_report := _start_give_item_to_player(intent, payload)
					report["action_applied"] = bool(give_report.get("ok", false))
					report["navigation_started"] = bool(give_report.get("navigation_started", false))
					report["action"] = String(intent_report.get("chosen_action", "work_reach"))
					report["intent_report"] = give_report
					ai_response_application_finished.emit(report.duplicate(true))
					return report
			var chosen := StringName(String(intent_report.get("chosen_action", "")))
			var marker_path := String(intent_report.get("target_marker_path", "")).strip_edges()
			if not marker_path.is_empty():
				report["navigation_started"] = _start_navigation_to_marker(NodePath(marker_path), chosen, payload, intent, intent_report)
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

func interrupt_for_dialogue(action: StringName = &"listen", expression: StringName = &"neutral", face_player: bool = true) -> Dictionary:
	_refresh_refs()
	var report := {
		"ok": true,
		"action_applied": false,
		"action": "",
		"expression_applied": false,
		"navigation_cancelled": false,
		"was_seated": _active_sit_marker_path != NodePath(),
	}
	var was_navigating := is_navigating()
	if not preserve_navigation_during_dialogue or not was_navigating:
		_cancel_transient_navigation_for_dialogue()
		report["navigation_cancelled"] = was_navigating
	if face_player:
		_face_player()
	if expression != &"" and _face_component != null and _face_component.has_method("set_face_expression"):
		report["expression_applied"] = bool(_face_component.call("set_face_expression", expression))
	var chosen := _resolve_dialogue_interrupt_action(action)
	# 行走中的短对话只转头回应，不覆盖 walk，也不丢掉原任务。
	report["action_applied"] = true if was_navigating and preserve_navigation_during_dialogue else _request_body_action(chosen)
	report["action"] = String(chosen)
	ai_response_application_finished.emit(report.duplicate(true))
	return report

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
		# 语义目录中的 waypoint 没有世界实体脚本；仍允许通过 target_ref 导航，
		# 但 Marker 的解析继续只发生在 Godot 内部。
		var fallback_role := String(intent.get("marker_role", "approach"))
		var fallback_affordance := String(intent.get("affordance", "")).strip_edges().to_lower()
		if String(intent.get("intent", "")).strip_edges().to_lower() == "sit_down" or fallback_affordance in ["sit", "sit_down", "seated_idle"]:
			fallback_role = "sit"
		var waypoint := _find_ai_nav_point_with_role(target_ref, fallback_role)
		if waypoint == null:
			report["errors"].append("target_object_not_found")
			return
		_target_report_from_nav_point(waypoint, target_ref, report)
		return
	var role := String(intent.get("marker_role", "approach")).strip_edges()
	var intent_name := String(intent.get("intent", "")).strip_edges().to_lower()
	var affordance := String(intent.get("affordance", "")).strip_edges().to_lower()
	if intent_name == "sit_down":
		role = "sit"
	if role.is_empty():
		role = "approach"
	if target.has_method("resolve_ai_affordance") and affordance != "" and role == "approach":
		var affordance_value: Variant = target.call("resolve_ai_affordance", affordance)
		if affordance_value is Dictionary:
			var resolved_role := String((affordance_value as Dictionary).get("marker_role", "")).strip_edges()
			if not resolved_role.is_empty():
				role = resolved_role
	var marker: Marker3D = null
	if target.has_method("get_marker_for_role"):
		marker = target.call("get_marker_for_role", role) as Marker3D
	if marker == null and target.has_method("get_nav_marker"):
		marker = target.call("get_nav_marker") as Marker3D
	if _is_sit_action(StringName(String(intent.get("action", "")))) or role.to_lower() == "sit":
		var resolved_sit_marker := _resolve_sit_marker_for_point(marker) if marker != null else null
		# 调用方已经明确指定 sit 角色时，语义物体的角色映射就是坐点。
		marker = resolved_sit_marker if resolved_sit_marker != null else (marker if role.to_lower() == "sit" else null)
	if marker == null:
		report["errors"].append("target_marker_not_found")
		return
	report["ok"] = true
	var summary := _build_world_object_summary(target)
	report["target_object_id"] = String(summary.get("id", _get_world_object_id(target)))
	report["target_object_type"] = String(summary.get("type", _safe_get(target, "object_type", ""))).strip_edges()
	report["target_object_tags"] = _to_string_array(summary.get("tags", _safe_get(target, "tags", [])))
	report["target_marker_path"] = String(marker.get_path())
	report["marker_role"] = role if role.to_lower() == "sit" else _get_marker_role(marker)

func _resolve_nav_point_marker(intent: Dictionary, report: Dictionary) -> void:
	var target_ref := String(intent.get("target_nav_point", intent.get("target_ref", intent.get("target_entity_id", "")))).strip_edges()
	if target_ref.is_empty():
		report["errors"].append("target_nav_point_empty")
		return
	var marker_role := String(intent.get("marker_role", intent.get("role", ""))).strip_edges()
	var marker := _find_ai_nav_point_with_role(target_ref, marker_role)
	if marker == null:
		report["errors"].append("target_nav_point_not_found")
		return
	marker_role = String(_safe_get(marker, "marker_role", marker_role)).strip_edges()
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

func _start_navigation_to_marker(marker_path: NodePath, arrival_action: StringName, payload: Dictionary = {}, intent: Dictionary = {}, intent_report: Dictionary = {}) -> bool:
	_refresh_refs()
	if marker_path == NodePath():
		return false
	if auto_stand_before_navigation and _should_stand_before_navigation(arrival_action):
		_queue_navigation_after_stand(marker_path, arrival_action, payload, intent, intent_report)
		return true
	if not _ensure_seat_exit_completed_before_navigation(arrival_action):
		_queue_navigation_after_stand(marker_path, arrival_action, payload, intent, intent_report)
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
		if seat_marker == null and String(intent.get("marker_role", "")).strip_edges().to_lower() == "sit":
			seat_marker = marker
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
	_navigation_goal_context = _build_navigation_goal_context(actual_marker, actual_arrival_action, payload, intent, intent_report)
	_navigation_goal_result_sent = false
	_navigation_active = true
	_follow_active = false
	_moving_action = &""
	if _navigation_motor != null and _navigation_motor.has_method("move_to_marker"):
		if not bool(_navigation_motor.call("move_to_marker", actual_marker, actual_arrival_action, false)):
			var failed_goal_context := _navigation_goal_context.duplicate(true)
			_navigation_active = false
			_navigation_target_marker_path = NodePath()
			_navigation_goal_context = {}
			_seat_exact_navigation_active = false
			_emit_navigation_goal_resolved(failed_goal_context, "navigation_goal_start_failed", false)
			return false
	elif _navigation_agent != null:
		_navigation_agent.target_desired_distance = arrival_distance
		_navigation_agent.path_desired_distance = maxf(0.05, arrival_distance * 0.5)
		_navigation_agent.target_position = _navigation_target_position
	elif _navigation_motor != null and _navigation_motor.has_method("navigate_to"):
		if not bool(_navigation_motor.call("navigate_to", _navigation_target_position)):
			_navigation_active = false
			_navigation_target_marker_path = NodePath()
			_navigation_goal_context = {}
			_emit_navigation_goal_resolved({}, "navigation_goal_start_failed", false)
			return false
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
	var goal_context := _navigation_goal_context.duplicate(true)
	_stop_navigation(false)
	if _pending_seat_marker_after_approach_path != NodePath():
		_navigation_goal_context = goal_context
		_start_seat_exact_navigation_after_approach()
		return
	if not _pending_give_after_navigation.is_empty():
		var pending_give := _pending_give_after_navigation.duplicate(true)
		_pending_give_after_navigation.clear()
		_face_player()
		_start_give_item_to_player(
			pending_give.get("intent", {}) as Dictionary,
			pending_give.get("payload", {}) as Dictionary,
			true,
		)
		return
	_face_arrival_target(goal_context)
	if finished_action != &"":
		_request_body_action(finished_action)
	else:
		_request_body_action(stop_action)
	_complete_pickable_interaction(goal_context)
	_update_seat_state_after_arrival(finished_action, finished_marker_path)
	_pending_arrival_action = &""
	navigation_finished.emit(finished_action)
	_emit_navigation_goal_finished(finished_action, finished_marker_path, goal_context)

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
	var goal_context := _navigation_goal_context.duplicate(true)
	_navigation_active = false
	_follow_active = false
	_navigation_target_marker_path = NodePath()
	_navigation_goal_context = {}
	_moving_action = &""
	_pending_arrival_action = &""
	if _navigation_motor != null and _navigation_motor.has_method("stop_navigation"):
		_navigation_motor.call("stop_navigation", false)
	if _seat_exact_navigation_active:
		_navigation_goal_context = goal_context
		_seat_exact_navigation_active = false
		_start_seat_after_approach()
		return
	if _pending_seat_marker_after_approach_path != NodePath():
		_navigation_goal_context = goal_context
		_start_seat_exact_navigation_after_approach()
		return
	if not _pending_give_after_navigation.is_empty():
		var pending_give := _pending_give_after_navigation.duplicate(true)
		_pending_give_after_navigation.clear()
		_face_player()
		_start_give_item_to_player(
			pending_give.get("intent", {}) as Dictionary,
			pending_give.get("payload", {}) as Dictionary,
			true,
		)
		return
	_face_arrival_target(goal_context)
	_update_seat_state_after_arrival(finished_action, finished_marker_path)
	_complete_pickable_interaction(goal_context)
	navigation_finished.emit(finished_action)
	_emit_navigation_goal_finished(finished_action, finished_marker_path, goal_context)

func _on_motor_navigation_cancelled() -> void:
	var goal_context := _navigation_goal_context.duplicate(true)
	_pending_give_after_navigation.clear()
	_navigation_active = false
	_follow_active = false
	_navigation_goal_context = {}
	_seat_alignment_active = false
	_seat_exact_navigation_active = false
	_stand_transition_active = false
	_seat_alignment_serial += 1
	_navigation_target_marker_path = NodePath()
	_moving_action = &""
	_emit_navigation_goal_resolved(goal_context, "navigation_goal_cancelled", false)
	navigation_cancelled.emit()

## 导航抵达后才操作物品，避免角色在远处就把世界物体拿走。
func _complete_pickable_interaction(goal_context: Dictionary) -> void:
	var intent: Variant = goal_context.get("intent", {})
	if intent is not Dictionary:
		return
	var intent_name := String((intent as Dictionary).get("intent", "")).strip_edges()
	if intent_name == "take_from_container":
		_complete_container_take(intent as Dictionary, goal_context)
		return
	if intent_name not in ["pick_up_item", "use_item", "eat_item"]:
		return
	var target_ref := String((intent as Dictionary).get("target_ref", "")).strip_edges()
	var target := _find_pickable_item(target_ref)
	if target == null or not target.has_method("pick_up_by"):
		_log("pickable interaction target missing: %s" % target_ref)
		goal_context["action_result"] = {"ok": false, "error": "pickable_interaction_target_missing", "target_ref": target_ref, "interaction": intent_name}
		return
	# use/eat 不再把“拿起+消耗”塞进一个异步 call：先拿到手上，再短暂停顿后喝/吃。
	# 这样 Mirdo 的动作顺序是：导航到水边 -> 拿起水 -> 喝水，而不是原地瞬间消耗。
	var pick_result: Variant = target.call("pick_up_by", _actor, "ai_%s" % intent_name, false)
	var pick_report := pick_result as Dictionary if pick_result is Dictionary else {"ok": true, "started": true}
	goal_context["action_result"] = {
		"ok": bool(pick_report.get("ok", true)),
		"interaction": intent_name,
		"target_ref": target_ref,
		"pick_result": pick_report.duplicate(true),
		"consume_scheduled": intent_name != "pick_up_item",
	}
	if intent_name != "pick_up_item" and bool(pick_report.get("ok", true)):
		_consume_pickable_after_arrival(target, intent_name, target_ref)

func _consume_pickable_after_arrival(target: Node, intent_name: String, target_ref: String) -> void:
	# 等拿起动画/手部模型稍微就位后再消耗，让玩家能看到“拿水→喝水”的因果。
	if is_inside_tree():
		await get_tree().create_timer(0.35).timeout
	if target == null or not is_instance_valid(target) or not target.has_method("use_by"):
		_log("consume skipped, target invalid: %s" % target_ref)
		return
	var consume_result: Variant = target.call("use_by", _actor, "ai_%s" % intent_name)
	_log("pickable consumed target=%s intent=%s result=%s" % [target_ref, intent_name, str(consume_result)])

func _build_navigation_goal_context(marker: Marker3D, arrival_action: StringName, payload: Dictionary, intent: Dictionary, intent_report: Dictionary) -> Dictionary:
	var action_step_value: Variant = payload.get("action_step", {})
	var action_line_value: Variant = payload.get("action_line", [])
	var context := {
		"arrival_action": String(arrival_action),
		"target_marker_path": String(marker.get_path()) if marker != null else "",
		"target_marker_name": String(marker.name) if marker != null else "",
		"payload": payload.duplicate(true),
		"intent": intent.duplicate(true),
		"intent_report": intent_report.duplicate(true),
		"target_object": String(intent.get("target_ref", intent_report.get("target_object_id", payload.get("target_object", "")))).strip_edges(),
		"target_nav_point": String(intent.get("target_nav_point", payload.get("target_nav_point", ""))).strip_edges(),
		"task_id": String(payload.get("task_id", "")).strip_edges(),
		"marker_role": String(intent.get("marker_role", payload.get("marker_role", ""))).strip_edges(),
		"chain_id": String(payload.get("chain_id", "")).strip_edges(),
		"chain_depth": int(payload.get("chain_depth", 0)),
		"current_step_id": String(payload.get("current_step_id", "")).strip_edges(),
		"action_step": (action_step_value as Dictionary).duplicate(true) if action_step_value is Dictionary else {},
		"action_line": (action_line_value as Array).duplicate(true) if action_line_value is Array else [],
		"action_hint": "",
		"target_description": "",
		"target_name": "",
	}
	if marker != null and marker.has_method("build_ai_nav_point_summary"):
		var summary_value: Variant = marker.call("build_ai_nav_point_summary", _actor)
		if summary_value is Dictionary:
			var summary := summary_value as Dictionary
			context["nav_point_summary"] = summary.duplicate(true)
			context["target_nav_point"] = String(summary.get("id", context.get("target_nav_point", ""))).strip_edges()
			context["target_name"] = String(summary.get("name", "")).strip_edges()
			context["target_description"] = String(summary.get("description", "")).strip_edges()
			context["action_hint"] = String(summary.get("action_hint", "")).strip_edges()
			if context["marker_role"].is_empty():
				context["marker_role"] = String(summary.get("marker_role", "")).strip_edges()
			if context["arrival_action"].is_empty():
				context["arrival_action"] = String(summary.get("arrival_action", "")).strip_edges()
			if String(context.get("target_object", "")).is_empty():
				context["target_object"] = String(summary.get("target_object_id", "")).strip_edges()
	var semantic_target := _find_world_object(String(context.get("target_object", "")).strip_edges())
	if semantic_target != null and semantic_target.has_method("build_ai_entity_summary"):
		var entity_value: Variant = semantic_target.call("build_ai_entity_summary", _actor)
		if entity_value is Dictionary:
			var entity := entity_value as Dictionary
			context["target_name"] = String(entity.get("name", context.get("target_name", ""))).strip_edges()
			context["target_description"] = String(entity.get("description", context.get("target_description", ""))).strip_edges()
	if String(context.get("target_name", "")).is_empty():
		context["target_name"] = String(payload.get("target_name", payload.get("target", ""))).strip_edges()
	if String(context.get("target_description", "")).is_empty():
		context["target_description"] = String(payload.get("target_description", "")).strip_edges()
	return context

func _emit_navigation_goal_finished(finished_action: StringName, finished_marker_path: NodePath, goal_context: Dictionary = {}) -> void:
	var report := goal_context.duplicate(true)
	report["ok"] = true
	report["arrival_action"] = String(finished_action)
	report["finished_marker_path"] = String(finished_marker_path)
	report["event"] = "navigation_goal_finished"
	navigation_goal_finished.emit(report)
	_emit_navigation_goal_resolved(report, "navigation_goal_finished", true)

## 只同步带 task_id 的模型任务，避免把本地漫游也误报给正在等待结果的后端。
func _emit_navigation_goal_resolved(goal_context: Dictionary, event: String, ok: bool) -> void:
	if _navigation_goal_result_sent:
		return
	if String(goal_context.get("task_id", "")).strip_edges().is_empty():
		return
	_navigation_goal_result_sent = true
	var report := goal_context.duplicate(true)
	report["event"] = event
	report["ok"] = ok
	navigation_goal_resolved.emit(report)

func _stop_navigation(play_stop: bool = true) -> void:
	var goal_context := _navigation_goal_context.duplicate(true)
	if play_stop:
		_queued_navigation_after_stand = {}
	if _navigation_motor != null and _navigation_motor.has_method("stop_navigation") and bool(_navigation_motor.call("is_navigating") if _navigation_motor.has_method("is_navigating") else true):
		_navigation_motor.call("stop_navigation", play_stop)
	_navigation_active = false
	_follow_active = false
	if play_stop:
		_navigation_goal_context = {}
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
		_emit_navigation_goal_resolved(goal_context, "navigation_goal_cancelled", false)
		navigation_cancelled.emit()

func _cancel_transient_navigation_for_dialogue() -> void:
	var goal_context := _navigation_goal_context.duplicate(true)
	_queued_navigation_after_stand = {}
	_pending_sit_marker_path = NodePath()
	_pending_seat_marker_after_approach_path = NodePath()
	_pending_seat_action_after_approach = &""
	_navigation_target_marker_path = NodePath()
	_navigation_goal_context = {}
	_pending_arrival_action = &""
	_moving_action = &""
	_navigation_active = false
	_follow_active = false
	_seat_alignment_active = false
	_seat_exact_navigation_active = false
	_seat_alignment_serial += 1
	if _actor != null:
		_actor.velocity.x = 0.0
		_actor.velocity.z = 0.0
	if _navigation_motor != null:
		if _navigation_motor.has_method("stop_navigation") and bool(_navigation_motor.call("is_navigating") if _navigation_motor.has_method("is_navigating") else true):
			_navigation_motor.call("stop_navigation", false)
		if _navigation_motor.has_method("reset_navigation_state"):
			_navigation_motor.call("reset_navigation_state")
	_emit_navigation_goal_resolved(goal_context, "navigation_goal_cancelled", false)
	navigation_cancelled.emit()

func _resolve_dialogue_interrupt_action(requested: StringName) -> StringName:
	if _active_sit_marker_path != NodePath():
		if requested != &"" and _is_sit_action(requested):
			return requested
		return dialogue_seated_action
	if requested == &"":
		return dialogue_listen_action
	return requested

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
	# 新协议只接受 action_line；旧的顶层 command 不再进入执行器。
	out.erase("command")
	out.erase("command_payload")
	out.erase("intent")
	var action_line_value: Variant = out.get("action_line", [])
	if action_line_value is Array and not (action_line_value as Array).is_empty():
		var action_line := action_line_value as Array
		var current_step_id := String(out.get("current_step_id", "")).strip_edges()
		var step: Dictionary = {}
		for candidate in action_line:
			if not candidate is Dictionary:
				continue
			var candidate_dict := candidate as Dictionary
			if current_step_id.is_empty() or String(candidate_dict.get("step_id", "")).strip_edges() == current_step_id:
				step = candidate_dict.duplicate(true)
				break
		if not step.is_empty():
			current_step_id = String(step.get("step_id", current_step_id)).strip_edges()
			out["current_step_id"] = current_step_id
			out["action_step"] = step.duplicate(true)
			var step_payload_value: Variant = step.get("command_payload", {})
			var step_payload: Dictionary = step_payload_value.duplicate(true) if step_payload_value is Dictionary else {}
			# 执行器内部统一读取当前步骤；对外协议仍只有 action_line。
			out["command"] = String(step.get("command", "")).strip_edges()
			out["command_payload"] = step_payload
			for key in step_payload.keys():
				# 当前步骤是执行真相，不能用顶层同名字段覆盖它；也避免把 Dictionary/Array
				# 强制转 String 造成运行时错误。
				out[key] = step_payload[key]
			for key in ["action", "reason", "expected_result", "success_next_step", "failure_next_step", "status"]:
				if not step.has(key):
					continue
				if key == "action" and String(step.get(key, "")).strip_edges().is_empty():
					continue
				out[key] = step[key]
		else:
			out["command"] = ""
			out["command_payload"] = {}
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
		"item_id": String(payload.get("item_id", payload.get("item", payload.get("given_item", "")))).strip_edges(),
		"item_path": String(payload.get("item_path", payload.get("item_resource", payload.get("resource_path", "")))).strip_edges(),
		"amount": int(payload.get("amount", payload.get("count", 1))),
		"raw": payload.duplicate(true),
	}

func _start_give_item_to_player(intent: Dictionary, payload: Dictionary, skip_approach: bool = false) -> Dictionary:
	_refresh_refs()
	if _give_item_component == null or not _give_item_component.has_method("offer_item_to_player"):
		return {"ok": false, "error": "give_item_component_missing"}
	var item := _resolve_gift_item(intent)
	if item == null:
		return {"ok": false, "error": "gift_item_missing"}
	var options := {
		"amount": maxi(1, _carried_amount if _carried_item != null else int(intent.get("amount", payload.get("amount", 1)))),
		"action": String(payload.get("action", "work_reach")),
		"expression": String(payload.get("expression", "face_fun")),
	}
	var line := String(payload.get("dialogue", payload.get("line", ""))).strip_edges()
	if not line.is_empty():
		options["line"] = line
	if payload.has("timeout_sec"):
		options["timeout_sec"] = float(payload.get("timeout_sec", 10.0))
	var player := _find_player()
	if player == null:
		return {"ok": false, "error": "player_missing"}
	if not skip_approach and _actor is Node3D and _navigation_motor != null and _navigation_motor.has_method("move_to_position"):
		var distance := (_actor as Node3D).global_position.distance_to(player.global_position)
		if distance > give_item_approach_distance:
			_pending_give_after_navigation = {
				"intent": intent.duplicate(true),
				"payload": payload.duplicate(true),
			}
			_navigation_active = true
			_follow_active = false
			_navigation_target_position = player.global_position
			_navigation_target_marker_path = NodePath()
			_navigation_goal_result_sent = false
			_pending_arrival_action = &"give_item_to_player"
			_navigation_goal_context = {
				"task_id": String(payload.get("task_id", "")).strip_edges(),
				"current_step_id": String(payload.get("current_step_id", "")).strip_edges(),
				"intent": intent.duplicate(true),
				"payload": payload.duplicate(true),
				"target_object": "player",
				"target_name": "老师",
				"arrival_action": "give_item_to_player",
			}
			var started := bool(_navigation_motor.call(
				"move_to_position",
				player.global_position,
				&"give_item_to_player",
				NodePath(),
				give_item_approach_run,
			))
			if not started:
				_pending_give_after_navigation.clear()
				_navigation_active = false
				return {"ok": false, "error": "give_navigation_start_failed"}
			return {
				"ok": true,
				"navigation_started": true,
				"awaiting": "give_item_to_player",
				"target": "player",
				"distance": distance,
			}
	var result: Dictionary = _give_item_component.call("offer_item_to_player", item, player, options)
	if bool(result.get("ok", false)) and item == _carried_item:
		_carried_item = null
		_carried_amount = 0
	return result

func _resolve_gift_item(intent: Dictionary) -> ItemData:
	if _carried_item != null:
		return _carried_item
	var item_path := String(intent.get("item_path", "")).strip_edges()
	if item_path.is_empty():
		var raw: Variant = intent.get("raw", {})
		if raw is Dictionary:
			item_path = String((raw as Dictionary).get("item_path", (raw as Dictionary).get("item_resource", ""))).strip_edges()
	if not item_path.is_empty():
		var by_path := load(item_path) as ItemData
		if by_path != null:
			return by_path
	var item_id := String(intent.get("item_id", "")).strip_edges().to_lower()
	if item_id.is_empty():
		var raw_value: Variant = intent.get("raw", {})
		if raw_value is Dictionary:
			item_id = String((raw_value as Dictionary).get("item_id", (raw_value as Dictionary).get("item", (raw_value as Dictionary).get("given_item", "")))).strip_edges().to_lower()
	match item_id:
		"bandage", "绷带", "bandage_item":
			return load("res://resources/items/bandage.tres") as ItemData
		"medkit", "medical_kit", "first_aid", "first_aid_kit", "急救箱", "医疗包", "急救包":
			return load("res://resources/items/medkit.tres") as ItemData
		"water", "water_bottle", "水", "水瓶":
			return load("res://resources/items/water_bottle.tres") as ItemData
	return null

## 抵达容器后才减少库存，并把取出的 ItemData 保存到角色手中，供动作线下一步递给玩家。
func _complete_container_take(intent: Dictionary, goal_context: Dictionary) -> void:
	var target_ref := String(intent.get("target_ref", "")).strip_edges()
	var target := _find_world_object(target_ref)
	var inventory_node := _find_container_inventory_node(target)
	if inventory_node == null:
		goal_context["action_result"] = {"ok": false, "error": "container_inventory_missing", "target_ref": target_ref}
		return
	var result: Dictionary = inventory_node.call("take_item_for_ai", String(intent.get("item_id", "")), maxi(1, int(intent.get("amount", 1))))
	if bool(result.get("ok", false)):
		_carried_item = result.get("item", null) as ItemData
		_carried_amount = int(result.get("amount", 1))
	goal_context["action_result"] = result


func _find_container_inventory_node(root: Node) -> Node:
	if root == null:
		return null
	if root.has_method("take_item_for_ai"):
		return root
	for child in root.get_children():
		var found := _find_container_inventory_node(child as Node)
		if found != null:
			return found
	return null


## 到达设施后面向设施本身；只有显式 look_at_player 或玩家搭话时才看玩家。
func _face_arrival_target(goal_context: Dictionary) -> void:
	if _actor == null:
		return
	var target_ref := String(goal_context.get("target_object", "")).strip_edges()
	var target := _find_world_object(target_ref) as Node3D
	if target == null:
		return
	var direction := target.global_position - _actor.global_position
	direction.y = 0.0
	if direction.length() > 0.01:
		_face_direction(direction.normalized(), 1.0)

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
	var role := String(report.get("marker_role", intent.get("marker_role", "approach"))).strip_edges().to_lower()
	var intent_name := String(intent.get("intent", "")).strip_edges().to_lower()
	var affordance := String(intent.get("affordance", "")).strip_edges().to_lower()
	if intent_name == "sit_down":
		role = "sit"
	elif String(intent.get("marker_role", "")).strip_edges().to_lower() not in ["", "approach"]:
		role = String(intent.get("marker_role", role)).strip_edges().to_lower()
	var affordance_actions := {
		"sit": &"sit_down", "sit_down": &"sit_down", "seated_idle": &"sit_down",
		"take_item": &"work_take_item", "take_from_container": &"work_take_item",
		"drink": &"work_drink", "use": &"work_reach", "inspect": &"work_inspect_cabinet",
		"open": &"work_inspect_cabinet", "check": &"work_check_shelf",
	}
	if affordance_actions.has(affordance):
		return affordance_actions[affordance]
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
		# 拾取组件挂在物品根节点下；允许用 AI 摘要 id、场景实例名或根节点路径定位，
		# 这样抵达后面向目标和拾取阶段使用的是同一个语义引用。
		if _get_world_object_id(node) == target_ref or _node_matches_pickable_ref(node, target_ref):
			return node
		var parent := node.get_parent()
		if parent != null and (_get_world_object_id(parent) == target_ref or _node_matches_pickable_ref(parent, target_ref)):
			return parent
		if String(node.name) == target_ref:
			return node
	return null

func _find_ai_nav_point(target_ref: String) -> Marker3D:
	return _find_ai_nav_point_with_role(target_ref, "")

func _find_ai_nav_point_with_role(target_ref: String, requested_role: String = "") -> Marker3D:
	var tree := get_tree()
	if tree == null:
		return null
	var fallback: Marker3D = null
	var role := requested_role.strip_edges().to_lower()
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
		var target_object_id := String(_safe_get(node, "target_object_id", "")).strip_edges()
		var matches := id == target_ref or String(node.name) == target_ref or target_object_id == target_ref
		if not matches:
			continue
		var marker := node as Marker3D
		if marker == null:
			continue
		var marker_role := String(_safe_get(marker, "marker_role", "")).strip_edges().to_lower()
		if role.is_empty() or marker_role == role:
			return marker
		if fallback == null:
			fallback = marker
	return fallback

func _target_report_from_nav_point(marker: Marker3D, target_ref: String, report: Dictionary) -> void:
	if marker == null:
		return
	report["ok"] = true
	report["target_object_id"] = target_ref
	report["target_object_type"] = String(_safe_get(marker, "point_type", "waypoint")).strip_edges()
	report["target_object_tags"] = _to_string_array(_safe_get(marker, "tags", []))
	report["target_marker_path"] = String(marker.get_path())
	report["marker_role"] = String(_safe_get(marker, "marker_role", "approach")).strip_edges()

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
	if _navigation_motor != null and _navigation_motor.has_method("snap_to_marker"):
		return bool(_navigation_motor.call("snap_to_marker", stand_marker, true))
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

func _queue_navigation_after_stand(marker_path: NodePath, arrival_action: StringName, payload: Dictionary = {}, intent: Dictionary = {}, intent_report: Dictionary = {}) -> void:
	_queued_navigation_after_stand = {
		"marker_path": marker_path,
		"arrival_action": arrival_action,
		"payload": payload.duplicate(true),
		"intent": intent.duplicate(true),
		"intent_report": intent_report.duplicate(true),
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
	var payload: Dictionary = (queued.get("payload", {}) as Dictionary).duplicate(true) if queued.get("payload", {}) is Dictionary else {}
	var intent: Dictionary = (queued.get("intent", {}) as Dictionary).duplicate(true) if queued.get("intent", {}) is Dictionary else {}
	var intent_report: Dictionary = (queued.get("intent_report", {}) as Dictionary).duplicate(true) if queued.get("intent_report", {}) is Dictionary else {}
	if marker_path == NodePath():
		return
	call_deferred("_start_navigation_to_marker", marker_path, arrival_action, payload, intent, intent_report)

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
	return _resolve_posture_action_wait_time(&"stand_up", stand_relocate_delay_sec, stand_root_motion_end_margin_sec)

## 统一解析坐下/站起的动画等待时间，避免两套姿态逻辑互相漂移。
func _resolve_posture_action_wait_time(action_name: StringName, fallback: float, end_margin: float) -> float:
	if _animation_behavior != null and _animation_behavior.has_method("get_action_duration"):
		var duration := float(_animation_behavior.call("get_action_duration", action_name, fallback))
		if duration > 0.0:
			return maxf(0.0, duration - maxf(0.0, end_margin))
	return maxf(0.0, fallback)

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
		_emit_navigation_goal_finished(sit_action, seat_path, _navigation_goal_context.duplicate(true))
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
	var requested := _request_body_action(sit_action)
	# 和站起一样，等待姿态动画的 root-motion 完成后再占用座位、通知任务完成。
	var wait_time := _resolve_posture_action_wait_time(sit_action, seat_root_motion_wait_sec, seat_root_motion_end_margin_sec)
	var tree := get_tree()
	if requested and tree != null and wait_time > 0.0:
		await tree.create_timer(wait_time).timeout
	if serial != _seat_alignment_serial:
		return
	if not requested:
		_log("sit action request failed: %s" % String(sit_action))
	_update_seat_state_after_arrival(sit_action, seat_path)
	_seat_alignment_active = false
	sit_down_finished.emit()
	navigation_finished.emit(sit_action)
	_emit_navigation_goal_finished(sit_action, seat_path, _navigation_goal_context.duplicate(true))

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
	_give_item_component = get_node_or_null(give_item_component_path) if give_item_component_path != NodePath() else null
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
	if _navigation_motor == null:
		_navigation_motor = _find_ancestor_with_method(&"navigate_to")
	if _give_item_component == null:
		_give_item_component = _find_sibling_with_method(&"offer_item_to_player")
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

func _find_ancestor_with_method(method_name: StringName) -> Node:
	var current := get_parent()
	while current != null:
		if current.has_method(method_name):
			return current
		current = current.get_parent()
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
