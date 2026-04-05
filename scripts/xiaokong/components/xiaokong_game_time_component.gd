extends Node
class_name XiaokongGameTimeComponent

signal day_started(day_index: int, current_hour: float)
signal hour_changed(day_index: int, current_hour: float, delta_hours: float, reason: String)
signal day_ended(day_index: int, summary: Dictionary)

@export var state_component_path: NodePath
@export var expedition_component_path: NodePath
@export var daily_director_path: NodePath

@export_range(1, 3650, 1) var initial_day: int = 1
@export_range(1.0, 48.0, 0.5) var day_length_hours: float = 16.0

@export var realtime_enabled: bool = false
@export_range(0.5, 600.0, 0.5) var seconds_per_game_hour: float = 30.0

@export_range(0.5, 12.0, 0.5) var default_stay_home_hours: float = 3.0
@export_range(0.5, 12.0, 0.5) var default_expedition_hours: float = 4.0

var current_day: int = 1
var current_hour: float = 0.0

var _realtime_accum: float = 0.0
var _initialized := false

var _state_component: XiaokongStateComponent
var _expedition_component: XiaokongExpeditionComponent
var _daily_director: XiaokongDailyDirectorComponent

func _ready() -> void:
	_refresh_refs()
	if not _initialized:
		current_day = maxi(1, initial_day)
		current_hour = clampf(current_hour, 0.0, day_length_hours)
		_initialize_day_context()
		_initialized = true
		day_started.emit(current_day, current_hour)
	set_process(realtime_enabled)

func _process(delta: float) -> void:
	if not realtime_enabled:
		return
	if seconds_per_game_hour <= 0.001:
		return

	_realtime_accum += delta
	if _realtime_accum < seconds_per_game_hour:
		return

	var hours = _realtime_accum / seconds_per_game_hour
	_realtime_accum = 0.0
	_advance_time(hours, "realtime", true)

func set_realtime_enabled(enabled: bool) -> void:
	realtime_enabled = enabled
	_realtime_accum = 0.0
	set_process(enabled)

func get_snapshot() -> Dictionary:
	return {
		"day": current_day,
		"hour": current_hour,
		"day_length_hours": day_length_hours,
	}

func get_clock_text() -> String:
	var hour_int = int(floor(current_hour))
	var minute_int = int(round((current_hour - float(hour_int)) * 60.0))
	if minute_int >= 60:
		minute_int -= 60
		hour_int += 1
	return "D%d %02d:%02d" % [current_day, hour_int, minute_int]

func pass_hours(hours: float, reason: String = "manual") -> Dictionary:
	return _advance_time(hours, reason, true)

func run_stay_home(hours: float = -1.0) -> Dictionary:
	_refresh_refs()
	var use_hours = default_stay_home_hours if hours <= 0.0 else hours
	var report = {
		"ok": true,
		"type": "stay_home",
		"hours": use_hours,
	}

	# stay_home_and_chat already applies state decay/bonus.
	var apply_state_decay = true
	if _expedition_component != null:
		report = _expedition_component.stay_home_and_chat(use_hours)
		apply_state_decay = false

	report["time"] = _advance_time(use_hours, "stay_home", apply_state_decay)
	return report

func run_expedition_with_fallback(player_prompt: String, risk_level: int = 1, hours: float = -1.0) -> Dictionary:
	_refresh_refs()
	if _expedition_component == null:
		return {"ok": false, "error": "expedition_component_not_found"}

	var use_hours = default_expedition_hours if hours <= 0.0 else hours
	var report = _expedition_component.run_expedition_with_fallback(player_prompt, risk_level)
	if bool(report.get("ok", false)):
		report["time"] = _advance_time(use_hours, "expedition", true)
	return report

func _advance_time(hours: float, reason: String, apply_state_decay: bool) -> Dictionary:
	var requested = maxf(hours, 0.0)
	if requested <= 0.0:
		return {
			"ok": true,
			"hours_passed": 0.0,
			"day": current_day,
			"hour": current_hour,
			"day_wrap_count": 0,
			"state_delta": {},
		}

	_refresh_refs()
	var remaining = requested
	var total_state_delta = {}
	var day_wrap_count = 0

	while remaining > 0.0001:
		var time_until_day_end = maxf(day_length_hours - current_hour, 0.0)
		if time_until_day_end <= 0.0001:
			_finish_day_and_roll(reason)
			day_wrap_count += 1
			continue

		var chunk = minf(remaining, time_until_day_end)
		if apply_state_decay and _state_component != null:
			total_state_delta = _merge_delta(total_state_delta, _state_component.tick_hours(chunk))

		if _daily_director != null:
			_daily_director.advance_hours(chunk)

		current_hour = minf(current_hour + chunk, day_length_hours)
		hour_changed.emit(current_day, current_hour, chunk, reason)
		remaining -= chunk

		if current_hour >= day_length_hours - 0.0001:
			_finish_day_and_roll(reason)
			day_wrap_count += 1

	return {
		"ok": true,
		"hours_passed": requested,
		"day": current_day,
		"hour": current_hour,
		"day_wrap_count": day_wrap_count,
		"state_delta": total_state_delta,
	}

func _finish_day_and_roll(reason: String) -> void:
	var ended_day = current_day
	var summary = {
		"day": ended_day,
		"end_hour": day_length_hours,
		"reason": reason,
	}
	day_ended.emit(ended_day, summary)

	current_day += 1
	current_hour = 0.0

	if _expedition_component != null:
		# start_new_day handles daily upkeep and expedition reset.
		_expedition_component.start_new_day(current_day)

	if _daily_director != null:
		_daily_director.hours_per_day = day_length_hours
		_daily_director.start_day(current_day)

	day_started.emit(current_day, current_hour)

func _initialize_day_context() -> void:
	if _expedition_component != null:
		_expedition_component.current_day = current_day

	if _daily_director != null:
		_daily_director.hours_per_day = day_length_hours
		if _daily_director.current_day <= 0:
			_daily_director.start_day(current_day)

func _refresh_refs() -> void:
	_state_component = get_node_or_null(state_component_path) as XiaokongStateComponent
	if _state_component == null:
		_state_component = _find_state_component()

	_expedition_component = get_node_or_null(expedition_component_path) as XiaokongExpeditionComponent
	if _expedition_component == null:
		_expedition_component = _find_expedition_component()

	_daily_director = null
	if daily_director_path != NodePath():
		_daily_director = get_node_or_null(daily_director_path) as XiaokongDailyDirectorComponent

func _find_state_component() -> XiaokongStateComponent:
	var parent_node = get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var state_component = child as XiaokongStateComponent
		if state_component != null:
			return state_component
	return null

func _find_expedition_component() -> XiaokongExpeditionComponent:
	var parent_node = get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var expedition_component = child as XiaokongExpeditionComponent
		if expedition_component != null:
			return expedition_component
	return null

func _merge_delta(first: Dictionary, second: Dictionary) -> Dictionary:
	var merged = first.duplicate(true)
	for key in second.keys():
		merged[key] = float(merged.get(key, 0.0)) + float(second[key])
	return merged

func _get_custom_save_data() -> Dictionary:
	return {
		"current_day": current_day,
		"current_hour": current_hour,
		"realtime_enabled": realtime_enabled,
	}

func _load_custom_save_data(data: Dictionary) -> void:
	current_day = maxi(1, int(data.get("current_day", current_day)))
	current_hour = clampf(float(data.get("current_hour", current_hour)), 0.0, day_length_hours)
	realtime_enabled = bool(data.get("realtime_enabled", realtime_enabled))
	_initialized = true
	_refresh_refs()
	if _expedition_component != null:
		_expedition_component.current_day = current_day
	if _daily_director != null:
		_daily_director.hours_per_day = day_length_hours
	_realtime_accum = 0.0
	set_process(realtime_enabled)
	day_started.emit(current_day, current_hour)
