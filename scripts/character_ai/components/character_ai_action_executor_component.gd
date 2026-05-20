extends Node
class_name CharacterAIActionExecutorComponent

signal ai_response_application_started(ai_data: Dictionary)
signal ai_response_application_finished(report: Dictionary)
signal navigation_started(target_marker_path: NodePath, arrival_action: StringName)
signal navigation_finished(arrival_action: StringName)
signal navigation_cancelled()

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
@export_range(0.0, 30.0, 0.1) var turn_lerp_speed: float = 10.0
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
	if _navigation_motor != null and _navigation_motor.has_method("is_navigating"):
		return bool(_navigation_motor.call("is_navigating")) or _navigation_active or _follow_active
	return _navigation_active or _follow_active

func is_busy() -> bool:
	return is_navigating()

func stop_navigation_from_external() -> void:
	_stop_navigation(true)

func _physics_process(delta: float) -> void:
	if _navigation_motor != null and _navigation_motor.has_method("is_navigating"):
		return
	if _follow_active:
		_update_follow_target()
	if not _navigation_active:
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
	if marker == null:
		report["errors"].append("target_marker_not_found")
		return
	report["ok"] = true
	report["target_object_id"] = _get_world_object_id(target)
	report["target_object_type"] = String(target.get("object_type")).strip_edges()
	report["target_object_tags"] = _to_string_array(target.get("tags"))
	report["target_marker_path"] = String(marker.get_path())

func _resolve_nav_point_marker(intent: Dictionary, report: Dictionary) -> void:
	var target_ref := String(intent.get("target_nav_point", intent.get("target_ref", ""))).strip_edges()
	if target_ref.is_empty():
		report["errors"].append("target_nav_point_empty")
		return
	var marker := _find_ai_nav_point(target_ref)
	if marker == null:
		report["errors"].append("target_nav_point_not_found")
		return
	report["ok"] = true
	report["target_object_id"] = target_ref
	report["target_object_type"] = String(marker.get("point_type")).strip_edges()
	report["target_object_tags"] = _to_string_array(marker.get("tags"))
	report["target_marker_path"] = String(marker.get_path())
	var action := String(intent.get("action", "")).strip_edges()
	if action.is_empty():
		action = String(marker.get("arrival_action")).strip_edges()
	report["chosen_action"] = action

func _start_navigation_to_marker(marker_path: NodePath, arrival_action: StringName) -> bool:
	_refresh_refs()
	if marker_path == NodePath():
		return false
	var marker := get_node_or_null(marker_path) as Marker3D
	if marker == null:
		var tree := get_tree()
		if tree != null and String(marker_path).begins_with("/"):
			marker = tree.root.get_node_or_null(marker_path) as Marker3D
	if marker == null:
		_log("navigation marker missing: %s" % String(marker_path))
		return false
	_pending_arrival_action = arrival_action
	_navigation_target_marker_path = marker_path
	_navigation_target_position = marker.global_position
	_navigation_active = true
	_follow_active = false
	_moving_action = &""
	if _navigation_motor != null and _navigation_motor.has_method("move_to_marker"):
		if not bool(_navigation_motor.call("move_to_marker", marker, arrival_action, false)):
			_navigation_active = false
			_navigation_target_marker_path = NodePath()
			return false
	elif _navigation_agent != null:
		_navigation_agent.target_desired_distance = arrival_distance
		_navigation_agent.path_desired_distance = maxf(0.05, arrival_distance * 0.5)
		_navigation_agent.target_position = _navigation_target_position
	_request_body_action(walk_action)
	_log("navigation started marker=%s arrival_action=%s" % [String(marker_path), String(arrival_action)])
	navigation_started.emit(marker_path, arrival_action)
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
	_stop_navigation(false)
	if _pending_arrival_action != &"":
		_request_body_action(_pending_arrival_action)
	else:
		_request_body_action(stop_action)
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
	_navigation_active = false
	_follow_active = false
	_navigation_target_marker_path = NodePath()
	_moving_action = &""
	_pending_arrival_action = &""
	navigation_finished.emit(finished_action)

func _on_motor_navigation_cancelled() -> void:
	_navigation_active = false
	_follow_active = false
	_navigation_target_marker_path = NodePath()
	_moving_action = &""
	navigation_cancelled.emit()

func _stop_navigation(play_stop: bool = true) -> void:
	if _navigation_motor != null and _navigation_motor.has_method("stop_navigation") and bool(_navigation_motor.call("is_navigating") if _navigation_motor.has_method("is_navigating") else true):
		_navigation_motor.call("stop_navigation", play_stop)
	_navigation_active = false
	_follow_active = false
	_navigation_target_marker_path = NodePath()
	_moving_action = &""
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
	if _navigation_motor != null and _navigation_motor.has_method("face_position"):
		_navigation_motor.call("face_position", player.global_position, 1.0)
		return
	var direction := player.global_position - _actor.global_position
	direction.y = 0.0
	_face_direction(direction.normalized(), 1.0)

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
	var role := String(intent.get("marker_role", "approach")).strip_edges().to_lower()
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
			id = String(node.get("point_id")).strip_edges()
		if id == target_ref or String(node.name) == target_ref:
			return node as Marker3D
	return null

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
	var value: Variant = node.get("object_id")
	var clean := String(value).strip_edges()
	if not clean.is_empty():
		return clean
	return String(node.name)


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
