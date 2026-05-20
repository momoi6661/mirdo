extends Node
class_name CharacterResourceStateComponent

signal stats_changed(snapshot: Dictionary, applied_delta: Dictionary, reason: String)
signal critical_state_changed(stat_name: StringName, is_critical: bool, value: float)

const STAT_KEYS: PackedStringArray = ["health", "hunger", "thirst"]
const LEGACY_STAT_KEYS: PackedStringArray = ["mood", "favor"]
const SAVE_VERSION: int = 2

@export_category("Identity")
@export var character_id: StringName = &"character"
@export var display_name: String = "角色"

@export_category("Initial Stats")
@export_range(0, 100, 1) var initial_health: float = 100.0
@export_range(0, 100, 1) var initial_hunger: float = 65.0
@export_range(0, 100, 1) var initial_thirst: float = 60.0
# 旧 AI 组件仍可能读取 mood/favor，状态栏不显示，保存兼容用。
@export_range(0, 100, 1) var initial_mood: float = 70.0
@export_range(0, 100, 1) var initial_favor: float = 35.0

@export_category("Limits")
@export_range(0, 100, 1) var min_stat_value: float = 0.0
@export_range(0, 100, 1) var max_stat_value: float = 100.0
@export_range(0, 100, 1) var need_critical_threshold: float = 20.0
@export_range(0, 100, 1) var health_critical_threshold: float = 25.0

@export_category("Time Decay")
@export_range(0, 20, 0.1) var hunger_decay_per_hour: float = 2.0
@export_range(0, 20, 0.1) var thirst_decay_per_hour: float = 3.0
@export_range(0, 20, 0.1) var health_decay_when_hunger_critical: float = 1.0
@export_range(0, 20, 0.1) var health_decay_when_thirst_critical: float = 1.5
# 旧字段保留，避免旧场景属性丢失；新状态栏不使用。
@export_range(0, 20, 0.1) var mood_decay_when_hunger_critical: float = 1.2
@export_range(0, 20, 0.1) var mood_decay_when_thirst_critical: float = 1.8

var _stats: Dictionary = {}
var _legacy_stats: Dictionary = {}
var _critical_cache: Dictionary = {}


func _ready() -> void:
	if _stats.is_empty():
		_reset_to_initial_stats()
	_clamp_all_stats()
	_refresh_critical_cache(false)


func reset_to_initial(reason: String = "reset") -> void:
	_reset_to_initial_stats()
	_emit_state_update({}, reason)


func get_snapshot() -> Dictionary:
	var snapshot := _stats.duplicate(true)
	for key in LEGACY_STAT_KEYS:
		snapshot[key] = _legacy_stats.get(key, _default_legacy_value(key))
	snapshot["character_id"] = String(character_id)
	snapshot["display_name"] = display_name
	return snapshot


func build_ai_stats() -> Dictionary:
	return {
		"character_id": String(character_id),
		"display_name": display_name,
		"health": int(round(get_stat(&"health"))),
		"hunger": int(round(get_stat(&"hunger"))),
		"thirst": int(round(get_stat(&"thirst"))),
		"mood": int(round(float(_legacy_stats.get("mood", initial_mood)))),
		"favor": int(round(float(_legacy_stats.get("favor", initial_favor)))),
		"needs": build_need_summary(),
	}


func build_need_summary() -> String:
	var parts: PackedStringArray = []
	if is_critical(&"health"):
		parts.append("生命偏低，需要治疗")
	if is_critical(&"hunger"):
		parts.append("饥饿，需要食物")
	if is_critical(&"thirst"):
		parts.append("口渴，需要饮水")
	if parts.is_empty():
		parts.append("状态稳定")
	return "；".join(parts)


func get_stat(stat_name: StringName) -> float:
	var key := String(stat_name)
	if STAT_KEYS.has(key):
		return float(_stats.get(key, 0.0))
	if LEGACY_STAT_KEYS.has(key):
		return float(_legacy_stats.get(key, _default_legacy_value(key)))
	return 0.0


func set_stat(stat_name: StringName, value: float, reason: String = "set_stat") -> float:
	var key := String(stat_name)
	if LEGACY_STAT_KEYS.has(key):
		_legacy_stats[key] = clampf(value, min_stat_value, max_stat_value)
		return float(_legacy_stats[key])
	if not STAT_KEYS.has(key):
		return 0.0
	var before := float(_stats.get(key, 0.0))
	var after := clampf(value, min_stat_value, max_stat_value)
	_stats[key] = after
	var real_delta := after - before
	if absf(real_delta) > 0.0001:
		_emit_state_update({key: real_delta}, reason)
	return after


func apply_delta(delta: Dictionary, reason: String = "external") -> Dictionary:
	var applied := {}
	for key in STAT_KEYS:
		var requested_delta := _extract_delta(delta, key)
		if absf(requested_delta) <= 0.0001:
			continue
		var before := float(_stats.get(key, 0.0))
		var after := clampf(before + requested_delta, min_stat_value, max_stat_value)
		var real_delta := after - before
		if absf(real_delta) <= 0.0001:
			continue
		_stats[key] = after
		applied[key] = real_delta
	# 兼容旧 AI 修改 mood/favor，但不进入状态栏。
	for key in LEGACY_STAT_KEYS:
		var legacy_delta := _extract_delta(delta, key)
		if absf(legacy_delta) <= 0.0001:
			continue
		_legacy_stats[key] = clampf(float(_legacy_stats.get(key, _default_legacy_value(key))) + legacy_delta, min_stat_value, max_stat_value)
	if not applied.is_empty():
		_emit_state_update(applied, reason)
	return applied


func apply_outing_cost(hunger_cost: float, thirst_cost: float, health_damage: float, reason: String = "outing") -> Dictionary:
	return apply_delta({
		"hunger": -absf(hunger_cost),
		"thirst": -absf(thirst_cost),
		"health": -absf(health_damage),
	}, reason)


func apply_item_effect(item: ItemData, reason: String = "use_item") -> Dictionary:
	if item == null:
		return {}
	var delta := item.get_consumable_delta()
	if delta.is_empty():
		return {}
	return apply_delta(delta, reason)


func tick_hours(hours: float) -> Dictionary:
	if hours <= 0.0:
		return {}
	var decay := {
		"hunger": -hunger_decay_per_hour * hours,
		"thirst": -thirst_decay_per_hour * hours,
	}
	if is_critical(&"hunger"):
		decay["health"] = float(decay.get("health", 0.0)) - health_decay_when_hunger_critical * hours
	if is_critical(&"thirst"):
		decay["health"] = float(decay.get("health", 0.0)) - health_decay_when_thirst_critical * hours
	return apply_delta(decay, "time_decay")


func is_critical(stat_name: StringName) -> bool:
	var key := String(stat_name)
	if key == "health":
		return get_stat(stat_name) <= health_critical_threshold
	if key == "hunger" or key == "thirst":
		return get_stat(stat_name) <= need_critical_threshold
	return false


func _get_custom_save_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"character_id": String(character_id),
		"display_name": display_name,
		"stats": _stats.duplicate(true),
		"legacy_stats": _legacy_stats.duplicate(true),
	}


func _load_custom_save_data(data: Dictionary) -> void:
	if data.has("character_id"):
		character_id = StringName(String(data.get("character_id", String(character_id))))
	if data.has("display_name"):
		display_name = String(data.get("display_name", display_name))
	if _stats.is_empty():
		_reset_to_initial_stats()
	var loaded_stats: Variant = data.get("stats", {})
	if loaded_stats is Dictionary:
		for key in STAT_KEYS:
			if loaded_stats.has(key):
				_stats[key] = clampf(float(loaded_stats[key]), min_stat_value, max_stat_value)
		# 旧存档没有 health 时自动补满，避免读档直接 0 血。
		if not loaded_stats.has("health"):
			_stats["health"] = initial_health
		for key in LEGACY_STAT_KEYS:
			if loaded_stats.has(key):
				_legacy_stats[key] = clampf(float(loaded_stats[key]), min_stat_value, max_stat_value)
	var legacy_loaded: Variant = data.get("legacy_stats", {})
	if legacy_loaded is Dictionary:
		for key in LEGACY_STAT_KEYS:
			if legacy_loaded.has(key):
				_legacy_stats[key] = clampf(float(legacy_loaded[key]), min_stat_value, max_stat_value)
	_emit_state_update({}, "load")


func _reset_to_initial_stats() -> void:
	_stats = {
		"health": initial_health,
		"hunger": initial_hunger,
		"thirst": initial_thirst,
	}
	_legacy_stats = {
		"mood": initial_mood,
		"favor": initial_favor,
	}


func _clamp_all_stats() -> void:
	if _stats.is_empty():
		_reset_to_initial_stats()
	for key in STAT_KEYS:
		if not _stats.has(key):
			_stats[key] = _default_stat_value(key)
		_stats[key] = clampf(float(_stats.get(key, 0.0)), min_stat_value, max_stat_value)
	for key in LEGACY_STAT_KEYS:
		if not _legacy_stats.has(key):
			_legacy_stats[key] = _default_legacy_value(key)
		_legacy_stats[key] = clampf(float(_legacy_stats.get(key, 0.0)), min_stat_value, max_stat_value)


func _default_stat_value(key: String) -> float:
	match key:
		"health": return initial_health
		"hunger": return initial_hunger
		"thirst": return initial_thirst
		_: return 0.0


func _default_legacy_value(key: String) -> float:
	match key:
		"mood": return initial_mood
		"favor": return initial_favor
		_: return 0.0


func _extract_delta(delta: Dictionary, key: String) -> float:
	if delta.has(key):
		return float(delta[key])
	if key == "health" and delta.has("ai_health"):
		return float(delta["ai_health"])
	if key == "hunger" and delta.has("ai_hunger"):
		return float(delta["ai_hunger"])
	if key == "thirst" and delta.has("ai_thirst"):
		return float(delta["ai_thirst"])
	if key == "mood" and delta.has("ai_mood"):
		return float(delta["ai_mood"])
	if key == "favor" and delta.has("ai_favor"):
		return float(delta["ai_favor"])
	return 0.0


func _emit_state_update(applied_delta: Dictionary, reason: String) -> void:
	_refresh_critical_cache(true)
	stats_changed.emit(get_snapshot(), applied_delta, reason)


func _refresh_critical_cache(emit_changes: bool) -> void:
	for key in STAT_KEYS:
		var stat_name := StringName(key)
		var now_critical := is_critical(stat_name)
		var previous := bool(_critical_cache.get(key, now_critical))
		_critical_cache[key] = now_critical
		if emit_changes and previous != now_critical:
			critical_state_changed.emit(stat_name, now_critical, get_stat(stat_name))
