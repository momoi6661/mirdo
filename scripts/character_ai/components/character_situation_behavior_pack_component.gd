extends Node
class_name CharacterSituationBehaviorPackComponent

@export_range(0.0, 1.0, 0.01) var teacher_attention_gaze_threshold: float = 0.75
@export_range(0.0, 100.0, 1.0) var tired_energy_threshold: float = 35.0
@export_range(0.0, 1.0, 0.01) var tiredness_threshold: float = 0.62
@export_range(0.0, 1.0, 0.01) var boredom_threshold: float = 0.68
@export_range(0.0, 1.0, 0.01) var curiosity_threshold: float = 0.45
@export var extra_packs: Array[Dictionary] = []

func evaluate_situations(blackboard_snapshot: Dictionary) -> Dictionary:
	var packs := _build_candidate_packs(blackboard_snapshot)
	for extra in extra_packs:
		if extra is Dictionary:
			packs.append((extra as Dictionary).duplicate(true))
	if packs.is_empty():
		return _empty_context()
	packs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
	)
	var active: Array[Dictionary] = []
	for pack in packs:
		if float(pack.get("score", 0.0)) > 0.01:
			active.append(pack.duplicate(true))
	var primary := active[0] if not active.is_empty() else {}
	return {
		"primary_pack": String(primary.get("id", "")),
		"primary_score": float(primary.get("score", 0.0)),
		"active_packs": active,
		"priority_tags": _merge_array_field(active, "priority_tags"),
		"avoid_tags": _merge_array_field(active, "avoid_tags"),
		"action_bias": _merge_array_field(active, "action_bias"),
		"expression_bias": _merge_array_field(active, "expression_bias"),
		"decision_bias": _merge_bias_dict(active),
	}

func _build_candidate_packs(snapshot: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var awareness := _dict(snapshot.get("player_awareness", {}))
	var mind := _dict(snapshot.get("mind_state", {}))
	var resources := _dict(snapshot.get("resource_stats", {}))
	var gaze_score := 0.0
	if bool(awareness.get("gaze_active", false)):
		gaze_score += 0.65
	if bool(awareness.get("near", false)):
		gaze_score += 0.18
	if bool(awareness.get("very_close", false)):
		gaze_score += 0.12
	gaze_score += clampf(float(awareness.get("gaze_time", 0.0)) / 4.0, 0.0, 0.25)
	if gaze_score >= teacher_attention_gaze_threshold:
		out.append({
			"id": "teacher_attention",
			"score": gaze_score + float(mind.get("social", 0.0)) * 0.25,
			"priority_tags": ["teacher", "social"],
			"avoid_tags": ["rest"],
			"action_bias": ["tiny_wave", "small_wave", "small_nod", "cute_explain", "tilt_head_cute", "listen"],
			"expression_bias": ["joy", "fun"],
			"decision_bias": {"look_at_player": 0.65, "ambient": 0.18, "go_to_nav_point": 0.05},
			"description": "老师正在靠近或注视 Mirdo，优先做软社交回应。",
		})
	var energy := float(resources.get("energy", 70.0))
	var tiredness := float(mind.get("tiredness", 0.0))
	var tired_score := maxf(0.0, (tired_energy_threshold - energy) / maxf(1.0, tired_energy_threshold)) + maxf(0.0, tiredness - tiredness_threshold) * 1.6
	if tired_score > 0.0:
		out.append({
			"id": "tired_rest",
			"score": tired_score,
			"priority_tags": ["rest", "seat", "bed"],
			"avoid_tags": ["work", "run"],
			"action_bias": ["rub_eye", "sleepy_yawn", "seated_sleepy", "seated_idle"],
			"expression_bias": ["sorrow", "neutral"],
			"decision_bias": {"go_to_nav_point": 0.28, "go_to_object": 0.45, "ambient": 0.20},
			"description": "精力低或困倦，倾向休息或困倦动作。",
		})
	var boredom := float(mind.get("boredom", 0.0))
	var curiosity := float(mind.get("curiosity", 0.0))
	var bored_score := maxf(0.0, boredom - boredom_threshold) + maxf(0.0, curiosity - curiosity_threshold) * 0.45
	if bored_score > 0.0 and energy > tired_energy_threshold:
		out.append({
			"id": "bored_wander",
			"score": bored_score,
			"priority_tags": ["wander", "idle", "look", "corner", "route"],
			"avoid_tags": [],
			"action_bias": ["look_around", "curious_peek", "idle_fidget", "look_back", "tilt_head_cute"],
			"expression_bias": ["neutral", "fun"],
			"decision_bias": {"go_to_nav_point": 0.55, "ambient": 0.22},
			"description": "无聊且还有精力，倾向闲逛和观察小球。",
		})
	return out

func _empty_context() -> Dictionary:
	return {
		"primary_pack": "",
		"primary_score": 0.0,
		"active_packs": [],
		"priority_tags": [],
		"avoid_tags": [],
		"action_bias": [],
		"expression_bias": [],
		"decision_bias": {},
	}

func _dict(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}

func _merge_array_field(packs: Array[Dictionary], field_name: String) -> Array:
	var result: Array = []
	for pack in packs:
		var value: Variant = pack.get(field_name, [])
		if value is Array or value is PackedStringArray:
			for entry in value:
				var text := String(entry).strip_edges()
				if not text.is_empty() and not result.has(text):
					result.append(text)
	return result

func _merge_bias_dict(packs: Array[Dictionary]) -> Dictionary:
	var result := {}
	for pack in packs:
		var value: Variant = pack.get("decision_bias", {})
		if value is not Dictionary:
			continue
		for key in (value as Dictionary).keys():
			var text := String(key).strip_edges()
			if text.is_empty():
				continue
			result[text] = float(result.get(text, 0.0)) + float((value as Dictionary)[key])
	return result
