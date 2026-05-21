extends Node
class_name CharacterAutonomousPlannerComponent

signal decision_scored(best_decision: Dictionary, candidates: Array)

@export var mind_state_path: NodePath
@export var perception_component_path: NodePath
@export var blackboard_path: NodePath
@export var action_semantics_path: NodePath
@export_range(0.0, 5.0, 0.01) var object_distance_penalty: float = 0.08
@export_range(0.0, 5.0, 0.01) var repeat_target_penalty: float = 3.0
@export_range(0.0, 5.0, 0.01) var movement_bias: float = 0.45
@export_range(0.0, 1.0, 0.01) var minimum_score: float = 0.18
@export_range(0.0, 1.0, 0.01) var top_candidate_randomness: float = 0.18
@export_range(0.0, 0.5, 0.001) var score_noise: float = 0.035
@export_range(0.0, 10.0, 0.1) var repeat_kind_penalty: float = 0.55
@export_range(0.0, 300.0, 0.1) var default_target_cooldown_sec: float = 25.0
@export_range(0.0, 1.0, 0.01) var base_wander_score: float = 0.52
@export_range(0.0, 1.0, 0.01) var base_ambient_score: float = 0.30
@export_range(0.0, 1.0, 0.01) var max_rest_score_without_need: float = 0.42
@export_range(0.0, 1.0, 0.01) var social_prompt_bonus: float = 0.34
@export_range(0.0, 1.0, 0.01) var natural_variety_band: float = 0.22
@export_range(0.0, 1.0, 0.01) var natural_variety_chance: float = 0.34
@export var inspect_tags: PackedStringArray = PackedStringArray(["storage", "supplies", "food", "medical", "equipment", "tool", "material", "cabinet", "utility"])
@export var supply_tags: PackedStringArray = PackedStringArray(["food", "supplies"])
@export var medical_tags: PackedStringArray = PackedStringArray(["medical"])
@export var lower_check_tags: PackedStringArray = PackedStringArray(["tool", "material", "utility"])
@export var sit_tags: PackedStringArray = PackedStringArray(["seat", "rest", "bed"])
@export var avoid_tags: PackedStringArray = PackedStringArray(["danger", "blocked"])
@export var debug_tags: PackedStringArray = PackedStringArray(["debug", "experiment", "test"])
@export var ambient_actions: PackedStringArray = PackedStringArray(["idle_fidget", "look_around", "curious_peek", "tilt_head_cute", "small_happy_bounce", "tiny_wave", "rub_eye", "sleepy_yawn"])
@export var seated_ambient_actions: PackedStringArray = PackedStringArray(["seated_idle", "seated_sleepy"])
@export var player_social_actions: PackedStringArray = PackedStringArray(["tiny_wave", "small_wave", "small_nod", "cute_explain", "tilt_head_cute"])
@export var player_social_seated_actions: PackedStringArray = PackedStringArray(["seated_idle"])
@export var nav_point_group: StringName = &"ai_nav_point"
@export_range(1, 64, 1) var max_nav_point_candidates: int = 24
@export var debug_log: bool = false

var _mind_state: Node
var _perception_component: Node
var _blackboard: Node
var _action_semantics: Node
var _rng := RandomNumberGenerator.new()
var _last_decision_kind := ""
var _last_target_ref := ""
var _recent_kinds: Array[String] = []
var _recent_targets: Array[String] = []
var _target_cooldowns: Dictionary = {}

func _ready() -> void:
	_rng.randomize()
	_refresh_refs()
	set_process(true)

func _process(delta: float) -> void:
	_tick_target_cooldowns(delta)

func choose_decision(context: Dictionary = {}) -> Dictionary:
	_refresh_refs()
	if context.is_empty() and _blackboard != null and _blackboard.has_method("build_blackboard_snapshot"):
		var blackboard_value: Variant = _blackboard.call("build_blackboard_snapshot")
		if blackboard_value is Dictionary:
			context = {"blackboard": (blackboard_value as Dictionary).duplicate(true)}
	var mind := _get_mind_snapshot()
	var snapshot := _get_perception_snapshot(context)
	var resource_stats: Dictionary = context.get("resource_stats", snapshot.get("resource_stats", {})) as Dictionary if (context.get("resource_stats", snapshot.get("resource_stats", {})) is Dictionary) else {}
	if not resource_stats.is_empty():
		mind["energy"] = float(resource_stats.get("energy", 70.0))
		mind["mood"] = float(resource_stats.get("mood", 55.0))
	if bool(context.get("is_seated", false)):
		snapshot["is_seated"] = true
	if _mind_state != null and _mind_state.has_method("apply_perception_hint"):
		_mind_state.call("apply_perception_hint", snapshot)
		mind = _get_mind_snapshot()
		if not resource_stats.is_empty():
			mind["energy"] = float(resource_stats.get("energy", 70.0))
			mind["mood"] = float(resource_stats.get("mood", 55.0))
	var candidates: Array = []
	var is_seated := bool(context.get("is_seated", false))
	_add_social_candidates(candidates, mind, snapshot)
	if not is_seated:
		_add_object_candidates(candidates, mind, snapshot, context)
		_add_nav_point_candidates(candidates, mind, context)
	_add_ambient_candidates(candidates, mind, is_seated)
	_postprocess_candidate_scores(candidates, mind, context)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
	)
	var best := _pick_from_top(candidates)
	if float(best.get("score", 0.0)) < minimum_score:
		return {}
	_remember_decision(best)
	decision_scored.emit(best.duplicate(true), candidates)
	_log("best=%s score=%.2f" % [String(best.get("kind", "")), float(best.get("score", 0.0))])
	return best

func notify_decision_executed(decision: Dictionary) -> void:
	_remember_decision(decision)
	var target_ref := _decision_target_ref(decision)
	if not target_ref.is_empty():
		var cooldown := float(decision.get("cooldown_sec", default_target_cooldown_sec))
		if cooldown > 0.0:
			_target_cooldowns[target_ref] = cooldown
	if _mind_state != null and _mind_state.has_method("apply_behavior_feedback"):
		_mind_state.call("apply_behavior_feedback", String(decision.get("feedback", decision.get("kind", ""))), decision)

func _add_social_candidates(out: Array, mind: Dictionary, _snapshot: Dictionary) -> void:
	var social := float(mind.get("social", 0.0))
	var boredom := float(mind.get("boredom", 0.0))
	var intent: Variant = mind.get("high_level_intent", {})
	var is_seated := bool(_snapshot.get("is_seated", false))
	var fed_bonus := 0.0
	if intent is Dictionary and String((intent as Dictionary).get("kind", "")) == "recently_fed":
		fed_bonus = 0.95
	var player_interest := _player_interest_score(_snapshot)
	out.append({"kind": "look_at_player", "action": _pick_social_action(is_seated), "score": social * 0.62 + boredom * 0.08 + fed_bonus * 0.45 + player_interest * social_prompt_bonus, "feedback": "look_at_player", "cooldown_sec": 14.0, "arrival_expression": "face_joy" if fed_bonus > 0.0 else "face_neutral"})
	out.append({"kind": "ambient", "action": _pick_social_action(is_seated), "score": social * 0.46 + boredom * 0.07 + fed_bonus * 0.55, "feedback": "small_wave", "cooldown_sec": 18.0, "arrival_expression": "face_joy"})
	if fed_bonus > 0.0:
		out.append({"kind": "ambient", "action": "seated_idle" if is_seated else "small_happy_bounce", "score": fed_bonus * 0.70 + social * 0.22, "feedback": "fed", "cooldown_sec": 28.0, "arrival_expression": "face_joy", "dwell_time_sec": 1.8})

func _add_object_candidates(out: Array, mind: Dictionary, snapshot: Dictionary, context: Dictionary) -> void:
	var objects: Variant = snapshot.get("nearby_objects", [])
	if objects is not Array:
		return
	for value in objects:
		if value is not Dictionary:
			continue
		var entry := (value as Dictionary).duplicate(true)
		if _has_any_tag(entry, avoid_tags):
			continue
		var target_ref := _entry_ref(entry)
		if target_ref.is_empty():
			continue
		if _is_ref_on_cooldown(target_ref, context):
			continue
		var distance := float(entry.get("distance", 0.0))
		if _has_any_tag(entry, sit_tags):
			var sit_score := _score_sit(entry, mind, distance)
			out.append(_make_go_decision(entry, target_ref, "sit", "sit_down", sit_score, "sit"))
		if _is_inspect_object(entry):
			var arrival := _arrival_action_for_entry(entry)
			var inspect_score := _score_inspect(entry, mind, distance, context)
			out.append(_make_go_decision(entry, target_ref, "approach", arrival, inspect_score, "inspect"))

func _add_nav_point_candidates(out: Array, mind: Dictionary, context: Dictionary) -> void:
	var points := _collect_nav_point_summaries(context)
	for entry in points:
		if bool(entry.get("enabled", true)) == false:
			continue
		if _has_any_tag(entry, avoid_tags) or _has_any_tag(entry, debug_tags):
			continue
		var point_id := _entry_ref(entry)
		if point_id.is_empty():
			continue
		if _is_ref_on_cooldown(point_id, context):
			continue
		var score := _score_nav_point(entry, mind, context)
		out.append({
			"kind": "go_to_nav_point",
			"target_nav_point": point_id,
			"target_path": String(entry.get("path", "")),
			"marker_role": String(entry.get("marker_role", "approach")),
			"arrival_action": String(entry.get("arrival_action", "idle_fidget")),
			"arrival_expression": String(entry.get("arrival_expression", _expression_for_entry(entry, String(entry.get("arrival_action", "idle_fidget"))))),
			"action_options": entry.get("action_options", []),
			"expression_options": entry.get("expression_options", []),
			"action_hint": String(entry.get("action_hint", "")),
			"target_object_id": String(entry.get("target_object_id", "")),
			"tags": entry.get("tags", []),
			"name": String(entry.get("name", "")),
			"description": String(entry.get("description", "")),
			"face_mode": String(entry.get("face_mode", "")),
			"dwell_time_sec": float(entry.get("dwell_time_sec", 1.5)),
			"cooldown_sec": float(entry.get("cooldown_sec", 35.0)),
			"run": false,
			"score": score,
			"feedback": "nav_point",
			"distance": float(entry.get("distance", 0.0)),
		})

func _score_nav_point(entry: Dictionary, mind: Dictionary, context: Dictionary) -> float:
	var score := float(entry.get("priority", 1.0)) * 0.35 + movement_bias
	var energy := float(mind.get("energy", 70.0))
	var role := String(entry.get("marker_role", "")).strip_edges().to_lower()
	var is_sit_point := role == "sit" or _has_any_tag(entry, sit_tags)
	if is_sit_point and float(mind.get("tiredness", 0.0)) < 0.55 and energy > 35.0:
		score -= 1.15
	if is_sit_point and energy < 35.0:
		score += (35.0 - energy) / 35.0 * 1.3
	if is_sit_point:
		score = minf(score, max_rest_score_without_need + float(mind.get("tiredness", 0.0)) * 0.85 + maxf(0.0, (40.0 - energy) / 40.0) * 0.9)
	if _has_any_tag(entry, PackedStringArray(["wander", "idle", "route", "corner"])):
		score += base_wander_score + float(mind.get("boredom", 0.0)) * 0.38 + float(mind.get("curiosity", 0.0)) * 0.16
	if _has_any_tag(entry, PackedStringArray(["social", "teacher"])):
		score += float(mind.get("social", 0.0)) * 0.42
	if _has_any_tag(entry, supply_tags):
		score += float(mind.get("duty", 0.0)) * 0.45 + float(mind.get("curiosity", 0.0)) * 0.12
	if _has_any_tag(entry, medical_tags):
		score += float(mind.get("duty", 0.0)) * 0.25 + float(mind.get("caution", 0.0)) * 0.22
	if _has_any_tag(entry, lower_check_tags):
		score += float(mind.get("curiosity", 0.0)) * 0.26 + float(mind.get("duty", 0.0)) * 0.18
	if _has_any_tag(entry, PackedStringArray(["equipment", "cabinet", "storage"])):
		score += float(mind.get("duty", 0.0)) * 0.22 + float(mind.get("curiosity", 0.0)) * 0.18
	var weights: Variant = entry.get("mood_weights", {})
	if weights is Dictionary:
		for key in ["curiosity", "tiredness", "boredom", "social", "duty", "caution"]:
			score += float(mind.get(key, 0.0)) * float((weights as Dictionary).get(key, 0.0))
	else:
		score += float(mind.get("boredom", 0.0)) * 0.35
	var intent: Dictionary = mind.get("high_level_intent", {})
	if String(intent.get("kind", "")) == "recently_fed" and _has_any_tag(entry, supply_tags):
		score -= 0.45
	var priority_tags: Variant = intent.get("priority_tags", []) if intent is Dictionary else []
	if priority_tags is Array or priority_tags is PackedStringArray:
		for tag in priority_tags:
			if _has_any_tag(entry, PackedStringArray([String(tag)])):
				score += 0.45
	if String(context.get("last_nav_point", "")) == _entry_ref(entry) or _last_target_ref == _entry_ref(entry):
		score -= repeat_target_penalty
	score += _situation_tag_bonus(entry, context)
	score -= float(entry.get("distance", 0.0)) * object_distance_penalty
	return score

func _collect_nav_point_summaries(context: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var context_points: Variant = context.get("known_nav_points", context.get("ai_nav_points", []))
	if (context_points is not Array or (context_points as Array).is_empty()) and context.get("blackboard", {}) is Dictionary:
		context_points = (context.get("blackboard", {}) as Dictionary).get("known_nav_points", [])
	if context_points is Array:
		for entry_value in context_points:
			if result.size() >= max_nav_point_candidates:
				break
			if entry_value is Dictionary:
				result.append((entry_value as Dictionary).duplicate(true))
		if not result.is_empty():
			return result
	if _perception_component != null and _perception_component.has_method("build_known_nav_points"):
		var known_value: Variant = _perception_component.call("build_known_nav_points")
		if known_value is Array:
			for entry_value in known_value:
				if result.size() >= max_nav_point_candidates:
					break
				if entry_value is Dictionary:
					result.append((entry_value as Dictionary).duplicate(true))
			if not result.is_empty():
				return result
	var tree := get_tree()
	if tree == null:
		return result
	var observer := _find_observer()
	for candidate in tree.get_nodes_in_group(nav_point_group):
		if result.size() >= max_nav_point_candidates:
			break
		var node := candidate as Node
		if node == null or not is_instance_valid(node):
			continue
		if not node.has_method("build_ai_nav_point_summary"):
			continue
		var value: Variant = node.call("build_ai_nav_point_summary", observer)
		if value is Dictionary:
			result.append((value as Dictionary).duplicate(true))
	return result

func _find_observer() -> Node3D:
	if _perception_component != null and _perception_component.has_method("_resolve_observer"):
		var value: Variant = _perception_component.call("_resolve_observer")
		if value is Node3D:
			return value as Node3D
	var parent_node := get_parent()
	while parent_node != null:
		if parent_node is Node3D:
			return parent_node as Node3D
		parent_node = parent_node.get_parent()
	return null

func _add_ambient_candidates(out: Array, mind: Dictionary, is_seated: bool = false) -> void:
	var boredom := float(mind.get("boredom", 0.0))
	var curiosity := float(mind.get("curiosity", 0.0))
	var tiredness := float(mind.get("tiredness", 0.0))
	var caution := float(mind.get("caution", 0.0))
	var energy := float(mind.get("energy", 70.0))
	var low_energy_bonus := maxf(0.0, (40.0 - energy) / 40.0)
	var source_actions := seated_ambient_actions if is_seated else ambient_actions
	for action in source_actions:
		var action_text := String(action).strip_edges()
		if is_seated:
			action_text = _sanitize_seated_action(action_text)
		if action_text.is_empty():
			continue
		var score := base_ambient_score + boredom * 0.36 + curiosity * 0.14
		var feedback := "ambient"
		match action_text:
			"look_around":
				score += caution * 0.45 + curiosity * 0.10
			"curious_peek", "tilt_head_cute":
				score += curiosity * 0.35
			"rub_eye", "sleepy_yawn":
				score += tiredness * 0.65 + low_energy_bonus * 0.45
				feedback = action_text
			"small_happy_bounce", "tiny_wave":
				score += float(mind.get("social", 0.0)) * 0.22
			"small_wave", "small_nod", "cute_explain":
				score += float(mind.get("social", 0.0)) * 0.30
			"seated_idle":
				score += 0.28
			"seated_sleepy":
				score += tiredness * 0.55 + low_energy_bonus * 0.75
			"listen":
				score += float(mind.get("social", 0.0)) * 0.16
		if _last_decision_kind == "ambient" and action_text == String(_last_target_ref):
			score -= 0.55
		out.append({"kind": "ambient", "action": action_text, "score": score, "feedback": feedback, "cooldown_sec": 10.0})

func _pick_social_action(is_seated: bool) -> String:
	var actions := player_social_seated_actions if is_seated else player_social_actions
	if actions.is_empty():
		return "seated_idle" if is_seated else "listen"
	var picked := String(actions[_rng.randi_range(0, actions.size() - 1)]).strip_edges()
	return _sanitize_seated_action(picked) if is_seated else picked

func _sanitize_seated_action(action: String) -> String:
	match action.strip_edges().to_lower():
		"seated_sleepy":
			return "seated_sleepy"
		"seated_idle", "listen", "small_nod", "tiny_wave", "small_wave", "cute_explain", "tilt_head_cute", "idle_normal", "idle_relaxed":
			return "seated_idle"
	return "seated_idle"

func _score_inspect(entry: Dictionary, mind: Dictionary, distance: float, context: Dictionary) -> float:
	var score := float(mind.get("curiosity", 0.0)) * 0.55 + float(mind.get("duty", 0.0)) * 0.55 + movement_bias
	if _has_any_tag(entry, supply_tags):
		score += float(mind.get("duty", 0.0)) * 0.30
	if _has_any_tag(entry, medical_tags):
		score += float(mind.get("caution", 0.0)) * 0.20 + float(mind.get("duty", 0.0)) * 0.20
	var intent: Dictionary = mind.get("high_level_intent", {})
	if String(intent.get("kind", "")) == "recently_fed" and _has_any_tag(entry, supply_tags):
		score -= 0.55
	var priority_tags: Variant = intent.get("priority_tags", []) if intent is Dictionary else []
	if priority_tags is Array or priority_tags is PackedStringArray:
		for tag in priority_tags:
			if _has_any_tag(entry, PackedStringArray([String(tag)])):
				score += 0.55
	if String(context.get("last_target", "")) == _entry_ref(entry) or _last_target_ref == _entry_ref(entry):
		score -= repeat_target_penalty
	score += _situation_tag_bonus(entry, context)
	score -= distance * object_distance_penalty
	return score

func _score_sit(_entry: Dictionary, mind: Dictionary, distance: float) -> float:
	var energy := float(mind.get("energy", 70.0))
	var low_energy_bonus := maxf(0.0, (45.0 - energy) / 45.0)
	var score := float(mind.get("tiredness", 0.0)) * 0.72 + float(mind.get("boredom", 0.0)) * 0.12 + low_energy_bonus * 1.1
	if float(mind.get("tiredness", 0.0)) < 0.55 and energy > 35.0:
		score = minf(score, max_rest_score_without_need)
	score -= distance * object_distance_penalty
	if _last_decision_kind == "sit":
		score -= repeat_target_penalty
	return score

func _player_interest_score(snapshot: Dictionary) -> float:
	var awareness: Variant = snapshot.get("player_awareness", snapshot.get("awareness", {}))
	if awareness is Dictionary:
		var data := awareness as Dictionary
		var score := 0.0
		if bool(data.get("gaze_active", false)):
			score += 0.65
		if bool(data.get("near", false)):
			score += 0.25
		if bool(data.get("very_close", false)):
			score += 0.25
		score += clampf(float(data.get("gaze_time", 0.0)) / 4.0, 0.0, 0.35)
		return clampf(score, 0.0, 1.0)
	var objects: Variant = snapshot.get("nearby_objects", [])
	if objects is Array:
		for value in objects:
			if value is Dictionary and _has_any_tag(value as Dictionary, PackedStringArray(["player", "teacher", "social"])):
				return 0.35
	return 0.0

func _make_go_decision(entry: Dictionary, target_ref: String, marker_role: String, arrival_action: String, score: float, feedback: String) -> Dictionary:
	return {
		"kind": "go_to_object",
		"target_object": target_ref,
		"marker_role": _choose_marker_role(entry, marker_role),
		"arrival_action": arrival_action,
		"arrival_expression": _expression_for_entry(entry, arrival_action),
		"dwell_time_sec": _dwell_for_arrival(arrival_action),
		"cooldown_sec": default_target_cooldown_sec,
		"run": false,
		"score": score,
		"feedback": feedback,
		"distance": float(entry.get("distance", 0.0)),
		"tags": entry.get("tags", []),
		"name": String(entry.get("name", "")),
		"description": String(entry.get("description", "")),
		"target_object_id": String(entry.get("target_object_id", "")),
	}

func _expression_for_entry(entry: Dictionary, arrival_action: String = "") -> String:
	var explicit := String(entry.get("arrival_expression", entry.get("expression", ""))).strip_edges().to_lower()
	if not explicit.is_empty():
		return explicit
	var action := arrival_action.strip_edges().to_lower()
	var object_type := String(entry.get("type", "")).strip_edges().to_lower()
	if action == "work_count_supplies" or object_type == "food" or _has_any_tag(entry, supply_tags):
		return "face_fun"
	if action == "work_check_shelf" or object_type == "medical" or _has_any_tag(entry, medical_tags):
		return "face_neutral"
	if action == "work_check_lower" or _has_any_tag(entry, lower_check_tags):
		return "face_fun"
	if action == "work_inspect_cabinet" or _has_any_tag(entry, PackedStringArray(["equipment", "cabinet", "storage"])):
		return "face_neutral"
	if _has_any_tag(entry, PackedStringArray(["door", "lookout", "caution"])):
		return "face_surprised"
	if _has_any_tag(entry, PackedStringArray(["teacher", "social"])):
		return "face_joy"
	if _has_any_tag(entry, sit_tags) or action in ["rub_eye", "sleepy_yawn", "seated_sleepy"]:
		return "face_sorrow"
	return "face_neutral"

func _arrival_action_for_entry(entry: Dictionary) -> String:
	var object_type := String(entry.get("type", "")).to_lower()
	if object_type == "food" or _has_any_tag(entry, supply_tags):
		return "work_count_supplies"
	if object_type == "medical" or _has_any_tag(entry, medical_tags):
		return "work_check_shelf"
	if object_type == "tool" or _has_any_tag(entry, lower_check_tags):
		return "work_check_lower"
	return "work_inspect_cabinet"

func _is_inspect_object(entry: Dictionary) -> bool:
	if _has_any_tag(entry, inspect_tags):
		return true
	var actions: Variant = entry.get("actions", [])
	if actions is Array or actions is PackedStringArray:
		for action in actions:
			var text := String(action).to_lower()
			if text.find("inspect") >= 0 or text.find("check") >= 0 or text.find("open") >= 0 or text.find("count") >= 0:
				return true
	return false

func _choose_marker_role(entry: Dictionary, preferred: String) -> String:
	var roles_value: Variant = entry.get("marker_roles", {})
	if roles_value is Dictionary:
		var roles := roles_value as Dictionary
		if roles.has(preferred):
			return preferred
		for fallback in ["approach", "look", "open", "sit"]:
			if roles.has(fallback):
				return fallback
	return preferred

func _pick_from_top(candidates: Array) -> Dictionary:
	if candidates.is_empty():
		return {}
	if candidates.size() == 1:
		return (candidates[0] as Dictionary).duplicate(true)
	var best_score := float((candidates[0] as Dictionary).get("score", 0.0))
	if natural_variety_chance > 0.0 and _rng.randf() < natural_variety_chance:
		var varied := _pick_from_natural_band(candidates, best_score)
		if not varied.is_empty():
			return varied
	if _rng.randf() >= top_candidate_randomness:
		return (candidates[0] as Dictionary).duplicate(true)
	var top_count := mini(candidates.size(), 3)
	var total := 0.0
	for i in range(top_count):
		total += maxf(0.01, float((candidates[i] as Dictionary).get("score", 0.0)))
	var roll := _rng.randf() * total
	var accum := 0.0
	for i in range(top_count):
		var entry := candidates[i] as Dictionary
		accum += maxf(0.01, float(entry.get("score", 0.0)))
		if roll <= accum:
			return entry.duplicate(true)
	return (candidates[0] as Dictionary).duplicate(true)

func _pick_from_natural_band(candidates: Array, best_score: float) -> Dictionary:
	var band: Array[Dictionary] = []
	var min_score := best_score - natural_variety_band
	for value in candidates:
		if value is not Dictionary:
			continue
		var candidate := value as Dictionary
		var score := float(candidate.get("score", 0.0))
		if score < min_score:
			continue
		if score < minimum_score:
			continue
		band.append(candidate)
	if band.size() <= 1:
		return {}
	var total := 0.0
	for candidate in band:
		total += maxf(0.01, float(candidate.get("score", 0.0)) - min_score + 0.01)
	var roll := _rng.randf() * total
	var accum := 0.0
	for candidate in band:
		accum += maxf(0.01, float(candidate.get("score", 0.0)) - min_score + 0.01)
		if roll <= accum:
			return candidate.duplicate(true)
	return band[0].duplicate(true)

func _remember_decision(decision: Dictionary) -> void:
	_last_decision_kind = String(decision.get("kind", ""))
	_last_target_ref = _decision_target_ref(decision)
	_push_recent(_recent_kinds, _last_decision_kind, 6)
	_push_recent(_recent_targets, _last_target_ref, 8)

func _postprocess_candidate_scores(candidates: Array, mind: Dictionary, context: Dictionary) -> void:
	var last_kind := String(context.get("last_kind", _last_decision_kind))
	var last_target := String(context.get("last_target", _last_target_ref))
	var last_nav_point := String(context.get("last_nav_point", ""))
	for value in candidates:
		if value is not Dictionary:
			continue
		var candidate := value as Dictionary
		var kind := String(candidate.get("kind", ""))
		var target_ref := _decision_target_ref(candidate)
		var score := float(candidate.get("score", 0.0))
		if kind == last_kind:
			score -= repeat_kind_penalty
		if not target_ref.is_empty() and (target_ref == last_target or target_ref == last_nav_point):
			score -= repeat_target_penalty
		if _recent_kinds.has(kind):
			score -= 0.12 * float(_recent_kinds.count(kind))
		if _recent_targets.has(target_ref):
			score -= 0.35 * float(_recent_targets.count(target_ref))
		if kind == "go_to_object" or kind == "go_to_nav_point":
			score += float(mind.get("boredom", 0.0)) * 0.22
		else:
			score -= float(mind.get("boredom", 0.0)) * 0.08
		score += _situation_decision_bonus(kind, context)
		score += _situation_action_bonus(String(candidate.get("action", candidate.get("arrival_action", ""))), context)
		if score_noise > 0.0:
			score += _rng.randf_range(-score_noise, score_noise)
		candidate["score"] = score

func _situation_context(context: Dictionary) -> Dictionary:
	if context.get("situation_context", {}) is Dictionary:
		return context.get("situation_context", {}) as Dictionary
	if context.get("blackboard", {}) is Dictionary:
		var blackboard := context.get("blackboard", {}) as Dictionary
		if blackboard.get("situation_context", {}) is Dictionary:
			return blackboard.get("situation_context", {}) as Dictionary
	return {}

func _situation_decision_bonus(kind: String, context: Dictionary) -> float:
	var situation := _situation_context(context)
	var bias: Variant = situation.get("decision_bias", {})
	if bias is Dictionary:
		return float((bias as Dictionary).get(kind, 0.0))
	return 0.0

func _situation_action_bonus(action_name: String, context: Dictionary) -> float:
	if action_name.strip_edges().is_empty():
		return 0.0
	var situation := _situation_context(context)
	var actions: Variant = situation.get("action_bias", [])
	if actions is Array or actions is PackedStringArray:
		for action in actions:
			if String(action) == action_name:
				return 0.45
	return 0.0

func _situation_tag_bonus(entry: Dictionary, context: Dictionary) -> float:
	var situation := _situation_context(context)
	var score := 0.0
	var priority_tags: Variant = situation.get("priority_tags", [])
	if priority_tags is Array or priority_tags is PackedStringArray:
		for tag in priority_tags:
			if _has_any_tag(entry, PackedStringArray([String(tag)])):
				score += 0.38
	var avoid_tags_value: Variant = situation.get("avoid_tags", [])
	if avoid_tags_value is Array or avoid_tags_value is PackedStringArray:
		for tag in avoid_tags_value:
			if _has_any_tag(entry, PackedStringArray([String(tag)])):
				score -= 0.55
	return score

func _dwell_for_arrival(arrival_action: String) -> float:
	match arrival_action:
		"work_count_supplies", "work_inspect_cabinet", "work_check_shelf", "work_check_lower":
			return 2.8
		"sit_down":
			return 6.0
		"look_around", "curious_peek":
			return 2.2
	return 1.6

func _push_recent(list: Array[String], value: String, limit: int) -> void:
	if value.is_empty():
		return
	list.push_front(value)
	while list.size() > limit:
		list.pop_back()

func _decision_target_ref(decision: Dictionary) -> String:
	for key in ["target_nav_point", "target_object", "action"]:
		var text := String(decision.get(key, "")).strip_edges()
		if not text.is_empty():
			return text
	return ""

func _is_ref_on_cooldown(target_ref: String, context: Dictionary) -> bool:
	if target_ref.is_empty():
		return false
	if _target_cooldowns.has(target_ref) and float(_target_cooldowns[target_ref]) > 0.0:
		return true
	var context_cooldowns: Variant = context.get("target_cooldowns", {})
	if context_cooldowns is Dictionary:
		var cooldowns := context_cooldowns as Dictionary
		return cooldowns.has(target_ref) and float(cooldowns[target_ref]) > 0.0
	return false

func _tick_target_cooldowns(delta: float) -> void:
	if _target_cooldowns.is_empty():
		return
	var expired: Array = []
	for key in _target_cooldowns.keys():
		var next_value := maxf(0.0, float(_target_cooldowns[key]) - delta)
		if next_value <= 0.0:
			expired.append(key)
		else:
			_target_cooldowns[key] = next_value
	for key in expired:
		_target_cooldowns.erase(key)

func _get_mind_snapshot() -> Dictionary:
	if _mind_state != null and _mind_state.has_method("get_state_snapshot"):
		var value: Variant = _mind_state.call("get_state_snapshot")
		if value is Dictionary:
			return value as Dictionary
	return {"curiosity": 0.4, "tiredness": 0.2, "boredom": 0.4, "social": 0.3, "duty": 0.3, "caution": 0.1}

func _get_perception_snapshot(context: Dictionary) -> Dictionary:
	if context.has("perception") and context["perception"] is Dictionary:
		return context["perception"] as Dictionary
	if context.get("blackboard", {}) is Dictionary:
		var blackboard := context.get("blackboard", {}) as Dictionary
		if blackboard.get("perception", {}) is Dictionary:
			return blackboard.get("perception", {}) as Dictionary
	if _perception_component != null and _perception_component.has_method("build_perception_snapshot"):
		var value: Variant = _perception_component.call("build_perception_snapshot")
		if value is Dictionary:
			return value as Dictionary
	return {}

func _refresh_refs() -> void:
	_mind_state = get_node_or_null(mind_state_path) if mind_state_path != NodePath() else null
	_perception_component = get_node_or_null(perception_component_path) if perception_component_path != NodePath() else null
	_blackboard = get_node_or_null(blackboard_path) if blackboard_path != NodePath() else null
	_action_semantics = get_node_or_null(action_semantics_path) if action_semantics_path != NodePath() else null
	if _mind_state == null:
		_mind_state = _find_sibling_with_method(&"get_state_snapshot")
	if _perception_component == null:
		_perception_component = _find_sibling_with_method(&"build_perception_snapshot")
	if _blackboard == null:
		_blackboard = _find_sibling_with_method(&"build_blackboard_snapshot")
	if _action_semantics == null:
		_action_semantics = _find_sibling_with_method(&"get_action_semantics")

func _find_sibling_with_method(method_name: StringName) -> Node:
	var parent_node := get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var node := child as Node
		if node != null and node != self and node.has_method(method_name):
			return node
	return null

func _entry_ref(entry: Dictionary) -> String:
	for key in ["id", "object_id", "name"]:
		var text := String(entry.get(key, "")).strip_edges()
		if not text.is_empty():
			return text
	return ""

func _has_any_tag(entry: Dictionary, tag_list: PackedStringArray) -> bool:
	var tags: Variant = entry.get("tags", [])
	if tags is not Array and tags is not PackedStringArray:
		return false
	for tag in tags:
		var tag_text := String(tag).strip_edges().to_lower()
		for wanted in tag_list:
			if tag_text == String(wanted).strip_edges().to_lower():
				return true
	return false

func _log(message: String) -> void:
	if debug_log:
		print("[CharacterAutonomousPlanner] %s" % message)
