extends Node
class_name CharacterActionSemanticsComponent

@export var extra_action_semantics: Dictionary = {}
@export var extra_context_actions: Dictionary = {}

var _action_table: Dictionary = {}
var _context_actions: Dictionary = {}

func _ready() -> void:
	_rebuild_tables()

func get_action_semantics(action_name: StringName) -> Dictionary:
	if _action_table.is_empty():
		_rebuild_tables()
	var key := String(action_name).strip_edges()
	if key.is_empty():
		return {}
	if _action_table.has(key):
		return (_action_table[key] as Dictionary).duplicate(true)
	return _default_semantics_for(key)

func get_all_action_semantics() -> Dictionary:
	if _action_table.is_empty():
		_rebuild_tables()
	return _action_table.duplicate(true)

func get_actions_for_context(context_name: String) -> Array:
	if _context_actions.is_empty():
		_rebuild_tables()
	var key := context_name.strip_edges().to_lower()
	var value: Variant = _context_actions.get(key, [])
	return _variant_to_string_array(value)

func get_actions_matching_tags(preferred_tags: Variant = [], avoid_tags: Variant = [], posture: String = "", include_unknown: bool = false) -> Array[Dictionary]:
	if _action_table.is_empty():
		_rebuild_tables()
	var preferred := _variant_to_lower_string_array(preferred_tags)
	var avoided := _variant_to_lower_string_array(avoid_tags)
	var wanted_posture := posture.strip_edges().to_lower()
	var result: Array[Dictionary] = []
	for action_name in _action_table.keys():
		var semantics := get_action_semantics(StringName(String(action_name)))
		if semantics.is_empty():
			continue
		if not include_unknown and String(semantics.get("category", "")).strip_edges().to_lower() == "unknown":
			continue
		if not wanted_posture.is_empty() and not _posture_matches(String(semantics.get("posture", "any")), wanted_posture):
			continue
		var score := score_action_for_tags(StringName(String(action_name)), preferred, avoided)
		if score <= 0.0 and not preferred.is_empty():
			continue
		semantics["tag_match_score"] = score
		result.append(semantics)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("tag_match_score", 0.0)) > float(b.get("tag_match_score", 0.0))
	)
	return result

func score_action_for_tags(action_name: StringName, preferred_tags: Variant = [], avoid_tags: Variant = []) -> float:
	var semantics := get_action_semantics(action_name)
	if semantics.is_empty():
		return 0.0
	var preferred := _variant_to_lower_string_array(preferred_tags)
	var avoided := _variant_to_lower_string_array(avoid_tags)
	var action_tags := _variant_to_lower_string_array(semantics.get("tags", []))
	action_tags.append(String(semantics.get("category", "")).strip_edges().to_lower())
	action_tags.append(String(semantics.get("posture", "")).strip_edges().to_lower())
	var score := 0.0
	for tag in preferred:
		if action_tags.has(tag):
			score += 1.0
	for tag in avoided:
		if action_tags.has(tag):
			score -= 1.25
	return score

func pick_best_action(candidates: Variant, preferred_tags: Variant = [], avoid_tags: Variant = [], fallback: StringName = &"idle_fidget") -> StringName:
	var names := _variant_to_string_array(candidates)
	if names.is_empty():
		return fallback
	var best := String(fallback)
	var best_score := -9999.0
	for name in names:
		var score := score_action_for_tags(StringName(name), preferred_tags, avoid_tags)
		var semantics := get_action_semantics(StringName(name))
		if bool(semantics.get("interruptible", true)):
			score += 0.08
		if bool(semantics.get("loop", false)):
			score += 0.04
		if score > best_score:
			best_score = score
			best = name
	return StringName(best)

func build_action_contract(actions: Variant = []) -> Array[Dictionary]:
	var names := _variant_to_string_array(actions)
	if names.is_empty():
		names = _variant_to_string_array(_action_table.keys())
	var result: Array[Dictionary] = []
	for name in names:
		var semantics := get_action_semantics(StringName(name))
		if semantics.is_empty():
			continue
		result.append(semantics)
	return result

func _rebuild_tables() -> void:
	_action_table = _build_default_action_table()
	for key in extra_action_semantics.keys():
		if extra_action_semantics[key] is Dictionary:
			var clean_key := String(key).strip_edges()
			if not clean_key.is_empty():
				var merged := get_action_semantics(StringName(clean_key))
				for override_key in (extra_action_semantics[key] as Dictionary).keys():
					merged[override_key] = (extra_action_semantics[key] as Dictionary)[override_key]
				_action_table[clean_key] = merged
	_context_actions = _build_default_context_actions()
	for key in extra_context_actions.keys():
		_context_actions[String(key).strip_edges().to_lower()] = extra_context_actions[key]

func _build_default_action_table() -> Dictionary:
	var table := {}
	_add(table, "idle_normal", "idle", "standing", true, true, false, "neutral", ["idle", "standing"], "默认站立待机。")
	_add(table, "idle_relaxed", "idle", "standing", true, true, false, "neutral", ["idle", "calm"], "放松站姿。")
	_add(table, "idle_sleepy", "idle", "standing", true, true, false, "sorrow", ["idle", "tired"], "困倦站姿。")
	_add(table, "idle_alert", "idle", "standing", true, true, false, "surprised", ["idle", "alert"], "警觉观察。")
	_add(table, "idle_fidget", "ambient", "standing", false, true, false, "neutral", ["cute", "idle", "ambient"], "站立小动作。")
	_add(table, "listen", "social", "standing", false, true, false, "neutral", ["teacher", "listen", "social"], "看着老师听话。")
	_add(table, "walk", "locomotion", "standing", true, true, true, "neutral", ["move"], "行走循环。")
	_add(table, "run", "locomotion", "standing", true, true, true, "neutral", ["move", "fast"], "跑步循环。")
	_add(table, "turn_left", "turn", "standing", false, false, true, "neutral", ["turn"], "向左转身过渡。")
	_add(table, "turn_right", "turn", "standing", false, false, true, "neutral", ["turn"], "向右转身过渡。")
	_add(table, "turn_180", "turn", "standing", false, false, true, "neutral", ["turn"], "大角度转身过渡。")
	_add(table, "sit_down", "posture", "standing_to_seated", false, false, true, "neutral", ["seat", "root_motion"], "从站立坐下，必须对齐坐点。")
	_add(table, "seated_idle", "posture", "seated", true, true, false, "neutral", ["seat", "idle"], "坐姿待机循环。")
	_add(table, "seated_sleepy", "posture", "seated", true, true, false, "sorrow", ["seat", "tired"], "坐着犯困。")
	_add(table, "stand_up", "posture", "seated_to_standing", false, false, true, "neutral", ["seat", "root_motion"], "从坐姿起身，完成后回 stand 点。")
	_add(table, "work_inspect_cabinet", "work", "standing", true, true, false, "neutral", ["inspect", "cabinet", "storage", "equipment"], "检查柜子。")
	_add(table, "work_check_shelf", "work", "standing", true, true, false, "neutral", ["inspect", "medical", "shelf"], "检查架子/医疗柜。")
	_add(table, "work_check_lower", "work", "standing", true, true, false, "fun", ["inspect", "low", "tool", "material", "utility"], "低处检查。")
	_add(table, "work_count_supplies", "work", "standing", true, true, false, "fun", ["supplies", "food", "water", "storage", "count"], "清点食物或物资。")
	_add(table, "work_reach", "work", "standing", false, true, true, "fun", ["reach", "take_item", "use"], "伸手够东西。")
	_add(table, "work_take_item", "work", "standing", false, true, true, "fun", ["take_item", "food", "water", "supplies", "use"], "拿起物品。")
	_add(table, "work_place_item", "work", "standing", false, true, true, "neutral", ["place_item", "organize", "supplies"], "放下物品。")
	_add(table, "work_drink", "work", "standing", false, true, false, "joy", ["drink", "eat", "use_item", "food", "water"], "喝水/进食通用使用动作。")
	_add(table, "work_explain", "work", "standing", false, true, false, "fun", ["explain", "talk", "teacher", "social"], "边解释边比划。")
	_add(table, "react_nod", "reaction", "any", false, true, false, "joy", ["teacher", "agree", "social"], "点头回应。")
	_add(table, "small_nod", "reaction", "standing", false, true, false, "joy", ["teacher", "agree", "social", "cute"], "小幅点头。")
	_add(table, "react_wave", "reaction", "standing", false, true, false, "joy", ["teacher", "wave", "greeting", "social"], "挥手回应。")
	_add(table, "tiny_wave", "reaction", "standing", false, true, false, "joy", ["teacher", "cute", "wave", "greeting", "social"], "很小的可爱挥手。")
	_add(table, "small_wave", "reaction", "standing", false, true, false, "joy", ["teacher", "wave", "greeting", "social"], "小幅挥手。")
	_add(table, "cute_explain", "social", "standing", false, true, false, "fun", ["teacher", "talk", "explain", "cute", "social"], "可爱解释。")
	_add(table, "small_happy_bounce", "reaction", "standing", true, true, false, "joy", ["happy", "cute", "joy", "social"], "开心小跳。")
	_add(table, "rub_eye", "ambient", "standing", false, true, false, "sorrow", ["tired", "rest", "sleepy"], "揉眼睛。")
	_add(table, "sleepy_yawn", "ambient", "standing", false, true, false, "sorrow", ["tired", "rest", "sleepy"], "打哈欠。")
	_add(table, "cute_startle", "reaction", "standing", false, false, false, "surprised", ["startle", "blocked", "surprised"], "可爱受惊。")
	_add(table, "curious_peek", "ambient", "standing", false, true, false, "fun", ["curious", "look", "inspect", "cute"], "好奇探头。")
	_add(table, "tilt_head_cute", "social", "standing", false, true, false, "fun", ["curious", "teacher", "cute", "social"], "可爱歪头。")
	_add(table, "look_back", "ambient", "standing", false, true, false, "surprised", ["look", "caution", "door"], "回头看。")
	_add(table, "look_around", "ambient", "standing", false, true, false, "neutral", ["look", "wander", "curious", "ambient"], "四处看看。")
	return table

func _build_default_context_actions() -> Dictionary:
	return {
		"social_standing": ["tiny_wave", "small_wave", "small_nod", "cute_explain", "tilt_head_cute", "listen"],
		"social_seated": ["seated_idle", "react_nod"],
		"tired": ["rub_eye", "sleepy_yawn", "seated_sleepy", "idle_sleepy"],
		"inspect_storage": ["work_inspect_cabinet", "work_count_supplies", "work_take_item"],
		"inspect_low": ["work_check_lower", "curious_peek"],
		"wander": ["look_around", "curious_peek", "idle_fidget", "look_back"],
		"happy": ["small_happy_bounce", "tiny_wave", "small_wave"],
	}

func _add(table: Dictionary, name: String, category: String, posture: String, loop: bool, interruptible: bool, root_motion: bool, default_expression: String, tags: Array, description: String) -> void:
	table[name] = {
		"name": name,
		"category": category,
		"posture": posture,
		"loop": loop,
		"interruptible": interruptible,
		"uses_root_motion": root_motion,
		"default_expression": default_expression,
		"tags": tags.duplicate(),
		"description": description,
	}

func _default_semantics_for(action_name: String) -> Dictionary:
	return {
		"name": action_name,
		"category": "unknown",
		"posture": "any",
		"loop": action_name.ends_with("_loop"),
		"interruptible": true,
		"uses_root_motion": false,
		"default_expression": "neutral",
		"tags": [],
		"description": "未登记动作，请在 CharacterActionSemanticsComponent 中补充语义。",
	}

func _variant_to_string_array(value: Variant) -> Array:
	var result: Array = []
	if value is Array or value is PackedStringArray:
		for entry in value:
			var text := String(entry).strip_edges()
			if not text.is_empty() and not result.has(text):
				result.append(text)
	return result

func _variant_to_lower_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array or value is PackedStringArray:
		for entry in value:
			var text := String(entry).strip_edges().to_lower()
			if not text.is_empty() and not result.has(text):
				result.append(text)
	return result

func _posture_matches(action_posture: String, wanted_posture: String) -> bool:
	var action := action_posture.strip_edges().to_lower()
	var wanted := wanted_posture.strip_edges().to_lower()
	if action.is_empty() or action == "any" or wanted.is_empty() or action == wanted:
		return true
	if wanted == "seated":
		return action.begins_with("seated")
	if wanted == "standing":
		return action == "standing" or action == "standing_to_seated" or action == "seated_to_standing"
	return false
