extends Node
class_name CharacterMindStateComponent

signal state_changed(snapshot: Dictionary)
signal high_level_intent_changed(intent: Dictionary)

@export var enabled: bool = true
@export_range(0.0, 1.0, 0.01) var curiosity: float = 0.45
@export_range(0.0, 1.0, 0.01) var tiredness: float = 0.18
@export_range(0.0, 1.0, 0.01) var boredom: float = 0.28
@export_range(0.0, 1.0, 0.01) var social: float = 0.35
@export_range(0.0, 1.0, 0.01) var duty: float = 0.38
@export_range(0.0, 1.0, 0.01) var caution: float = 0.12

@export_category("Drift Per Second")
@export_range(0.0, 0.2, 0.001) var curiosity_drift: float = 0.004
@export_range(0.0, 0.2, 0.001) var tiredness_drift: float = 0.002
@export_range(0.0, 0.2, 0.001) var boredom_drift: float = 0.006
@export_range(0.0, 0.2, 0.001) var social_decay: float = 0.002
@export_range(0.0, 0.2, 0.001) var duty_drift: float = 0.002
@export_range(0.0, 0.2, 0.001) var caution_decay: float = 0.004
@export_range(0.0, 1.0, 0.01) var low_energy_tiredness_gain: float = 0.18
@export_range(0.0, 1.0, 0.01) var low_mood_boredom_gain: float = 0.08

@export_category("High Level Intent")
@export_range(0.0, 300.0, 0.1) var default_intent_duration_sec: float = 60.0

var _high_level_intent: Dictionary = {}
var _intent_time_left: float = 0.0
var _last_snapshot: Dictionary = {}

func _ready() -> void:
	_last_snapshot = get_state_snapshot()
	set_process(true)

func _process(delta: float) -> void:
	if not enabled:
		return
	_update_intent(delta)
	_drift(delta)
	_emit_if_changed()

func get_state_snapshot() -> Dictionary:
	return {
		"curiosity": curiosity,
		"tiredness": tiredness,
		"boredom": boredom,
		"social": social,
		"duty": duty,
		"caution": caution,
		"high_level_intent": _high_level_intent.duplicate(true),
		"intent_time_left": _intent_time_left,
	}

func apply_behavior_feedback(behavior_kind: String, data: Dictionary = {}) -> void:
	match behavior_kind:
		"inspect", "go_inspect_object", "go_count_supplies", "go_check_medical", "go_check_lower":
			curiosity = _clamp01(curiosity - 0.22)
			duty = _clamp01(duty - 0.16)
			boredom = _clamp01(boredom - 0.12)
		"ambient", "idle_fidget", "look_around", "curious_peek", "tilt_head_cute":
			boredom = _clamp01(boredom - 0.18)
			curiosity = _clamp01(curiosity - 0.05)
		"look_at_player", "small_wave", "tiny_wave", "react_wave":
			social = _clamp01(social - 0.20)
			boredom = _clamp01(boredom - 0.08)
		"sit", "sit_down", "seated_idle":
			tiredness = _clamp01(tiredness - 0.25)
			boredom = _clamp01(boredom - 0.08)
		"rub_eye", "sleepy_yawn":
			tiredness = _clamp01(tiredness - 0.14)
		"external_ai", "dialogue":
			social = _clamp01(social + 0.08)
			boredom = _clamp01(boredom - 0.10)
		"real_outing_return_greeting":
			social = _clamp01(social + 0.12)
			boredom = _clamp01(boredom - 0.12)
			curiosity = _clamp01(curiosity + 0.06)
			caution = _clamp01(caution - 0.04)
		"fed", "ate", "drink", "treated", "consume_item", "inventory_use":
			social = _clamp01(social + 0.18)
			boredom = _clamp01(boredom - 0.18)
			tiredness = _clamp01(tiredness - 0.04)
			duty = _clamp01(duty - 0.06)
			curiosity = _clamp01(curiosity - 0.04)
	if data.has("state_delta") and data["state_delta"] is Dictionary:
		apply_state_delta(data["state_delta"] as Dictionary)
	_emit_if_changed(true)

func apply_perception_hint(snapshot: Dictionary) -> void:
	var objects: Variant = snapshot.get("nearby_objects", [])
	if objects is not Array:
		return
	var has_supplies := false
	var has_social := false
	var has_unknown := false
	for value in objects:
		if value is not Dictionary:
			continue
		var entry := value as Dictionary
		var tags: Variant = entry.get("tags", [])
		var tag_text := _tags_to_text(tags)
		if tag_text.find("food") >= 0 or tag_text.find("medical") >= 0 or tag_text.find("supplies") >= 0 or tag_text.find("equipment") >= 0:
			has_supplies = true
		if tag_text.find("player") >= 0 or tag_text.find("social") >= 0:
			has_social = true
		if tag_text.find("unknown") >= 0 or tag_text.find("danger") >= 0:
			has_unknown = true
	if has_supplies:
		curiosity = _clamp01(curiosity + 0.015)
		duty = _clamp01(duty + 0.012)
	if has_social:
		social = _clamp01(social + 0.015)
	if has_unknown:
		caution = _clamp01(caution + 0.025)
	_emit_if_changed()

func apply_state_delta(delta: Dictionary) -> void:
	if delta.has("energy") or delta.has("ai_energy"):
		tiredness = _clamp01(tiredness - float(delta.get("energy", delta.get("ai_energy", 0.0))) / 100.0)
	if delta.has("mood") or delta.has("ai_mood"):
		boredom = _clamp01(boredom - float(delta.get("mood", delta.get("ai_mood", 0.0))) / 120.0)
	if delta.has("favor") or delta.has("ai_favor"):
		social = _clamp01(social + float(delta.get("favor", delta.get("ai_favor", 0.0))) / 120.0)
	curiosity = _clamp01(curiosity + float(delta.get("curiosity", 0.0)))
	tiredness = _clamp01(tiredness + float(delta.get("tiredness", 0.0)))
	boredom = _clamp01(boredom + float(delta.get("boredom", 0.0)))
	social = _clamp01(social + float(delta.get("social", 0.0)))
	duty = _clamp01(duty + float(delta.get("duty", 0.0)))
	caution = _clamp01(caution + float(delta.get("caution", 0.0)))
	_emit_if_changed(true)

func apply_high_level_intent(intent: Dictionary) -> void:
	_high_level_intent = intent.duplicate(true)
	_intent_time_left = float(intent.get("duration_sec", default_intent_duration_sec))
	var bias: Variant = intent.get("state_bias", {})
	if bias is Dictionary:
		apply_state_delta(bias as Dictionary)
	high_level_intent_changed.emit(_high_level_intent.duplicate(true))
	_emit_if_changed(true)

func clear_high_level_intent() -> void:
	_high_level_intent = {}
	_intent_time_left = 0.0
	high_level_intent_changed.emit({})
	_emit_if_changed(true)

func apply_resource_snapshot(snapshot: Dictionary) -> void:
	var energy := float(snapshot.get("energy", 70.0))
	var mood := float(snapshot.get("mood", 55.0))
	if energy < 35.0:
		tiredness = _clamp01(tiredness + low_energy_tiredness_gain * (1.0 - energy / 35.0))
	if mood < 35.0:
		boredom = _clamp01(boredom + low_mood_boredom_gain * (1.0 - mood / 35.0))
	_emit_if_changed(true)

func _drift(delta: float) -> void:
	curiosity = _clamp01(curiosity + curiosity_drift * delta)
	tiredness = _clamp01(tiredness + tiredness_drift * delta)
	boredom = _clamp01(boredom + boredom_drift * delta)
	social = _clamp01(social - social_decay * delta)
	duty = _clamp01(duty + duty_drift * delta)
	caution = _clamp01(caution - caution_decay * delta)

func _update_intent(delta: float) -> void:
	if _intent_time_left <= 0.0:
		return
	_intent_time_left = maxf(0.0, _intent_time_left - delta)
	if _intent_time_left <= 0.0:
		clear_high_level_intent()

func _emit_if_changed(force: bool = false) -> void:
	var now := get_state_snapshot()
	if force or _snapshot_distance(_last_snapshot, now) > 0.05:
		_last_snapshot = now.duplicate(true)
		state_changed.emit(now)

func _snapshot_distance(a: Dictionary, b: Dictionary) -> float:
	var total := 0.0
	for key in ["curiosity", "tiredness", "boredom", "social", "duty", "caution"]:
		total += absf(float(a.get(key, 0.0)) - float(b.get(key, 0.0)))
	return total

func _tags_to_text(tags: Variant) -> String:
	var out := ""
	if tags is Array or tags is PackedStringArray:
		for tag in tags:
			out += String(tag).to_lower() + ","
	return out

func _clamp01(value: float) -> float:
	return clampf(value, 0.0, 1.0)
