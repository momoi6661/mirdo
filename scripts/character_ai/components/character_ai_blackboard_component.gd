extends Node
class_name CharacterAIBlackboardComponent

@export var actor_path: NodePath
@export var perception_component_path: NodePath
@export var mind_state_path: NodePath
@export var state_component_path: NodePath
@export var player_awareness_path: NodePath
@export var autonomous_life_path: NodePath
@export var action_semantics_path: NodePath
@export var situation_behavior_pack_path: NodePath
@export_range(0, 128, 1) var max_action_contract_entries: int = 48
@export var debug_print_enabled: bool = false
@export_range(0.2, 30.0, 0.1) var debug_print_interval_sec: float = 2.0

var _actor: Node3D
var _perception_component: Node
var _mind_state: Node
var _state_component: Node
var _player_awareness: Node
var _autonomous_life: Node
var _action_semantics: Node
var _situation_behavior_pack: Node
var _debug_print_left: float = 0.0

func _ready() -> void:
	_refresh_refs()
	_debug_print_left = debug_print_interval_sec

func _process(delta: float) -> void:
	if not debug_print_enabled:
		return
	_debug_print_left -= delta
	if _debug_print_left > 0.0:
		return
	_debug_print_left = debug_print_interval_sec
	print(build_debug_summary_line())

func build_blackboard_snapshot() -> Dictionary:
	_refresh_refs()
	var snapshot := {
		"schema": "character_ai_blackboard.v1",
		"actor": _build_actor_context(),
	}
	var perception := _build_perception_context()
	if not perception.is_empty():
		snapshot["perception"] = perception
	var known := _build_known_nav_points()
	if not known.is_empty():
		snapshot["known_nav_points"] = known
	var mind := _build_mind_context()
	if not mind.is_empty():
		snapshot["mind_state"] = mind
	var resources := _build_resource_context()
	if not resources.is_empty():
		snapshot["resource_stats"] = resources
	var awareness := _build_player_awareness_context()
	if not awareness.is_empty():
		snapshot["player_awareness"] = awareness
	var behavior := _build_current_behavior_context()
	if not behavior.is_empty():
		snapshot["current_behavior"] = behavior
	var actions := _build_action_contract()
	if not actions.is_empty():
		snapshot["action_contract"] = actions
	var situation := _build_situation_context(snapshot)
	if not situation.is_empty():
		snapshot["situation_context"] = situation
	return snapshot

func build_llm_context() -> Dictionary:
	var snapshot := build_blackboard_snapshot()
	snapshot["contract_note"] = "Blackboard is Mirdo's unified runtime context. Use known_nav_points for movement targets and action_contract for valid body actions."
	return snapshot

func build_debug_summary_line() -> String:
	var snapshot := build_blackboard_snapshot()
	var situation := snapshot.get("situation_context", {}) as Dictionary if snapshot.get("situation_context", {}) is Dictionary else {}
	var behavior := snapshot.get("current_behavior", {}) as Dictionary if snapshot.get("current_behavior", {}) is Dictionary else {}
	var resources := snapshot.get("resource_stats", {}) as Dictionary if snapshot.get("resource_stats", {}) is Dictionary else {}
	var awareness := snapshot.get("player_awareness", {}) as Dictionary if snapshot.get("player_awareness", {}) is Dictionary else {}
	var target := _extract_behavior_target(behavior)
	return "[AIBlackboard] pack=%s score=%.2f kind=%s target=%s task_stack=%d energy=%.1f mood=%.1f gaze=%s near=%s" % [
		String(situation.get("primary_pack", "")),
		float(situation.get("primary_score", 0.0)),
		String(behavior.get("current_kind", behavior.get("last_decision_kind", ""))),
		target,
		int(behavior.get("task_stack_size", _task_stack_size_from_behavior(behavior))),
		float(resources.get("energy", -1.0)),
		float(resources.get("mood", -1.0)),
		str(bool(awareness.get("gaze_active", false))),
		str(bool(awareness.get("near", false))),
	]

func print_debug_snapshot(include_llm_context: bool = false) -> void:
	if include_llm_context:
		print("[AIBlackboardDump] %s" % JSON.stringify(build_llm_context(), "\t"))
		return
	print(build_debug_summary_line())

func get_action_semantics(action_name: StringName) -> Dictionary:
	_refresh_refs()
	if _action_semantics != null and _action_semantics.has_method("get_action_semantics"):
		var value: Variant = _action_semantics.call("get_action_semantics", action_name)
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	return {}

func get_actions_for_context(context_name: String) -> Array:
	_refresh_refs()
	if _action_semantics != null and _action_semantics.has_method("get_actions_for_context"):
		var value: Variant = _action_semantics.call("get_actions_for_context", context_name)
		if value is Array:
			return value as Array
	return []

func _build_actor_context() -> Dictionary:
	var out := {}
	if _actor != null:
		out["path"] = String(_actor.get_path()) if _actor.is_inside_tree() else String(_actor.name)
		out["position"] = _vector3_to_dict(_actor.global_position)
	return out

func _build_perception_context() -> Dictionary:
	if _perception_component == null or not _perception_component.has_method("build_perception_snapshot"):
		return {}
	var value: Variant = _perception_component.call("build_perception_snapshot")
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}

func _build_known_nav_points() -> Array:
	if _perception_component == null or not _perception_component.has_method("build_known_nav_points"):
		return []
	var value: Variant = _perception_component.call("build_known_nav_points", _actor)
	return (value as Array).duplicate(true) if value is Array else []

func _build_mind_context() -> Dictionary:
	if _mind_state == null or not _mind_state.has_method("get_state_snapshot"):
		return {}
	var value: Variant = _mind_state.call("get_state_snapshot")
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}

func _build_resource_context() -> Dictionary:
	if _state_component != null and _state_component.has_method("get_snapshot"):
		var value: Variant = _state_component.call("get_snapshot")
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	if _state_component != null and _state_component.has_method("build_ai_stats"):
		var stats_value: Variant = _state_component.call("build_ai_stats")
		if stats_value is Dictionary:
			return (stats_value as Dictionary).duplicate(true)
	return {}

func _build_player_awareness_context() -> Dictionary:
	if _player_awareness == null or not _player_awareness.has_method("build_player_awareness_snapshot"):
		return {}
	var value: Variant = _player_awareness.call("build_player_awareness_snapshot")
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}

func _build_current_behavior_context() -> Dictionary:
	if _autonomous_life != null and _autonomous_life.has_method("get_autonomous_debug_snapshot"):
		var value: Variant = _autonomous_life.call("get_autonomous_debug_snapshot")
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	if _autonomous_life != null and _autonomous_life.has_method("get_current_behavior_snapshot"):
		var behavior_value: Variant = _autonomous_life.call("get_current_behavior_snapshot")
		if behavior_value is Dictionary:
			return (behavior_value as Dictionary).duplicate(true)
	return {}

func _build_action_contract() -> Array:
	if _action_semantics == null or not _action_semantics.has_method("build_action_contract"):
		return []
	var value: Variant = _action_semantics.call("build_action_contract", [])
	if value is not Array:
		return []
	var out: Array = []
	for entry in value:
		if out.size() >= max_action_contract_entries:
			break
		if entry is Dictionary:
			out.append((entry as Dictionary).duplicate(true))
	return out

func _build_situation_context(snapshot: Dictionary) -> Dictionary:
	if _situation_behavior_pack == null or not _situation_behavior_pack.has_method("evaluate_situations"):
		return {}
	var value: Variant = _situation_behavior_pack.call("evaluate_situations", snapshot)
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}

func _extract_behavior_target(behavior: Dictionary) -> String:
	for key in ["current_target", "last_decision_target", "resume_target"]:
		var text := String(behavior.get(key, "")).strip_edges()
		if not text.is_empty():
			return text
	var current: Variant = behavior.get("current_decision", {})
	if current is Dictionary:
		for key in ["target_nav_point", "target_object", "action"]:
			var text := String((current as Dictionary).get(key, "")).strip_edges()
			if not text.is_empty():
				return text
	return ""

func _task_stack_size_from_behavior(behavior: Dictionary) -> int:
	var task_stack: Variant = behavior.get("task_stack", {})
	if task_stack is Dictionary:
		return int((task_stack as Dictionary).get("stack_size", 0))
	var resume: Variant = behavior.get("resume", {})
	if resume is Dictionary:
		var nested: Variant = (resume as Dictionary).get("task_stack", {})
		if nested is Dictionary:
			return int((nested as Dictionary).get("stack_size", 0))
	return 0

func _refresh_refs() -> void:
	_actor = get_node_or_null(actor_path) as Node3D if actor_path != NodePath() else null
	_perception_component = get_node_or_null(perception_component_path) if perception_component_path != NodePath() else null
	_mind_state = get_node_or_null(mind_state_path) if mind_state_path != NodePath() else null
	_state_component = get_node_or_null(state_component_path) if state_component_path != NodePath() else null
	_player_awareness = get_node_or_null(player_awareness_path) if player_awareness_path != NodePath() else null
	_autonomous_life = get_node_or_null(autonomous_life_path) if autonomous_life_path != NodePath() else null
	_action_semantics = get_node_or_null(action_semantics_path) if action_semantics_path != NodePath() else null
	_situation_behavior_pack = get_node_or_null(situation_behavior_pack_path) if situation_behavior_pack_path != NodePath() else null
	if _actor == null:
		_actor = _find_parent_node3d()
	if _perception_component == null:
		_perception_component = _find_sibling_with_method(&"build_perception_snapshot")
	if _mind_state == null:
		_mind_state = _find_sibling_with_method(&"get_state_snapshot")
	if _state_component == null:
		_state_component = _find_sibling_with_method(&"get_snapshot")
	if _player_awareness == null:
		_player_awareness = _find_sibling_with_method(&"build_player_awareness_snapshot")
	if _autonomous_life == null:
		_autonomous_life = _find_sibling_with_method(&"get_current_behavior_snapshot")
	if _action_semantics == null:
		_action_semantics = _find_sibling_with_method(&"get_action_semantics")
	if _situation_behavior_pack == null:
		_situation_behavior_pack = _find_sibling_with_method(&"evaluate_situations")

func _find_sibling_with_method(method_name: StringName) -> Node:
	var parent_node := get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var node := child as Node
		if node != null and node != self and node.has_method(method_name):
			return node
	return null

func _find_parent_node3d() -> Node3D:
	var current := get_parent()
	while current != null:
		if current is Node3D:
			return current as Node3D
		current = current.get_parent()
	return null

func _vector3_to_dict(value: Vector3) -> Dictionary:
	return {"x": snappedf(value.x, 0.001), "y": snappedf(value.y, 0.001), "z": snappedf(value.z, 0.001)}
