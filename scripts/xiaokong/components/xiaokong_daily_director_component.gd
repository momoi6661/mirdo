extends Node
class_name XiaokongDailyDirectorComponent

signal day_started(day_index: int, active_events: Array)
signal hour_changed(day_index: int, current_hour: float)
signal event_state_changed(event_id: StringName, state: String, event_data: Dictionary)
signal day_finished(day_index: int, summary: Dictionary)

@export var state_component_path: NodePath
@export_range(1.0, 48.0, 0.5) var hours_per_day: float = 16.0
@export_range(1, 5, 1) var events_per_day: int = 2
@export var auto_start_on_ready: bool = false

var current_day: int = 0
var current_hour: float = 0.0
var active_events: Array[Dictionary] = []
var completed_events: Dictionary = {}
var failed_events: Dictionary = {}

var _rng = RandomNumberGenerator.new()
var _state_component: XiaokongStateComponent

const EVENT_TEMPLATES: Array[Dictionary] = [
	{
		"id": "hydrate_now",
		"title": "小空口渴了",
		"required_item_ids": ["water_bottle"],
		"deadline_min": 3.0,
		"deadline_max": 6.0,
		"reward": {"thirst": 20, "mood": 3, "favor": 1},
		"penalty": {"mood": -6, "favor": -2},
	},
	{
		"id": "proper_meal",
		"title": "补充食物",
		"required_item_ids": ["ration_bar", "hot_meal"],
		"deadline_min": 5.0,
		"deadline_max": 9.0,
		"reward": {"hunger": 18, "mood": 4, "favor": 2},
		"penalty": {"mood": -5, "favor": -2},
	},
	{
		"id": "comfort_food",
		"title": "安抚性投喂",
		"required_item_ids": ["sweet_snack"],
		"deadline_min": 8.0,
		"deadline_max": 12.0,
		"reward": {"mood": 8, "favor": 2},
		"penalty": {"mood": -4},
	},
	{
		"id": "late_water",
		"title": "睡前补水",
		"required_item_ids": ["water_bottle"],
		"deadline_min": 11.0,
		"deadline_max": 15.0,
		"reward": {"thirst": 16, "mood": 2},
		"penalty": {"mood": -3, "favor": -1},
	},
]

func _ready() -> void:
	_rng.randomize()
	_state_component = get_node_or_null(state_component_path) as XiaokongStateComponent
	if _state_component == null:
		_state_component = _find_state_component()

	if auto_start_on_ready:
		start_day(1)

func start_day(day_index: int) -> void:
	current_day = max(day_index, 1)
	current_hour = 0.0
	completed_events.clear()
	failed_events.clear()
	active_events = _build_events_for_day(events_per_day)
	day_started.emit(current_day, active_events.duplicate(true))

func advance_hours(hours: float) -> void:
	if hours <= 0.0 or active_events.is_empty():
		return

	current_hour += hours
	current_hour = minf(current_hour, hours_per_day)
	_apply_deadline_failures()
	hour_changed.emit(current_day, current_hour)

	if current_hour >= hours_per_day:
		_finish_day()

func resolve_event_with_item(event_id: StringName, item_id: String) -> Dictionary:
	var normalized_item_id = item_id.strip_edges().to_lower()
	if normalized_item_id.is_empty():
		return {"ok": false, "error": "item_id_empty"}

	for i in range(active_events.size()):
		var event = active_events[i]
		if StringName(String(event.get("id", ""))) != event_id:
			continue
		if String(event.get("state", "pending")) != "pending":
			return {"ok": false, "error": "event_not_pending"}

		var required_items = event.get("required_item_ids", [])
		if required_items is not Array or not _contains_item(required_items, normalized_item_id):
			return {"ok": false, "error": "item_not_accepted"}

		var reward_delta = _normalize_delta_dict(event.get("reward", {}))
		if _state_component != null:
			reward_delta = _state_component.apply_delta(reward_delta, "daily_event_reward")

		event["state"] = "completed"
		event["resolved_hour"] = current_hour
		active_events[i] = event
		completed_events[String(event_id)] = true
		event_state_changed.emit(event_id, "completed", event.duplicate(true))
		return {
			"ok": true,
			"event_id": String(event_id),
			"applied_delta": reward_delta,
		}

	return {"ok": false, "error": "event_not_found"}

func resolve_event_with_item_data(event_id: StringName, item_data: Resource) -> Dictionary:
	var item_id = _extract_item_id(item_data)
	if item_id.is_empty():
		return {"ok": false, "error": "cannot_resolve_item_id"}
	return resolve_event_with_item(event_id, item_id)

func get_pending_events() -> Array[Dictionary]:
	var pending: Array[Dictionary] = []
	for event in active_events:
		if String(event.get("state", "pending")) == "pending":
			pending.append(event.duplicate(true))
	return pending

func has_pending_events() -> bool:
	for event in active_events:
		if String(event.get("state", "pending")) == "pending":
			return true
	return false

func _get_custom_save_data() -> Dictionary:
	return {
		"current_day": current_day,
		"current_hour": current_hour,
		"active_events": active_events.duplicate(true),
		"completed_events": completed_events.duplicate(true),
		"failed_events": failed_events.duplicate(true),
	}

func _load_custom_save_data(data: Dictionary) -> void:
	current_day = int(data.get("current_day", current_day))
	current_hour = float(data.get("current_hour", current_hour))
	active_events = data.get("active_events", []).duplicate(true)
	completed_events = data.get("completed_events", {}).duplicate(true)
	failed_events = data.get("failed_events", {}).duplicate(true)

func _build_events_for_day(count: int) -> Array[Dictionary]:
	var picked: Array[Dictionary] = []
	var pool: Array[Dictionary] = EVENT_TEMPLATES.duplicate(true)
	_shuffle_events(pool)

	var target_count = clampi(count, 1, pool.size())
	for i in range(target_count):
		var event = pool[i].duplicate(true)
		event["state"] = "pending"
		var min_hour = float(event.get("deadline_min", 2.0))
		var max_hour = float(event.get("deadline_max", hours_per_day))
		event["deadline_hour"] = clampf(_rng.randf_range(min_hour, max_hour), 1.0, hours_per_day)
		picked.append(event)
	return picked

func _shuffle_events(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j = _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

func _apply_deadline_failures() -> void:
	for i in range(active_events.size()):
		var event = active_events[i]
		if String(event.get("state", "pending")) != "pending":
			continue

		var deadline = float(event.get("deadline_hour", hours_per_day))
		if current_hour < deadline:
			continue

		var penalty_delta = _normalize_delta_dict(event.get("penalty", {}))
		if _state_component != null:
			penalty_delta = _state_component.apply_delta(penalty_delta, "daily_event_penalty")

		var event_id = String(event.get("id", ""))
		event["state"] = "failed"
		event["resolved_hour"] = current_hour
		event["penalty_applied"] = penalty_delta
		active_events[i] = event
		failed_events[event_id] = true
		event_state_changed.emit(StringName(event_id), "failed", event.duplicate(true))

func _finish_day() -> void:
	var summary = {
		"day": current_day,
		"completed_count": completed_events.size(),
		"failed_count": failed_events.size(),
		"remaining_pending": get_pending_events().size(),
	}
	day_finished.emit(current_day, summary)

func _normalize_delta_dict(raw_delta: Variant) -> Dictionary:
	if raw_delta is not Dictionary:
		return {}

	var normalized = {}
	var delta_dict = raw_delta as Dictionary
	for key in ["hunger", "thirst", "mood", "favor"]:
		if delta_dict.has(key):
			normalized[key] = float(delta_dict[key])
	return normalized

func _contains_item(items: Array, normalized_item_id: String) -> bool:
	for entry in items:
		if String(entry).to_lower() == normalized_item_id:
			return true
	return false

func _extract_item_id(item_data: Resource) -> String:
	if item_data == null:
		return ""
	if item_data is ItemData:
		var path = String((item_data as ItemData).resource_path)
		if not path.is_empty():
			return path.get_file().get_basename().to_lower()

	# Fallback to resource name if the item is runtime-generated.
	var resource_name = String(item_data.resource_name).strip_edges().to_lower()
	return resource_name

func _find_state_component() -> XiaokongStateComponent:
	var parent_node = get_parent()
	if parent_node == null:
		return null

	for child in parent_node.get_children():
		var state = child as XiaokongStateComponent
		if state != null:
			return state

	return null
