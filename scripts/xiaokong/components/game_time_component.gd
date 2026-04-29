extends Node

signal day_started(day_index: int, current_hour: float)
signal hour_changed(day_index: int, current_hour: float, delta_hours: float, reason: String)
signal minute_changed(day_index: int, hour_24: int, minute: int, delta_minutes: int, reason: String)
signal day_ended(day_index: int, summary: Dictionary)

@export var state_component_path: NodePath
@export var expedition_component_path: NodePath
@export var daily_director_path: NodePath
@export var time_flow_profile: Resource

@export_range(1, 3650, 1) var initial_day: int = 1
@export_range(1.0, 48.0, 0.5) var day_length_hours: float = 24.0

@export var realtime_enabled: bool = false
@export_range(0.5, 600.0, 0.5) var seconds_per_game_hour: float = 30.0
@export_range(60.0, 7200.0, 1.0) var real_seconds_per_day: float = 600.0
@export_range(0, 23, 1) var sleep_morning_hour: int = 8

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
	_apply_time_profile_if_needed()
	_refresh_refs()
	if not _initialized:
		current_day = maxi(1, initial_day)
		current_hour = clampf(current_hour, 0.0, day_length_hours)
		_initialize_day_context()
		_initialized = true
		day_started.emit(current_day, current_hour)
		_emit_minute_changed("init", 0.0)
	set_process(realtime_enabled)

func _process(delta: float) -> void:
	if not realtime_enabled:
		return
	var day_seconds: float = maxf(real_seconds_per_day, 0.0)
	if day_seconds <= 0.001:
		return

	_realtime_accum += delta
	var seconds_per_game_minute: float = day_seconds / maxf(day_length_hours * 60.0, 1.0)
	if seconds_per_game_minute <= 0.001 or _realtime_accum < seconds_per_game_minute:
		return

	var passed_minutes: int = int(floor(_realtime_accum / seconds_per_game_minute))
	if passed_minutes <= 0:
		return
	_realtime_accum -= float(passed_minutes) * seconds_per_game_minute
	_advance_time(float(passed_minutes) / 60.0, "realtime", true)

func set_realtime_enabled(enabled: bool) -> void:
	realtime_enabled = enabled
	_realtime_accum = 0.0
	set_process(enabled)

func get_snapshot() -> Dictionary:
	var clock := _get_clock_parts()
	return {
		"day": current_day,
		"hour": current_hour,
		"hour_24": int(clock.get("hour", 0)),
		"minute": int(clock.get("minute", 0)),
		"day_length_hours": day_length_hours,
	}

func get_clock_text() -> String:
	var clock := _get_clock_parts()
	var hour_int: int = int(clock.get("hour", 0))
	var minute_int: int = int(clock.get("minute", 0))
	return "Day %d %02d:%02d" % [current_day, hour_int, minute_int]

func get_day_text() -> String:
	return "Day %d" % current_day

func get_time_text_24h() -> String:
	var clock := _get_clock_parts()
	return "%02d:%02d" % [int(clock.get("hour", 0)), int(clock.get("minute", 0))]

func get_day_time_text() -> String:
	return "%s %s" % [get_day_text(), get_time_text_24h()]

func get_day_progress_01() -> float:
	var day_hours := maxf(day_length_hours, 1.0)
	return clampf(fposmod(current_hour, day_hours) / day_hours, 0.0, 1.0)

func get_hour_24() -> int:
	return int(_get_clock_parts().get("hour", 0))

func get_minute() -> int:
	return int(_get_clock_parts().get("minute", 0))

func pass_hours(hours: float, reason: String = "manual") -> Dictionary:
	return _advance_time(hours, reason, true)

func pass_minutes(minutes: float, reason: String = "manual") -> Dictionary:
	return _advance_time(maxf(minutes, 0.0) / 60.0, reason, true)

func pass_days(days: int, reason: String = "manual") -> Dictionary:
	if days <= 0:
		return _advance_time(0.0, reason, true)
	return _advance_time(float(days) * day_length_hours, reason, true)

func skip_time_hours(hours: float, reason: String = "external_skip") -> Dictionary:
	return _advance_time(hours, reason, true)

func skip_time_minutes(minutes: float, reason: String = "external_skip") -> Dictionary:
	return pass_minutes(minutes, reason)

func skip_time_days(days: int, reason: String = "external_skip") -> Dictionary:
	return pass_days(days, reason)

func skip_sleep(hours: float = -1.0) -> Dictionary:
	var use_hours: float = hours
	if use_hours <= 0.0:
		use_hours = _calc_hours_until_next_morning()
	return _advance_time(use_hours, "sleep_skip", true)

func skip_repair(hours: float = 1.0) -> Dictionary:
	return _advance_time(maxf(hours, 0.0), "repair_skip", true)

func set_day_time(day_index: int, hour_24: int, minute: int, reason: String = "set_day_time") -> Dictionary:
	current_day = maxi(1, day_index)
	var safe_hour: int = clampi(hour_24, 0, 23)
	var safe_minute: int = clampi(minute, 0, 59)
	var hour_value: float = float(safe_hour) + float(safe_minute) / 60.0
	current_hour = clampf(hour_value, 0.0, maxf(day_length_hours - 0.0001, 0.0))
	_realtime_accum = 0.0
	_refresh_refs()
	_initialize_day_context()
	day_started.emit(current_day, current_hour)
	hour_changed.emit(current_day, current_hour, 0.0, reason)
	_emit_minute_changed(reason, 0.0)
	return {
		"ok": true,
		"day": current_day,
		"hour": current_hour,
		"hour_24": safe_hour,
		"minute": safe_minute,
		"reason": reason,
	}

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
		_emit_minute_changed(reason, chunk)
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
	_emit_minute_changed(reason, 0.0)

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

func _get_clock_parts() -> Dictionary:
	var wrapped_hour: float = fposmod(current_hour, maxf(day_length_hours, 1.0))
	var hour_int: int = int(floor(wrapped_hour))
	var minute_int: int = int(round((wrapped_hour - float(hour_int)) * 60.0))
	if minute_int >= 60:
		minute_int -= 60
		hour_int += 1
	var hour_limit: int = maxi(1, int(round(day_length_hours)))
	hour_int = int(posmod(hour_int, hour_limit))
	return {"hour": hour_int, "minute": minute_int}

func _emit_minute_changed(reason: String, delta_hours: float) -> void:
	var clock := _get_clock_parts()
	var hour_int: int = int(clock.get("hour", 0))
	var minute_int: int = int(clock.get("minute", 0))
	var delta_minutes: int = int(round(delta_hours * 60.0))
	minute_changed.emit(current_day, hour_int, minute_int, delta_minutes, reason)

func _calc_hours_until_next_morning() -> float:
	var morning: float = float(clampi(sleep_morning_hour, 0, 23))
	var clock := _get_clock_parts()
	var now_hour: float = float(clock.get("hour", 0)) + float(clock.get("minute", 0)) / 60.0
	if now_hour < morning:
		return morning - now_hour
	return maxf(day_length_hours - now_hour + morning, 0.0)

@warning_ignore("inference_on_variant")
func _apply_time_profile_if_needed() -> void:
	if time_flow_profile == null:
		return
	var profile: Resource = time_flow_profile
	var profile_day_length = profile.get("day_length_hours")
	if profile_day_length == null:
		profile_day_length = day_length_hours
	day_length_hours = clampf(float(profile_day_length), 1.0, 48.0)

	var profile_real_seconds = profile.get("real_seconds_per_day")
	if profile_real_seconds == null:
		profile_real_seconds = real_seconds_per_day
	real_seconds_per_day = maxf(float(profile_real_seconds), 60.0)

	seconds_per_game_hour = real_seconds_per_day / maxf(day_length_hours, 1.0)

	var profile_auto_tick = profile.get("auto_tick_enabled")
	if profile_auto_tick == null:
		profile_auto_tick = realtime_enabled
	realtime_enabled = bool(profile_auto_tick)

	var profile_morning_hour = profile.get("morning_hour")
	if profile_morning_hour == null:
		profile_morning_hour = sleep_morning_hour
	sleep_morning_hour = clampi(int(profile_morning_hour), 0, 23)

	if _initialized:
		return

	var profile_start_day = profile.get("start_day")
	if profile_start_day == null:
		profile_start_day = initial_day
	initial_day = maxi(1, int(profile_start_day))
	current_day = initial_day

	var profile_start_hour = profile.get("start_hour")
	if profile_start_hour == null:
		profile_start_hour = 8
	var start_hour: int = clampi(int(profile_start_hour), 0, 23)

	var profile_start_minute = profile.get("start_minute")
	if profile_start_minute == null:
		profile_start_minute = 0
	var start_minute: int = clampi(int(profile_start_minute), 0, 59)

	current_hour = clampf(float(start_hour) + float(start_minute) / 60.0, 0.0, day_length_hours)

func _get_custom_save_data() -> Dictionary:
	var clock := _get_clock_parts()
	return {
		"current_day": current_day,
		"current_hour": current_hour,
		"current_minute": int(clock.get("minute", 0)),
		"realtime_enabled": realtime_enabled,
	}

func _load_custom_save_data(data: Dictionary) -> void:
	current_day = maxi(1, int(data.get("current_day", current_day)))
	var loaded_hour: float = float(data.get("current_hour", current_hour))
	if data.has("current_minute"):
		var minute_value: int = clampi(int(data.get("current_minute", 0)), 0, 59)
		var hour_floor: int = clampi(int(floor(loaded_hour)), 0, 23)
		loaded_hour = float(hour_floor) + float(minute_value) / 60.0
	current_hour = clampf(loaded_hour, 0.0, day_length_hours)
	realtime_enabled = bool(data.get("realtime_enabled", realtime_enabled))
	_initialized = true
	_apply_time_profile_if_needed()
	_refresh_refs()
	if _expedition_component != null:
		_expedition_component.current_day = current_day
	if _daily_director != null:
		_daily_director.hours_per_day = day_length_hours
	_realtime_accum = 0.0
	set_process(realtime_enabled)
	day_started.emit(current_day, current_hour)
	_emit_minute_changed("load", 0.0)
