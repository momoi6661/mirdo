extends Node
class_name CharacterSituationBehaviorPackComponent

@export_range(0.0, 1.0, 0.01) var teacher_attention_gaze_threshold: float = 0.75
@export_range(0.0, 100.0, 1.0) var tired_energy_threshold: float = 35.0
@export_range(0.0, 1.0, 0.01) var tiredness_threshold: float = 0.62
@export_range(0.0, 1.0, 0.01) var boredom_threshold: float = 0.68
@export_range(0.0, 1.0, 0.01) var curiosity_threshold: float = 0.45
@export_range(0.0, 100.0, 1.0) var hungry_threshold: float = 38.0
@export_range(0.0, 100.0, 1.0) var thirsty_threshold: float = 42.0
@export_range(0.0, 100.0, 1.0) var low_mood_threshold: float = 35.0
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
		"preferred_action_tags": _merge_array_field(active, "preferred_action_tags"),
		"avoid_action_tags": _merge_array_field(active, "avoid_action_tags"),
		"expression_bias": _merge_array_field(active, "expression_bias"),
		"decision_bias": _merge_bias_dict(active),
	}

func _build_candidate_packs(snapshot: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var awareness := _dict(snapshot.get("player_awareness", {}))
	var mind := _dict(snapshot.get("mind_state", {}))
	var resources := _dict(snapshot.get("resource_stats", {}))
	var behavior := _dict(snapshot.get("current_behavior", {}))
	var hunger := float(resources.get("hunger", 65.0))
	var thirst := float(resources.get("thirst", 60.0))
	var mood := float(resources.get("mood", 55.0))
	var current_kind := String(behavior.get("current_kind", "")).strip_edges()
	var external_grace := float(behavior.get("external_grace_left", 0.0))
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
			"preferred_action_tags": ["teacher", "social", "greeting", "cute"],
			"avoid_action_tags": ["rest", "tired"],
			"expression_bias": ["joy", "fun"],
			"decision_bias": {"look_at_player": 0.65, "ambient": 0.18, "go_to_nav_point": 0.05},
			"description": "老师正在靠近或注视 Mirdo，优先做软社交回应。",
		})
	if external_grace > 0.0 or current_kind in ["dialogue", "talk"]:
		out.append({
			"id": "player_talking",
			"score": 0.82 + clampf(external_grace / 8.0, 0.0, 0.22),
			"priority_tags": ["teacher", "social"],
			"avoid_tags": ["wander", "rest"],
			"action_bias": ["listen", "small_nod", "cute_explain", "tilt_head_cute"],
			"preferred_action_tags": ["teacher", "listen", "talk", "social"],
			"avoid_action_tags": ["move", "rest"],
			"expression_bias": ["neutral", "joy", "fun"],
			"decision_bias": {"look_at_player": 0.72, "ambient": 0.22, "go_to_nav_point": -0.18},
			"description": "老师正在对话或外部控制刚发生，暂停自主游走并专注互动。",
		})
	var hunger_need := maxf(0.0, (hungry_threshold - hunger) / maxf(1.0, hungry_threshold))
	if hunger_need > 0.0:
		out.append({
			"id": "hungry_supply",
			"score": 0.45 + hunger_need * 1.25,
			"priority_tags": ["food", "supplies", "storage", "cabinet"],
			"avoid_tags": ["rest", "debug"],
			"action_bias": ["work_count_supplies", "work_take_item", "work_drink", "small_happy_bounce"],
			"preferred_action_tags": ["food", "supplies", "take_item", "eat", "use_item"],
			"avoid_action_tags": ["tired", "rest"],
			"expression_bias": ["neutral", "fun", "joy"],
			"decision_bias": {"go_to_nav_point": 0.85, "go_to_object": 0.65, "ambient": -0.16},
			"description": "饥饿偏低，优先找食物柜并拿取/使用食物。",
		})
	var thirst_need := maxf(0.0, (thirsty_threshold - thirst) / maxf(1.0, thirsty_threshold))
	if thirst_need > 0.0:
		out.append({
			"id": "thirsty_supply",
			"score": 0.48 + thirst_need * 1.35,
			"priority_tags": ["water", "drink", "supplies", "food", "storage"],
			"avoid_tags": ["rest", "debug"],
			"action_bias": ["work_count_supplies", "work_take_item", "work_drink"],
			"preferred_action_tags": ["water", "drink", "take_item", "use_item"],
			"avoid_action_tags": ["tired", "rest"],
			"expression_bias": ["neutral", "fun", "joy"],
			"decision_bias": {"go_to_nav_point": 0.92, "go_to_object": 0.70, "ambient": -0.18},
			"description": "口渴偏低，优先找水/补给并饮用。",
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
			"preferred_action_tags": ["tired", "rest", "sleepy", "seat"],
			"avoid_action_tags": ["work", "fast", "run"],
			"expression_bias": ["sorrow", "neutral"],
			"decision_bias": {"go_to_nav_point": 0.28, "go_to_object": 0.45, "ambient": 0.20},
			"description": "精力低或困倦，倾向休息或困倦动作。",
		})
	var comfort_rest_score := maxf(0.0, tiredness - 0.38) * 0.45 + maxf(0.0, (55.0 - energy) / 55.0) * 0.38
	if comfort_rest_score > 0.12 and tired_score <= 0.0:
		out.append({
			"id": "comfort_rest",
			"score": comfort_rest_score,
			"priority_tags": ["seat", "rest", "idle"],
			"avoid_tags": ["work", "run"],
			"action_bias": ["seated_idle", "rub_eye", "small_nod"],
			"preferred_action_tags": ["seat", "idle", "rest"],
			"avoid_action_tags": ["fast", "work"],
			"expression_bias": ["neutral", "sorrow"],
			"decision_bias": {"go_to_nav_point": 0.18, "ambient": 0.16},
			"description": "有点累但不是强制睡觉，倾向自然坐下休息一会。",
		})
	var low_mood_score := maxf(0.0, (low_mood_threshold - mood) / maxf(1.0, low_mood_threshold)) + maxf(0.0, float(mind.get("boredom", 0.0)) - 0.72) * 0.35
	if low_mood_score > 0.0:
		out.append({
			"id": "low_mood_comfort",
			"score": 0.35 + low_mood_score,
			"priority_tags": ["quiet", "corner", "rest", "teacher"],
			"avoid_tags": ["work", "run"],
			"action_bias": ["rub_eye", "small_nod", "tilt_head_cute", "listen"],
			"preferred_action_tags": ["tired", "teacher", "listen", "cute"],
			"avoid_action_tags": ["happy", "fast"],
			"expression_bias": ["sorrow", "neutral", "disappointed"],
			"decision_bias": {"ambient": 0.28, "look_at_player": 0.18, "go_to_nav_point": 0.10},
			"description": "心情偏低，动作更轻，倾向安静和需要安慰的反应。",
		})
	var playful_score := float(mind.get("social", 0.0)) * 0.45 + maxf(0.0, mood - 62.0) / 100.0 + gaze_score * 0.28
	if playful_score > 0.38 and energy > tired_energy_threshold and mood >= low_mood_threshold:
		out.append({
			"id": "playful_social",
			"score": playful_score,
			"priority_tags": ["teacher", "social", "idle"],
			"avoid_tags": ["rest"],
			"action_bias": ["tiny_wave", "small_wave", "tilt_head_cute", "small_happy_bounce", "idle_fidget"],
			"preferred_action_tags": ["cute", "happy", "social", "greeting"],
			"avoid_action_tags": ["tired", "work"],
			"expression_bias": ["joy", "fun"],
			"decision_bias": {"look_at_player": 0.26, "ambient": 0.32, "go_to_nav_point": 0.04},
			"description": "心情好且玩家在附近，主动做一点可爱的轻社交。",
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
			"preferred_action_tags": ["wander", "look", "curious", "ambient"],
			"avoid_action_tags": ["rest", "use_item"],
			"expression_bias": ["neutral", "fun"],
			"decision_bias": {"go_to_nav_point": 0.55, "ambient": 0.22},
			"description": "无聊且还有精力，倾向闲逛和观察小球。",
		})
	if curiosity > curiosity_threshold and energy > tired_energy_threshold:
		out.append({
			"id": "curious_object",
			"score": maxf(0.0, curiosity - curiosity_threshold) * 0.8 + float(mind.get("duty", 0.0)) * 0.18,
			"priority_tags": ["inspect", "look", "cabinet", "equipment", "medical", "tool", "storage"],
			"avoid_tags": ["rest", "debug"],
			"action_bias": ["look_around", "curious_peek", "work_inspect_cabinet", "work_check_lower"],
			"preferred_action_tags": ["inspect", "look", "curious"],
			"avoid_action_tags": ["rest", "tired"],
			"expression_bias": ["neutral", "fun"],
			"decision_bias": {"go_to_nav_point": 0.38, "go_to_object": 0.35, "ambient": 0.10},
			"description": "好奇心上升，优先观察带语义的小球或设施。",
		})
	var block_reason := String(behavior.get("block_reason", "")).strip_edges().to_lower()
	if block_reason.find("navigation") >= 0 or block_reason.find("blocked") >= 0 or block_reason.find("stuck") >= 0:
		out.append({
			"id": "door_or_path_blocked",
			"score": 0.88,
			"priority_tags": ["door", "stand", "route", "look"],
			"avoid_tags": ["seat", "rest"],
			"action_bias": ["look_around", "curious_peek", "small_nod"],
			"preferred_action_tags": ["look", "caution", "blocked"],
			"avoid_action_tags": ["seat", "rest", "fast"],
			"expression_bias": ["neutral", "surprised", "sorrow"],
			"decision_bias": {"ambient": 0.32, "go_to_nav_point": 0.18, "go_to_object": -0.10},
			"description": "导航或路径可能被门/障碍影响，先观察和恢复，不反复硬挤。",
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
