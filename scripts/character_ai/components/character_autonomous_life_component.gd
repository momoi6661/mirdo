extends Node
class_name CharacterAutonomousLifeComponent

## Mirdo local autonomous behaviour.
## No backend/model request. It chooses simple local goals from perception,
## moves with NavigationAgent3D, and only calls AnimationBehaviorTreeComponent
## for body animation.

signal autonomous_decision_made(decision: Dictionary)
signal autonomous_decision_skipped(reason: String)
signal autonomous_navigation_finished(decision: Dictionary)

@export var enabled: bool = true
@export var perception_component_path: NodePath
@export var planner_path: NodePath
@export var mind_state_path: NodePath
@export var animation_behavior_path: NodePath
@export var navigation_motor_path: NodePath
@export var action_executor_path: NodePath
@export var dialogue_component_path: NodePath
@export var face_component_path: NodePath
@export var actor_path: NodePath
@export var navigation_agent_path: NodePath
@export var world_object_group: StringName = &"ai_world_object"

@export_category("Self Talk")
@export var self_talk_enabled: bool = true
@export_range(0.0, 1.0, 0.01) var self_talk_chance_on_arrival: float = 0.24
@export_range(0.0, 1.0, 0.01) var self_talk_chance_on_ambient: float = 0.06
@export_range(5.0, 300.0, 1.0) var self_talk_cooldown_sec: float = 38.0
@export_range(8, 80, 1) var self_talk_max_chars: int = 24
@export var self_talk_prompt_prefix: String = "用Mirdo的口吻自言自语一句很短的话，称呼玩家为老师，不要超过24个中文字符。"

@export_category("Timing")
@export_range(0.5, 60.0, 0.1) var think_interval_min: float = 4.0
@export_range(0.5, 90.0, 0.1) var think_interval_max: float = 9.0
@export_range(0.0, 120.0, 0.1) var startup_delay_sec: float = 3.0
@export_range(0.0, 120.0, 0.1) var external_grace_sec: float = 8.0
@export_range(0.0, 120.0, 0.1) var movement_cooldown_sec: float = 6.0
@export_range(0.0, 300.0, 0.1) var same_target_cooldown_sec: float = 45.0
@export_range(0.0, 300.0, 0.1) var sit_cooldown_sec: float = 120.0
@export_range(0.0, 60.0, 0.1) var post_arrival_dwell_default_sec: float = 1.8
@export_range(0.0, 60.0, 0.1) var post_arrival_think_delay_sec: float = 2.5

@export_category("Movement")
@export_range(0.05, 2.0, 0.01) var arrival_distance: float = 0.45
@export_range(0.1, 8.0, 0.05) var walk_speed: float = 1.8
@export_range(0.1, 8.0, 0.05) var run_speed: float = 3.6
@export_range(0.0, 30.0, 0.1) var turn_lerp_speed: float = 10.0
@export_range(0.1, 30.0, 0.1) var far_distance: float = 7.0
@export_range(0.0, 1.0, 0.01) var run_when_far_chance: float = 0.08

@export_category("Decision Weights")
@export_range(0.0, 1.0, 0.01) var inspect_chance: float = 0.18
@export_range(0.0, 1.0, 0.01) var ambient_chance: float = 0.70
@export_range(0.0, 1.0, 0.01) var sit_chance: float = 0.015
@export_range(0.0, 1.0, 0.01) var look_at_player_chance: float = 0.10

@export_category("Tags")
@export var inspect_tags: PackedStringArray = PackedStringArray(["storage", "supplies", "food", "medical", "equipment", "tool", "material", "cabinet", "utility"])
@export var sit_tags: PackedStringArray = PackedStringArray(["seat", "rest", "bed"])
@export var avoid_autonomous_tags: PackedStringArray = PackedStringArray(["player", "door", "danger", "blocked"])

@export_category("Animation Actions")
@export var idle_action: StringName = &"idle_normal"
@export var walk_action: StringName = &"walk"
@export var run_action: StringName = &"run"
@export var stop_action: StringName = &"idle_normal"
@export var listen_action: StringName = &"listen"
@export var ambient_actions: PackedStringArray = PackedStringArray(["idle_fidget", "look_around", "curious_peek", "tilt_head_cute", "small_happy_bounce", "tiny_wave"])
@export var inspect_marker_role: String = "approach"
@export var sit_marker_role: String = "sit"
@export var debug_log: bool = false

var _perception_component: Node
var _planner: Node
var _mind_state: Node
var _animation_behavior: Node
var _navigation_motor: Node
var _action_executor: Node
var _dialogue_component: Node
var _face_component: Node
var _actor: CharacterBody3D
var _navigation_agent: NavigationAgent3D
var _rng := RandomNumberGenerator.new()
var _think_left := 0.0
var _external_grace_left := 0.0
var _movement_cooldown_left := 0.0
var _sit_cooldown_left := 0.0
var _target_cooldowns: Dictionary = {}
var _last_ambient_action := ""
var _navigation_active := false
var _navigation_target_position := Vector3.ZERO
var _navigation_decision: Dictionary = {}
var _arrival_action: StringName = &""
var _moving_action: StringName = &""
var _locomotion_velocity_gate_active: bool = false
var _dwell_left: float = 0.0
var _self_talk_cooldown_left: float = 0.0
var _last_decision_kind: String = ""
var _last_decision_target: String = ""
var _recent_decision_kinds: Array[String] = []

func _ready() -> void:
	_rng.randomize()
	_refresh_refs()
	_bind_navigation_motor_signals()
	_bind_external_control_signals()
	_external_grace_left = maxf(_external_grace_left, startup_delay_sec)
	_schedule_next_think()
	set_process(true)
	set_physics_process(true)

func _process(delta: float) -> void:
	_tick_timers(delta)
	if _dwell_left > 0.0:
		_dwell_left = maxf(0.0, _dwell_left - delta)
		return
	if not enabled or _navigation_active:
		return
	_think_left -= delta
	if _think_left > 0.0:
		return
	_schedule_next_think()
	_think()

func _physics_process(delta: float) -> void:
	if not _navigation_active:
		return
	if _navigation_motor != null and _navigation_motor.has_method("is_navigating"):
		if bool(_navigation_motor.call("is_navigating")):
			return
		_on_motor_navigation_finished(_arrival_action)
		return
	_update_navigation(delta)

func notify_external_control() -> void:
	_external_grace_left = external_grace_sec
	if _navigation_active:
		stop_autonomous_navigation(true)

func notify_dialogue_started() -> void:
	notify_external_control()

func notify_ai_response_applied(_ai_data: Dictionary = {}) -> void:
	notify_external_control()

func force_think_now() -> bool:
	return _think(true)

func is_navigating() -> bool:
	return _navigation_active

func stop_autonomous_navigation(play_stop: bool = true) -> void:
	if _navigation_motor != null and _navigation_motor.has_method("stop_navigation") and bool(_navigation_motor.call("is_navigating") if _navigation_motor.has_method("is_navigating") else true):
		_navigation_motor.call("stop_navigation", play_stop)
	_navigation_active = false
	_navigation_decision = {}
	_arrival_action = &""
	_moving_action = &""
	_locomotion_velocity_gate_active = false
	if _actor != null:
		_actor.velocity.x = 0.0
		_actor.velocity.z = 0.0
	if play_stop:
		_request_body_action(stop_action)

func _think(ignore_grace: bool = false) -> bool:
	_refresh_refs()
	var block_reason := _get_block_reason(ignore_grace)
	if not block_reason.is_empty():
		autonomous_decision_skipped.emit(block_reason)
		_log("skip: %s" % block_reason)
		return false
	var snapshot := _build_snapshot()
	var decision: Dictionary = _choose_planner_decision(snapshot)
	if decision.is_empty():
		decision = _make_fallback_decision(snapshot)
	if decision.is_empty():
		autonomous_decision_skipped.emit("no_decision")
		return false
	return _dispatch_decision(decision)

func _dispatch_decision(decision: Dictionary) -> bool:
	match String(decision.get("kind", "")):
		"go_to_object":
			return _start_object_navigation(decision)
		"go_to_nav_point":
			return _start_nav_point_navigation(decision)
		"look_at_player":
			_face_player(1.0)
			_request_body_action(StringName(String(decision.get("action", String(listen_action)))))
			_apply_decision_expression(decision)
			_movement_cooldown_left = movement_cooldown_sec
			_start_dwell(float(decision.get("dwell_time_sec", 1.2)))
		"ambient":
			_request_body_action(StringName(String(decision.get("action", String(idle_action)))))
			_apply_decision_expression(decision)
			_movement_cooldown_left = movement_cooldown_sec
			_start_dwell(float(decision.get("dwell_time_sec", 1.4)))
			_try_request_self_talk(decision, self_talk_chance_on_ambient)
		_:
			return false
	_remember_local_decision(decision)
	_notify_decision_executed(decision)
	autonomous_decision_made.emit(decision.duplicate(true))
	_log("decision: %s" % str(decision))
	return true

func _start_nav_point_navigation(decision: Dictionary) -> bool:
	var target := String(decision.get("target_nav_point", "")).strip_edges()
	if not target.is_empty() and _is_target_on_cooldown(target):
		autonomous_decision_skipped.emit("nav_point_cooldown")
		return false
	var marker := _resolve_nav_point_marker(decision)
	if marker == null:
		autonomous_decision_skipped.emit("nav_point_missing")
		return false
	_navigation_target_position = marker.global_position
	_navigation_decision = decision.duplicate(true)
	_arrival_action = StringName(String(decision.get("arrival_action", String(idle_action))))
	_navigation_active = true
	_moving_action = &""
	if _navigation_motor != null and _navigation_motor.has_method("move_to_marker"):
		var run_flag := bool(decision.get("run", false))
		if not bool(_navigation_motor.call("move_to_marker", marker, _arrival_action, run_flag)):
			_navigation_active = false
			_navigation_decision = {}
			_arrival_action = &""
			autonomous_decision_skipped.emit("navigation_motor_failed")
			return false
	elif _navigation_agent != null:
		_navigation_agent.target_desired_distance = arrival_distance
		_navigation_agent.path_desired_distance = maxf(0.05, arrival_distance * 0.5)
		_navigation_agent.target_position = _navigation_target_position
	if not target.is_empty():
		_target_cooldowns[target] = float(decision.get("cooldown_sec", same_target_cooldown_sec))
	_movement_cooldown_left = movement_cooldown_sec
	_remember_local_decision(decision)
	_notify_decision_executed(decision)
	autonomous_decision_made.emit(decision.duplicate(true))
	_log("navigate point: %s" % str(decision))
	return true

func _start_object_navigation(decision: Dictionary) -> bool:
	var target := String(decision.get("target_object", "")).strip_edges()
	if not target.is_empty() and _is_target_on_cooldown(target):
		autonomous_decision_skipped.emit("target_cooldown")
		return false
	var marker := _resolve_decision_marker(decision)
	if marker == null:
		autonomous_decision_skipped.emit("target_marker_missing")
		return false
	_navigation_target_position = marker.global_position
	_navigation_decision = decision.duplicate(true)
	_arrival_action = StringName(String(decision.get("arrival_action", String(idle_action))))
	_navigation_active = true
	_moving_action = &""
	if _navigation_motor != null and _navigation_motor.has_method("move_to_marker"):
		var run_flag := bool(decision.get("run", false))
		if not bool(_navigation_motor.call("move_to_marker", marker, _arrival_action, run_flag)):
			_navigation_active = false
			_navigation_decision = {}
			_arrival_action = &""
			autonomous_decision_skipped.emit("navigation_motor_failed")
			return false
	elif _navigation_agent != null:
		_navigation_agent.target_desired_distance = arrival_distance
		_navigation_agent.path_desired_distance = maxf(0.05, arrival_distance * 0.5)
		_navigation_agent.target_position = _navigation_target_position
	if not target.is_empty():
		_target_cooldowns[target] = same_target_cooldown_sec
	if String(decision.get("marker_role", "")).to_lower() == sit_marker_role.to_lower():
		_sit_cooldown_left = sit_cooldown_sec
	_movement_cooldown_left = movement_cooldown_sec
	_remember_local_decision(decision)
	_notify_decision_executed(decision)
	autonomous_decision_made.emit(decision.duplicate(true))
	_log("navigate: %s" % str(decision))
	return true

func _update_navigation(delta: float) -> void:
	_refresh_refs()
	if _actor == null:
		stop_autonomous_navigation(false)
		return
	var final_distance := _actor.global_position.distance_to(_navigation_target_position)
	if final_distance <= arrival_distance:
		_finish_navigation()
		return
	var next_position := _navigation_target_position
	if _navigation_agent != null:
		next_position = _navigation_agent.get_next_path_position()
	var direction := next_position - _actor.global_position
	direction.y = 0.0
	if direction.length() <= 0.01:
		direction = _navigation_target_position - _actor.global_position
		direction.y = 0.0
		if direction.length() <= 0.01:
			return
	direction = direction.normalized()
	var want_run := bool(_navigation_decision.get("run", false)) or final_distance >= far_distance
	var speed := run_speed if want_run else walk_speed
	var moving_action := run_action if want_run else walk_action
	if moving_action != _moving_action:
		_set_moving_action(moving_action)
	if not _is_locomotion_velocity_ready():
		_actor.velocity.x = move_toward(_actor.velocity.x, 0.0, 18.0 * delta)
		_actor.velocity.z = move_toward(_actor.velocity.z, 0.0, 18.0 * delta)
	else:
		_actor.velocity.x = direction.x * speed
		_actor.velocity.z = direction.z * speed
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	if not _actor.is_on_floor():
		_actor.velocity.y -= gravity * delta
	else:
		_actor.velocity.y = 0.0
	_actor.move_and_slide()
	_face_direction(direction, delta)

func _finish_navigation() -> void:
	var finished := _navigation_decision.duplicate(true)
	var arrival := _arrival_action
	stop_autonomous_navigation(false)
	_apply_decision_face_target(finished, 1.0)
	if arrival != &"":
		_request_body_action(arrival)
		_apply_decision_expression(finished)
	else:
		_request_body_action(stop_action)
	_start_dwell(float(finished.get("dwell_time_sec", post_arrival_dwell_default_sec)))
	_think_left = maxf(_think_left, post_arrival_think_delay_sec)
	if _mind_state != null and _mind_state.has_method("apply_behavior_feedback"):
		_mind_state.call("apply_behavior_feedback", String(finished.get("feedback", finished.get("kind", ""))), finished)
	_try_request_self_talk(finished, self_talk_chance_on_arrival)
	autonomous_navigation_finished.emit(finished)

func _make_fallback_decision(snapshot: Dictionary) -> Dictionary:
	var mind := _get_mind_snapshot()
	var tired := float(mind.get("tiredness", 0.0))
	var bored := float(mind.get("boredom", 0.0))
	var curious := float(mind.get("curiosity", 0.0))
	var social_need := float(mind.get("social", 0.0))
	if tired > 0.62 and _sit_cooldown_left <= 0.0:
		var sit_decision := _make_object_decision(snapshot, true)
		if not sit_decision.is_empty():
			sit_decision["dwell_time_sec"] = 6.0
			return sit_decision
	if (curious + bored) > 0.85 and _movement_cooldown_left <= 0.0:
		var inspect_decision := _make_object_decision(snapshot, false)
		if not inspect_decision.is_empty() and _rng.randf() < inspect_chance:
			return inspect_decision
	if social_need > 0.55 and _last_decision_kind != "look_at_player" and _rng.randf() < look_at_player_chance:
		return {"kind": "look_at_player", "action": String(listen_action), "feedback": "look_at_player", "dwell_time_sec": 1.2}
	return _make_ambient_decision()

func _get_mind_snapshot() -> Dictionary:
	if _mind_state != null and _mind_state.has_method("get_state_snapshot"):
		var value: Variant = _mind_state.call("get_state_snapshot")
		if value is Dictionary:
			return value as Dictionary
	return {"curiosity": 0.4, "tiredness": 0.2, "boredom": 0.4, "social": 0.3, "duty": 0.3, "caution": 0.1}

func _make_object_decision(snapshot: Dictionary, want_sit: bool) -> Dictionary:
	var candidates := _collect_object_candidates(snapshot, want_sit)
	if candidates.is_empty():
		return {}
	var entry := _pick_weighted_candidate(candidates)
	var target_ref := _entry_ref(entry)
	if target_ref.is_empty():
		return {}
	var role := _choose_marker_role(entry, sit_marker_role if want_sit else inspect_marker_role)
	var arrival := &"sit_down" if want_sit else _choose_arrival_action(entry)
	return {
		"kind": "go_to_object",
		"target_object": target_ref,
		"marker_role": role,
		"arrival_action": String(arrival),
		"dwell_time_sec": _dwell_for_arrival(String(arrival)),
		"cooldown_sec": same_target_cooldown_sec,
		"run": float(entry.get("distance", 0.0)) >= far_distance and _rng.randf() < run_when_far_chance,
		"feedback": "sit" if want_sit else "inspect",
	}

func _make_ambient_decision() -> Dictionary:
	var action := _pick_ambient_action()
	if action.is_empty():
		return {}
	return {"kind": "ambient", "action": action, "feedback": action, "dwell_time_sec": _dwell_for_action(action)}

func _collect_object_candidates(snapshot: Dictionary, want_sit: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var objects: Variant = snapshot.get("nearby_objects", [])
	if objects is not Array:
		return result
	for value in objects:
		if value is not Dictionary:
			continue
		var entry := (value as Dictionary).duplicate(true)
		var ref := _entry_ref(entry)
		if ref.is_empty() or _is_target_on_cooldown(ref):
			continue
		if _has_any_tag(entry, avoid_autonomous_tags):
			continue
		if want_sit:
			if _has_any_tag(entry, sit_tags):
				result.append(entry)
		else:
			if _is_inspect_candidate(entry):
				result.append(entry)
	return result

func _is_inspect_candidate(entry: Dictionary) -> bool:
	if _has_any_tag(entry, inspect_tags):
		return true
	var actions: Variant = entry.get("actions", [])
	if actions is Array or actions is PackedStringArray:
		for action in actions:
			var text := String(action).to_lower()
			if text.find("inspect") >= 0 or text.find("check") >= 0 or text.find("open") >= 0 or text.find("count") >= 0:
				return true
	return false

func _choose_arrival_action(entry: Dictionary) -> StringName:
	var object_type := String(entry.get("type", "")).to_lower()
	if object_type == "food" or _has_any_tag(entry, PackedStringArray(["food", "supplies"])):
		return &"work_count_supplies"
	if object_type == "medical" or _has_any_tag(entry, PackedStringArray(["medical"])):
		return &"work_check_shelf"
	if object_type == "tool" or _has_any_tag(entry, PackedStringArray(["tool", "material", "utility"])):
		return &"work_check_lower"
	if object_type == "storage" or _has_any_tag(entry, PackedStringArray(["storage", "cabinet", "equipment"])):
		return &"work_inspect_cabinet"
	return &"look_around"

func _pick_weighted_candidate(candidates: Array[Dictionary]) -> Dictionary:
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _score_candidate(a) > _score_candidate(b)
	)
	if candidates.size() == 1:
		return candidates[0].duplicate(true)
	var best_score := _score_candidate(candidates[0])
	var close_candidates: Array[Dictionary] = []
	for candidate in candidates.slice(0, mini(candidates.size(), 3)):
		if best_score - _score_candidate(candidate) <= 0.45:
			close_candidates.append(candidate)
	if close_candidates.size() > 1 and _rng.randf() < 0.25:
		return close_candidates[_rng.randi_range(0, close_candidates.size() - 1)].duplicate(true)
	return candidates[0].duplicate(true)

func _score_candidate(entry: Dictionary) -> float:
	var distance := float(entry.get("distance", 999.0))
	var priority := float(entry.get("priority", 0.0))
	var score := priority * 2.0 - distance * 0.25
	if _has_any_tag(entry, PackedStringArray(["food", "medical", "equipment", "supplies"])):
		score += 1.5
	return score

func _choose_marker_role(entry: Dictionary, preferred: String) -> String:
	var roles_value: Variant = entry.get("marker_roles", {})
	if roles_value is Dictionary:
		var roles := roles_value as Dictionary
		if not preferred.is_empty() and roles.has(preferred):
			return preferred
		for fallback in ["open", "look", "approach", "sit"]:
			if roles.has(fallback):
				return fallback
		if not roles.is_empty():
			return String(roles.keys()[0])
	return preferred if not preferred.is_empty() else "approach"

func _pick_ambient_action() -> String:
	var candidates: Array[String] = []
	for value in ambient_actions:
		var action := String(value).strip_edges()
		if action.is_empty() or action == _last_ambient_action:
			continue
		candidates.append(action)
	if candidates.is_empty() and not ambient_actions.is_empty():
		return String(ambient_actions[0]).strip_edges()
	if candidates.is_empty():
		return ""
	var picked := candidates[_rng.randi_range(0, candidates.size() - 1)]
	_last_ambient_action = picked
	return picked

func _dwell_for_arrival(arrival_action: String) -> float:
	match arrival_action:
		"work_count_supplies", "work_inspect_cabinet", "work_check_shelf", "work_check_lower":
			return 2.8
		"sit_down":
			return 6.0
		"look_around", "curious_peek":
			return 2.2
	return post_arrival_dwell_default_sec

func _dwell_for_action(action: String) -> float:
	match action:
		"sleepy_yawn", "rub_eye": return 2.0
		"small_happy_bounce", "look_around", "curious_peek": return 1.8
		"tiny_wave", "tilt_head_cute": return 1.3
	return 1.4

func _start_dwell(duration: float) -> void:
	_dwell_left = maxf(_dwell_left, duration)

func _remember_local_decision(decision: Dictionary) -> void:
	_last_decision_kind = String(decision.get("kind", ""))
	_last_decision_target = _decision_target_ref(decision)
	if not _last_decision_kind.is_empty():
		_recent_decision_kinds.push_front(_last_decision_kind)
	while _recent_decision_kinds.size() > 6:
		_recent_decision_kinds.pop_back()

func _decision_target_ref(decision: Dictionary) -> String:
	for key in ["target_nav_point", "target_object", "action"]:
		var text := String(decision.get(key, "")).strip_edges()
		if not text.is_empty():
			return text
	return ""

func _resolve_decision_marker(decision: Dictionary) -> Marker3D:
	var target_ref := String(decision.get("target_object", "")).strip_edges()
	if target_ref.is_empty():
		return null
	var target := _find_world_object(target_ref)
	if target == null:
		return null
	var role := String(decision.get("marker_role", "approach")).strip_edges()
	var marker: Marker3D = null
	if target.has_method("get_marker_for_role"):
		marker = target.call("get_marker_for_role", role) as Marker3D
	if marker == null and target.has_method("get_nav_marker"):
		marker = target.call("get_nav_marker") as Marker3D
	return marker

func _resolve_nav_point_marker(decision: Dictionary) -> Marker3D:
	var path_text := String(decision.get("target_path", "")).strip_edges()
	if not path_text.is_empty():
		var by_path := get_node_or_null(NodePath(path_text)) as Marker3D
		if by_path != null:
			return by_path
		var scene_tree := get_tree()
		if scene_tree != null:
			by_path = scene_tree.root.get_node_or_null(NodePath(path_text)) as Marker3D
			if by_path != null:
				return by_path
	var target_ref := String(decision.get("target_nav_point", "")).strip_edges()
	if target_ref.is_empty():
		return null
	var tree := get_tree()
	if tree == null:
		return null
	for candidate in tree.get_nodes_in_group(&"ai_nav_point"):
		var node := candidate as Node
		if node == null or not is_instance_valid(node):
			continue
		if String(node.name) == target_ref:
			return node as Marker3D
		if node.has_method("build_ai_nav_point_summary"):
			var value: Variant = node.call("build_ai_nav_point_summary", _actor)
			if value is Dictionary and String((value as Dictionary).get("id", "")) == target_ref:
				return node as Marker3D
	return null

func _find_world_object(target_ref: String) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for candidate in tree.get_nodes_in_group(world_object_group):
		var node := candidate as Node
		if node == null or not is_instance_valid(node):
			continue
		if _get_world_object_id(node) == target_ref or String(node.name) == target_ref:
			return node
	return null

func _set_moving_action(action_name: StringName) -> void:
	var request_ok := _request_body_action(action_name)
	_moving_action = action_name
	_locomotion_velocity_gate_active = request_ok and _animation_behavior != null and _animation_behavior.has_method("get_current_state")

func _is_locomotion_velocity_ready() -> bool:
	if _moving_action == &"":
		return true
	if not _locomotion_velocity_gate_active:
		return true
	var state := StringName(_animation_behavior.call("get_current_state"))
	return state == &"MoveLoop"

func _request_body_action(action_name: StringName) -> bool:
	_refresh_refs()
	if action_name == &"" or _animation_behavior == null:
		return false
	if _animation_behavior.has_method("request_state"):
		if bool(_animation_behavior.call("request_state", action_name)):
			return true
	if _animation_behavior.has_method("request_action"):
		return bool(_animation_behavior.call("request_action", action_name))
	return false

func _apply_decision_expression(decision: Dictionary) -> bool:
	_refresh_refs()
	if _face_component == null:
		return false
	var expression := String(decision.get("arrival_expression", decision.get("expression", ""))).strip_edges()
	if expression.is_empty():
		expression = _expression_for_action(String(decision.get("arrival_action", decision.get("action", ""))))
	if expression.is_empty():
		return false
	if _face_component.has_method("set_face_expression"):
		return bool(_face_component.call("set_face_expression", StringName(expression)))
	if _face_component.has_method("set_expression"):
		return bool(_face_component.call("set_expression", StringName(expression)))
	return false

func _apply_decision_face_target(decision: Dictionary, delta: float = 1.0) -> bool:
	_refresh_refs()
	if _actor == null:
		return false
	var mode := String(decision.get("face_mode", "")).strip_edges().to_lower()
	match mode:
		"player":
			_face_player(delta)
			return true
		"target_object":
			var target_id := String(decision.get("target_object_id", decision.get("target_object", ""))).strip_edges()
			if target_id.is_empty():
				return false
			var target := _find_world_object(target_id) as Node3D
			if target == null:
				return false
			if _navigation_motor != null and _navigation_motor.has_method("face_position"):
				_navigation_motor.call("face_position", target.global_position, delta)
			else:
				_face_direction(target.global_position - _actor.global_position, delta)
			return true
		"marker_forward":
			var marker := _resolve_nav_point_marker(decision)
			if marker == null:
				return false
			var forward := marker.global_transform.basis.z
			if _navigation_motor != null and _navigation_motor.has_method("face_direction"):
				_navigation_motor.call("face_direction", forward, delta)
			else:
				_face_direction(forward, delta)
			return true
	return false

func _expression_for_action(action: String) -> String:
	match action.strip_edges().to_lower():
		"work_count_supplies", "work_take_item", "work_check_lower", "curious_peek", "tilt_head_cute":
			return "fun"
		"work_drink", "tiny_wave", "small_happy_bounce", "react_wave":
			return "joy"
		"rub_eye", "sleepy_yawn", "seated_sleepy":
			return "sorrow"
		"cute_startle", "look_back":
			return "surprised"
	return ""

func _try_request_self_talk(decision: Dictionary, chance: float) -> bool:
	if not self_talk_enabled:
		return false
	if _dialogue_component == null or not _dialogue_component.has_method("send_player_text"):
		return false
	if _self_talk_cooldown_left > 0.0:
		return false
	if _rng.randf() > chance:
		return false
	var text := _build_self_talk_prompt(decision)
	if text.is_empty():
		return false
	var result_value: Variant = _dialogue_component.call("send_player_text", text)
	var ok := false
	if result_value is Dictionary:
		ok = bool((result_value as Dictionary).get("ok", false))
	elif result_value is bool:
		ok = bool(result_value)
	if ok:
		_self_talk_cooldown_left = self_talk_cooldown_sec
		notify_dialogue_started()
	return ok

func _build_self_talk_prompt(decision: Dictionary) -> String:
	var context_parts: Array[String] = []
	var kind := String(decision.get("kind", "")).strip_edges()
	var target := _decision_target_ref(decision)
	var action := String(decision.get("arrival_action", decision.get("action", ""))).strip_edges()
	if not kind.is_empty():
		context_parts.append("行为=%s" % kind)
	if not target.is_empty():
		context_parts.append("目标=%s" % target)
	if not action.is_empty():
		context_parts.append("动作=%s" % action)
	var context_text := "正在避难所里活动"
	if not context_parts.is_empty():
		context_text = "，".join(context_parts)
	return "%s 当前%s。请返回JSON字段dialogue/expression/action/visemes，dialogue不超过%d字，visemes只使用aa、ih、ou、E、oh。" % [
		self_talk_prompt_prefix,
		context_text,
		maxi(8, self_talk_max_chars),
	]

func _choose_planner_decision(snapshot: Dictionary) -> Dictionary:
	_refresh_refs()
	if _planner == null or not _planner.has_method("choose_decision"):
		return {}
	var context := {
		"perception": snapshot,
		"last_kind": _last_decision_kind,
		"last_target": _last_object_target(),
		"last_nav_point": _last_nav_point_target(),
		"target_cooldowns": _target_cooldowns.duplicate(),
	}
	if snapshot.has("known_nav_points"):
		context["known_nav_points"] = snapshot.get("known_nav_points", [])
	elif _perception_component != null and _perception_component.has_method("build_known_nav_points"):
		context["known_nav_points"] = _perception_component.call("build_known_nav_points")
	var value: Variant = _planner.call("choose_decision", context)
	return value as Dictionary if value is Dictionary else {}

func _notify_decision_executed(decision: Dictionary) -> void:
	if _planner != null and _planner.has_method("notify_decision_executed"):
		_planner.call("notify_decision_executed", decision)

func _last_object_target() -> String:
	return String(_navigation_decision.get("target_object", "")).strip_edges()

func _last_nav_point_target() -> String:
	return String(_navigation_decision.get("target_nav_point", "")).strip_edges()

func _build_snapshot() -> Dictionary:
	if _perception_component == null or not _perception_component.has_method("build_perception_snapshot"):
		return {}
	var value: Variant = _perception_component.call("build_perception_snapshot")
	return value as Dictionary if value is Dictionary else {}

func _get_block_reason(ignore_grace: bool) -> String:
	if not ignore_grace and _external_grace_left > 0.0:
		return "external_grace"
	if not ignore_grace and _movement_cooldown_left > 0.0:
		return "movement_cooldown"
	if _is_external_action_busy():
		return "external_action_busy"
	return ""

func _face_player(delta: float) -> void:
	var player := _find_player()
	if player == null or _actor == null:
		return
	if _navigation_motor != null and _navigation_motor.has_method("face_position"):
		_navigation_motor.call("face_position", player.global_position, delta)
		return
	var direction := player.global_position - _actor.global_position
	direction.y = 0.0
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

func _is_external_action_busy() -> bool:
	_refresh_refs()
	if _action_executor == null:
		return false
	if _action_executor.has_method("is_busy"):
		return bool(_action_executor.call("is_busy"))
	if _action_executor.has_method("is_navigating"):
		return bool(_action_executor.call("is_navigating"))
	return false

func _bind_external_control_signals() -> void:
	if _action_executor != null:
		_connect_signal_if_exists(_action_executor, "ai_response_application_started", "_on_external_ai_started")
		_connect_signal_if_exists(_action_executor, "navigation_started", "_on_external_navigation_started")
	if _dialogue_component != null:
		_connect_signal_if_exists(_dialogue_component, "dialogue_requested", "_on_dialogue_requested")

func _bind_navigation_motor_signals() -> void:
	if _navigation_motor == null:
		return
	_connect_signal_if_exists(_navigation_motor, "navigation_finished", "_on_motor_navigation_finished")
	_connect_signal_if_exists(_navigation_motor, "navigation_cancelled", "_on_motor_navigation_cancelled")
	_connect_signal_if_exists(_navigation_motor, "navigation_failed", "_on_motor_navigation_failed")

func _connect_signal_if_exists(source: Node, signal_name: String, method_name: String) -> void:
	if source == null or not source.has_signal(signal_name):
		return
	var callback := Callable(self, method_name)
	if not source.is_connected(signal_name, callback):
		source.connect(signal_name, callback)

func _on_external_ai_started(_ai_data: Dictionary = {}) -> void:
	notify_external_control()

func _on_external_navigation_started(_target_marker_path: NodePath = NodePath(), _external_arrival_action: StringName = &"") -> void:
	notify_external_control()

func _on_dialogue_requested(_payload: Dictionary = {}) -> void:
	notify_external_control()

func _on_motor_navigation_finished(_finished_action: StringName = &"") -> void:
	if not _navigation_active:
		return
	var finished := _navigation_decision.duplicate(true)
	_navigation_active = false
	_navigation_decision = {}
	_arrival_action = &""
	_moving_action = &""
	_apply_decision_face_target(finished, 1.0)
	_apply_decision_expression(finished)
	_start_dwell(float(finished.get("dwell_time_sec", post_arrival_dwell_default_sec)))
	_think_left = maxf(_think_left, post_arrival_think_delay_sec)
	if _mind_state != null and _mind_state.has_method("apply_behavior_feedback"):
		_mind_state.call("apply_behavior_feedback", String(finished.get("feedback", finished.get("kind", ""))), finished)
	_try_request_self_talk(finished, self_talk_chance_on_arrival)
	autonomous_navigation_finished.emit(finished)

func _on_motor_navigation_cancelled() -> void:
	_navigation_active = false
	_navigation_decision = {}
	_arrival_action = &""
	_moving_action = &""
	_locomotion_velocity_gate_active = false

func _on_motor_navigation_failed(reason: String = "") -> void:
	_navigation_active = false
	_navigation_decision = {}
	_arrival_action = &""
	_moving_action = &""
	_locomotion_velocity_gate_active = false
	autonomous_decision_skipped.emit("navigation_failed:%s" % reason)

func _tick_timers(delta: float) -> void:
	_external_grace_left = maxf(0.0, _external_grace_left - delta)
	_movement_cooldown_left = maxf(0.0, _movement_cooldown_left - delta)
	_sit_cooldown_left = maxf(0.0, _sit_cooldown_left - delta)
	_self_talk_cooldown_left = maxf(0.0, _self_talk_cooldown_left - delta)
	var expired: Array = []
	for key in _target_cooldowns.keys():
		var next_value := maxf(0.0, float(_target_cooldowns[key]) - delta)
		if next_value <= 0.0:
			expired.append(key)
		else:
			_target_cooldowns[key] = next_value
	for key in expired:
		_target_cooldowns.erase(key)

func _schedule_next_think() -> void:
	_think_left = _rng.randf_range(think_interval_min, maxf(think_interval_max, think_interval_min))

func _refresh_refs() -> void:
	_perception_component = get_node_or_null(perception_component_path) if perception_component_path != NodePath() else null
	_planner = get_node_or_null(planner_path) if planner_path != NodePath() else null
	_mind_state = get_node_or_null(mind_state_path) if mind_state_path != NodePath() else null
	_animation_behavior = get_node_or_null(animation_behavior_path) if animation_behavior_path != NodePath() else null
	_navigation_motor = get_node_or_null(navigation_motor_path) if navigation_motor_path != NodePath() else null
	_action_executor = get_node_or_null(action_executor_path) if action_executor_path != NodePath() else null
	_dialogue_component = get_node_or_null(dialogue_component_path) if dialogue_component_path != NodePath() else null
	_face_component = get_node_or_null(face_component_path) if face_component_path != NodePath() else null
	_actor = get_node_or_null(actor_path) as CharacterBody3D if actor_path != NodePath() else null
	_navigation_agent = get_node_or_null(navigation_agent_path) as NavigationAgent3D if navigation_agent_path != NodePath() else null
	if _perception_component == null:
		_perception_component = _find_sibling_with_method(&"build_perception_snapshot")
	if _planner == null:
		_planner = _find_sibling_with_method(&"choose_decision")
	if _mind_state == null:
		_mind_state = _find_sibling_with_method(&"get_state_snapshot")
	if _animation_behavior == null:
		_animation_behavior = _find_sibling_with_method(&"request_action")
	if _navigation_motor == null:
		_navigation_motor = _find_sibling_with_method(&"move_to_marker")
	if _action_executor == null:
		_action_executor = _find_sibling_with_method(&"apply_ai_response")
	if _dialogue_component == null:
		_dialogue_component = _find_sibling_with_method(&"send_player_text")
	if _face_component == null:
		_face_component = _find_sibling_with_method(&"set_face_expression")
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

func _entry_ref(entry: Dictionary) -> String:
	for key in ["id", "object_id", "name"]:
		var text := String(entry.get(key, "")).strip_edges()
		if not text.is_empty():
			return text
	return ""

func _is_target_on_cooldown(ref: String) -> bool:
	return _target_cooldowns.has(ref) and float(_target_cooldowns[ref]) > 0.0

func _has_any_tag(entry: Dictionary, tag_list: PackedStringArray) -> bool:
	var tags: Variant = entry.get("tags", [])
	if tags is not Array and tags is not PackedStringArray:
		return false
	for tag in tags:
		var tag_text := String(tag).strip_edges().to_lower()
		for wanted in tag_list:
			if tag_text == String(wanted).strip_edges().to_lower():
				return true
	return false

func _get_world_object_id(node: Node) -> String:
	if node == null:
		return ""
	var value: Variant = node.get("object_id")
	var clean := String(value).strip_edges()
	if not clean.is_empty():
		return clean
	return String(node.name)

func _log(message: String) -> void:
	if debug_log:
		print("[CharacterAutonomousLife] %s" % message)
