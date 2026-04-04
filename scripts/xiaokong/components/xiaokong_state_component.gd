extends Node
class_name XiaokongStateComponent

signal stats_changed(snapshot: Dictionary, applied_delta: Dictionary, reason: String)
signal critical_state_changed(stat_name: StringName, is_critical: bool, value: float)

const STAT_KEYS: PackedStringArray = ["hunger", "thirst", "mood", "favor"]

@export_range(0, 100, 1) var initial_hunger: float = 45.0
@export_range(0, 100, 1) var initial_thirst: float = 40.0
@export_range(0, 100, 1) var initial_mood: float = 60.0
@export_range(0, 100, 1) var initial_favor: float = 20.0

@export_range(0, 100, 1) var min_stat_value: float = 0.0
@export_range(0, 100, 1) var max_stat_value: float = 100.0
@export_range(0, 100, 1) var need_critical_threshold: float = 20.0

@export_range(0, 20, 0.1) var hunger_decay_per_hour: float = 3.0
@export_range(0, 20, 0.1) var thirst_decay_per_hour: float = 4.0
@export_range(0, 20, 0.1) var mood_decay_when_hunger_critical: float = 2.0
@export_range(0, 20, 0.1) var mood_decay_when_thirst_critical: float = 3.0

var _stats: Dictionary = {}
var _critical_cache: Dictionary = {}

func _ready() -> void:
	_stats = {
		"hunger": initial_hunger,
		"thirst": initial_thirst,
		"mood": initial_mood,
		"favor": initial_favor,
	}
	_clamp_all_stats()
	_refresh_critical_cache(false)

func get_snapshot() -> Dictionary:
	return _stats.duplicate(true)

func build_ai_stats() -> Dictionary:
	return {
		"hunger": int(round(get_stat(&"hunger"))),
		"thirst": int(round(get_stat(&"thirst"))),
		"mood": int(round(get_stat(&"mood"))),
		"favor": int(round(get_stat(&"favor"))),
	}

func get_stat(stat_name: StringName) -> float:
	var key = String(stat_name)
	if not STAT_KEYS.has(key):
		return 0.0
	return float(_stats.get(key, 0.0))

func set_stat(stat_name: StringName, value: float, reason: String = "set_stat") -> float:
	var key = String(stat_name)
	if not STAT_KEYS.has(key):
		return 0.0

	var before = float(_stats.get(key, 0.0))
	var after = clampf(value, min_stat_value, max_stat_value)
	_stats[key] = after

	var real_delta = after - before
	if absf(real_delta) > 0.0001:
		var delta = {key: real_delta}
		_emit_state_update(delta, reason)

	return after

func apply_delta(delta: Dictionary, reason: String = "external") -> Dictionary:
	var applied = {}
	for key in STAT_KEYS:
		var requested_delta = _extract_delta(delta, key)
		if absf(requested_delta) <= 0.0001:
			continue

		var before = float(_stats.get(key, 0.0))
		var after = clampf(before + requested_delta, min_stat_value, max_stat_value)
		var real_delta = after - before
		if absf(real_delta) <= 0.0001:
			continue

		_stats[key] = after
		applied[key] = real_delta

	if not applied.is_empty():
		_emit_state_update(applied, reason)

	return applied

func tick_hours(hours: float) -> Dictionary:
	if hours <= 0.0:
		return {}

	var decay = {
		"hunger": -hunger_decay_per_hour * hours,
		"thirst": -thirst_decay_per_hour * hours,
	}

	if is_critical(&"hunger"):
		decay["mood"] = float(decay.get("mood", 0.0)) - mood_decay_when_hunger_critical * hours
	if is_critical(&"thirst"):
		decay["mood"] = float(decay.get("mood", 0.0)) - mood_decay_when_thirst_critical * hours

	return apply_delta(decay, "time_decay")

func is_critical(stat_name: StringName) -> bool:
	var key = String(stat_name)
	if key != "hunger" and key != "thirst":
		return false
	return get_stat(stat_name) <= need_critical_threshold

func _get_custom_save_data() -> Dictionary:
	return {
		"stats": get_snapshot(),
	}

func _load_custom_save_data(data: Dictionary) -> void:
	if not data.has("stats"):
		return
	var loaded_stats: Variant = data["stats"]
	if loaded_stats is not Dictionary:
		return

	for key in STAT_KEYS:
		if loaded_stats.has(key):
			_stats[key] = clampf(float(loaded_stats[key]), min_stat_value, max_stat_value)

	_emit_state_update({}, "load")

func _clamp_all_stats() -> void:
	for key in STAT_KEYS:
		_stats[key] = clampf(float(_stats.get(key, 0.0)), min_stat_value, max_stat_value)

func _extract_delta(delta: Dictionary, key: String) -> float:
	if delta.has(key):
		return float(delta[key])

	# Keep compatibility with old payload keys.
	if key == "hunger" and delta.has("ai_hunger"):
		return float(delta["ai_hunger"])
	if key == "mood" and delta.has("ai_mood"):
		return float(delta["ai_mood"])

	return 0.0

func _emit_state_update(applied_delta: Dictionary, reason: String) -> void:
	_refresh_critical_cache(true)
	stats_changed.emit(get_snapshot(), applied_delta, reason)

func _refresh_critical_cache(emit_changes: bool) -> void:
	var keys: PackedStringArray = ["hunger", "thirst"]
	for key in keys:
		var stat_name = StringName(key)
		var now_critical = is_critical(stat_name)
		var previous = bool(_critical_cache.get(key, now_critical))
		_critical_cache[key] = now_critical
		if emit_changes and previous != now_critical:
			critical_state_changed.emit(stat_name, now_critical, get_stat(stat_name))

