extends Node
class_name CharacterActionSchedulerComponent

signal scheduled_action_started(action_name: StringName, source: String, priority: int)
signal scheduled_action_finished(action_name: StringName, source: String, ok: bool)
signal scheduled_action_rejected(action_name: StringName, source: String, reason: String)

@export var animation_behavior_path: NodePath = NodePath("../AnimationBehaviorTreeComponent")
@export var action_executor_path: NodePath = NodePath("../CharacterAIActionExecutor")
@export var navigation_motor_path: NodePath = NodePath("../..")
@export var default_return_action: StringName = &"idle_normal"
@export var seated_return_action: StringName = &"seated_idle"
@export_range(0.1, 10.0, 0.05) var fallback_action_duration_sec: float = 1.4
@export_range(0.0, 3.0, 0.05) var action_tail_guard_sec: float = 0.15
@export_range(0.0, 3.0, 0.05) var stand_up_guard_sec: float = 1.2
@export_range(0.0, 3.0, 0.05) var locomotion_stop_guard_sec: float = 0.55
@export var debug_log: bool = false

var _animation_behavior: Node
var _action_executor: Node
var _navigation_motor: Node
var _queue: Array[Dictionary] = []
var _active: Dictionary = {}
var _busy: bool = false
var _serial: int = 0

const LOCOMOTION_ACTIONS := [&"walk", &"run", &"walk_forward", &"run_forward", &"walk_loop", &"run_loop"]
const SEATED_ACTIONS := [&"sit_down", &"seated_idle", &"seated_sleepy"]
const STAND_UP_ACTIONS := [&"stand", &"stand_up", &"idle_normal", &"idle_relaxed", &"idle_alert", &"idle_fidget", &"listen"]

func _ready() -> void:
	_refresh_refs()

func request_action(action_name: StringName, priority: int = 0, source: String = "", return_action: StringName = &"") -> bool:
	_refresh_refs()
	var action := _normalize_action(action_name)
	if action == &"":
		scheduled_action_rejected.emit(action_name, source, "empty_action")
		return false
	var entry := {
		"action": action,
		"priority": priority,
		"source": source,
		"return_action": return_action,
		"sequence": PackedStringArray(),
	}
	if _busy:
		if priority < int(_active.get("priority", 0)):
			scheduled_action_rejected.emit(action, source, "busy_lower_priority")
			return false
		_queue_action_entry(entry)
		return true
	return _start_entry(entry)

func request_sequence(actions: Array, priority: int = 0, source: String = "", return_action: StringName = &"") -> bool:
	var normalized := PackedStringArray()
	for raw in actions:
		var action := _normalize_action(StringName(String(raw)))
		if action != &"":
			normalized.append(String(action))
	if normalized.is_empty():
		scheduled_action_rejected.emit(&"", source, "empty_sequence")
		return false
	var first := StringName(normalized[0])
	var rest := PackedStringArray()
	for i in range(1, normalized.size()):
		rest.append(normalized[i])
	var entry := {
		"action": first,
		"priority": priority,
		"source": source,
		"return_action": return_action,
		"sequence": rest,
	}
	if _busy:
		if priority < int(_active.get("priority", 0)):
			scheduled_action_rejected.emit(first, source, "busy_lower_priority")
			return false
		_queue_action_entry(entry)
		return true
	return _start_entry(entry)

func is_busy() -> bool:
	return _busy or not _queue.is_empty()

func clear_queue() -> void:
	_queue.clear()

func cancel_current(play_return: bool = false) -> void:
	_serial += 1
	var old := _active.duplicate(true)
	_active = {}
	_busy = false
	if play_return:
		_request_body_action(_resolve_return_action(StringName(old.get("return_action", ""))))
	_drain_queue_deferred()

func _queue_action_entry(entry: Dictionary) -> void:
	_queue.append(entry)
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("priority", 0)) > int(b.get("priority", 0))
	)

func _start_entry(entry: Dictionary) -> bool:
	_refresh_refs()
	var action := StringName(entry.get("action", ""))
	if action == &"":
		return false
	if _navigation_motor != null and _navigation_motor.has_method("is_navigating") and bool(_navigation_motor.call("is_navigating")):
		if _navigation_motor.has_method("stop_navigation"):
			_navigation_motor.call("stop_navigation", true)
		await_guard(locomotion_stop_guard_sec)
	_busy = true
	_serial += 1
	var serial := _serial
	_active = entry.duplicate(true)
	scheduled_action_started.emit(action, String(entry.get("source", "")), int(entry.get("priority", 0)))
	var ok := _request_body_action(action)
	if not ok:
		_finish_entry(serial, false)
		return false
	var duration := _get_action_duration(action)
	_run_finish_timer(serial, duration + action_tail_guard_sec)
	return true

func await_guard(delay_sec: float) -> void:
	if delay_sec <= 0.0 or not is_inside_tree():
		return
	await get_tree().create_timer(delay_sec).timeout

func _run_finish_timer(serial: int, delay_sec: float) -> void:
	if delay_sec > 0.0 and is_inside_tree():
		await get_tree().create_timer(delay_sec).timeout
	_finish_entry(serial, true)

func _finish_entry(serial: int, ok: bool) -> void:
	if serial != _serial:
		return
	var finished := _active.duplicate(true)
	var action := StringName(finished.get("action", ""))
	var source := String(finished.get("source", ""))
	var sequence_value: Variant = finished.get("sequence", PackedStringArray())
	var sequence := sequence_value as PackedStringArray if sequence_value is PackedStringArray else PackedStringArray()
	if not sequence.is_empty():
		var next := StringName(sequence[0])
		var rest := PackedStringArray()
		for i in range(1, sequence.size()):
			rest.append(sequence[i])
		finished["action"] = next
		finished["sequence"] = rest
		_active = {}
		_busy = false
		scheduled_action_finished.emit(action, source, ok)
		_start_entry(finished)
		return
	_active = {}
	_busy = false
	scheduled_action_finished.emit(action, source, ok)
	var return_action := _resolve_return_action(StringName(finished.get("return_action", "")))
	if return_action != &"" and ok:
		_request_body_action(return_action)
	_drain_queue_deferred()

func _drain_queue_deferred() -> void:
	if not is_inside_tree():
		_drain_queue()
		return
	call_deferred("_drain_queue")

func _drain_queue() -> void:
	if _busy or _queue.is_empty():
		return
	var next := _queue.pop_front() as Dictionary
	_start_entry(next)

func _request_body_action(action_name: StringName) -> bool:
	_refresh_refs()
	if action_name == &"" or _animation_behavior == null:
		return false
	if _animation_behavior.has_method("request_state") and bool(_animation_behavior.call("request_state", action_name)):
		return true
	if _animation_behavior.has_method("request_action"):
		return bool(_animation_behavior.call("request_action", action_name))
	return false

func _get_action_duration(action_name: StringName) -> float:
	_refresh_refs()
	if _animation_behavior != null and _animation_behavior.has_method("get_action_duration"):
		var fallback := fallback_action_duration_sec
		if String(action_name) == "stand_up":
			fallback = maxf(fallback, stand_up_guard_sec)
		var value := float(_animation_behavior.call("get_action_duration", action_name, fallback))
		return maxf(0.05, value)
	return fallback_action_duration_sec

func _resolve_return_action(requested: StringName) -> StringName:
	if requested != &"":
		return requested
	if _is_currently_seated():
		return seated_return_action
	return default_return_action

func _is_currently_seated() -> bool:
	_refresh_refs()
	if _action_executor != null and _action_executor.has_method("get_active_sit_marker"):
		var marker: Variant = _action_executor.call("get_active_sit_marker")
		if marker is Marker3D:
			return true
	if _animation_behavior != null and _animation_behavior.has_method("get_current_mode"):
		return StringName(_animation_behavior.call("get_current_mode")) == &"Posture"
	return false

func _normalize_action(action_name: StringName) -> StringName:
	return StringName(String(action_name).strip_edges().to_lower())

func _refresh_refs() -> void:
	_animation_behavior = get_node_or_null(animation_behavior_path) if animation_behavior_path != NodePath() else null
	_action_executor = get_node_or_null(action_executor_path) if action_executor_path != NodePath() else null
	_navigation_motor = get_node_or_null(navigation_motor_path) if navigation_motor_path != NodePath() else null
	if _animation_behavior == null:
		_animation_behavior = _find_sibling_with_method(&"request_action")
	if _action_executor == null:
		_action_executor = _find_sibling_with_method(&"apply_ai_response")
	if _navigation_motor == null:
		_navigation_motor = _find_ancestor_with_method(&"move_to_marker")

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
	var cursor := get_parent()
	while cursor != null:
		if cursor.has_method(method_name):
			return cursor
		cursor = cursor.get_parent()
	return null

func _log(message: String) -> void:
	if debug_log:
		print("[CharacterActionScheduler] %s" % message)
