extends Node
class_name CharacterCompanionDirectorComponent

@export var rest_tags: PackedStringArray = PackedStringArray(["rest", "seat", "bed"])
@export var inspect_tags: PackedStringArray = PackedStringArray(["wander", "patrol", "inspect", "storage", "supplies", "food", "medical", "equipment", "tool", "material", "cabinet"])
@export var ambient_actions: PackedStringArray = PackedStringArray(["idle_fidget", "look_around", "curious_peek", "tilt_head_cute", "small_happy_bounce"])
@export var perception_component_path: NodePath
@export var action_router_path: NodePath
@export var action_controller_path: NodePath
@export var autonomous_movement_enabled: bool = true
@export_range(0.05, 30.0, 0.05) var autonomous_tick_interval_sec: float = 2.0
@export var autonomous_rest_command: StringName = &"go_to_object"
@export var autonomous_rest_marker_role: StringName = &"sit"
@export_range(0.0, 120.0, 0.1) var manual_grace_period_sec: float = 10.0
@export_range(0.0, 120.0, 0.1) var external_action_grace_period_sec: float = 12.0
@export_range(0.0, 120.0, 0.1) var movement_cooldown_sec: float = 8.0
@export_range(0.0, 300.0, 0.1) var rest_repeat_suppression_sec: float = 60.0
@export_range(0.0, 300.0, 0.1) var speech_cooldown_sec: float = 30.0
@export_range(0.0, 300.0, 0.1) var startup_autonomous_grace_sec: float = 30.0
@export_range(0.0, 1.0, 0.01) var autonomous_rest_chance: float = 0.18
@export_range(0.0, 1.0, 0.01) var autonomous_ambient_chance_when_no_object: float = 0.85

var _perception_component: Node
var _action_router: Node
var _action_controller: Node
var _rng := RandomNumberGenerator.new()
var _autonomous_tick_left: float = 0.0
var _manual_grace_left: float = 0.0
var _external_action_grace_left: float = 0.0
var _movement_cooldown_left: float = 0.0
var _rest_repeat_suppression_left: float = 0.0
var _speech_cooldown_left: float = 0.0
var _last_autonomous_target_id: String = ""
var _last_autonomous_target_ref: String = ""
var _last_ambient_action: String = ""

func _ready() -> void:
	_rng.randomize()
	_refresh_refs()
	_autonomous_tick_left = maxf(0.05, autonomous_tick_interval_sec)
	_manual_grace_left = maxf(_manual_grace_left, startup_autonomous_grace_sec)

func _process(delta: float) -> void:
	_manual_grace_left = maxf(0.0, _manual_grace_left - delta)
	_external_action_grace_left = maxf(0.0, _external_action_grace_left - delta)
	_movement_cooldown_left = maxf(0.0, _movement_cooldown_left - delta)
	_rest_repeat_suppression_left = maxf(0.0, _rest_repeat_suppression_left - delta)
	_speech_cooldown_left = maxf(0.0, _speech_cooldown_left - delta)
	if not autonomous_movement_enabled:
		return
	_autonomous_tick_left = maxf(0.0, _autonomous_tick_left - delta)
	if _autonomous_tick_left > 0.0:
		return
	_autonomous_tick_left = maxf(0.05, autonomous_tick_interval_sec)
	_try_dispatch_autonomous_movement()

func notify_manual_control() -> void:
	_manual_grace_left = manual_grace_period_sec

func notify_external_ai_action(ai_data: Dictionary = {}) -> void:
	if _is_autonomous_source(ai_data):
		return
	_external_action_grace_left = external_action_grace_period_sec
	_rest_repeat_suppression_left = 0.0

func can_start_autonomous_movement() -> bool:
	return _manual_grace_left <= 0.0 \
		and _external_action_grace_left <= 0.0 \
		and _movement_cooldown_left <= 0.0 \
		and _rest_repeat_suppression_left <= 0.0 \
		and not _is_action_controller_busy()

func mark_autonomous_movement_started() -> void:
	_movement_cooldown_left = movement_cooldown_sec
	_rest_repeat_suppression_left = rest_repeat_suppression_sec

func can_speak_hint() -> bool:
	return _manual_grace_left <= 0.0 and _speech_cooldown_left <= 0.0

func mark_hint_spoken() -> void:
	_speech_cooldown_left = speech_cooldown_sec

func _try_dispatch_autonomous_movement() -> void:
	if not can_start_autonomous_movement():
		return
	_refresh_refs()
	if _perception_component == null or not _perception_component.has_method("build_perception_snapshot"):
		return
	if _action_router == null or not _action_router.has_method("apply_ai_response"):
		return

	var snapshot_value: Variant = _perception_component.call("build_perception_snapshot")
	if snapshot_value is not Dictionary:
		return
	var target_object: Dictionary = pick_preferred_activity_object(snapshot_value as Dictionary)
	if target_object.is_empty():
		_try_dispatch_ambient_action()
		return

	var target_ref: String = _extract_object_ref(target_object)
	if target_ref.is_empty():
		return
	var payload: Dictionary = {
		"command": "go_to_object",
		"target_object": target_ref,
		"marker_role": _choose_activity_marker_role(target_object),
		"autonomous_kind": String(target_object.get("autonomous_kind", "wander")),
		"source": "autonomous_companion",
	}
	_action_router.call("apply_ai_response", payload)
	_last_autonomous_target_id = target_ref
	_last_autonomous_target_ref = target_ref
	mark_autonomous_movement_started()

func pick_preferred_rest_object(snapshot: Dictionary) -> Dictionary:
	var objects: Array = snapshot.get("nearby_objects", [])
	var best: Dictionary = {}
	var best_distance := INF
	for entry in objects:
		if entry is not Dictionary:
			continue
		var object_entry: Dictionary = entry
		if not _has_any_rest_tag(object_entry):
			continue
		var distance := float(object_entry.get("distance", INF))
		if distance < best_distance:
			best_distance = distance
			best = object_entry.duplicate(true)
	return best

func pick_preferred_activity_object(snapshot: Dictionary) -> Dictionary:
	var objects: Array = snapshot.get("nearby_objects", [])
	var last_target := _last_autonomous_target_ref if not _last_autonomous_target_ref.is_empty() else _last_autonomous_target_id
	var inspect_candidates: Array[Dictionary] = []
	var rest_candidates: Array[Dictionary] = []
	for entry in objects:
		if entry is not Dictionary:
			continue
		var object_entry: Dictionary = entry
		if _extract_object_ref(object_entry) == last_target:
			continue
		if _has_any_inspect_tag(object_entry):
			inspect_candidates.append(object_entry)
		elif _has_any_rest_tag(object_entry):
			rest_candidates.append(object_entry)
	if not inspect_candidates.is_empty():
		var inspect_target := _pick_weighted_nearest(inspect_candidates)
		inspect_target["autonomous_kind"] = "wander"
		return inspect_target
	if not rest_candidates.is_empty() and _rest_repeat_suppression_left <= 0.0:
		# 没有可检查目标时，休息点是唯一自然的自主活动，不再被随机数吞掉。
		var rest_target := _pick_weighted_nearest(rest_candidates, false)
		rest_target["autonomous_kind"] = "rest"
		return rest_target
	return {}

## 兼容语义测试与旧调用方：自主行为统一走同一套活动选择规则。
func pick_preferred_autonomous_object(snapshot: Dictionary) -> Dictionary:
	var target := pick_preferred_activity_object(snapshot)
	if not target.is_empty() and not target.has("autonomous_kind"):
		target["autonomous_kind"] = "wander"
	return target

func _try_dispatch_ambient_action() -> void:
	if ambient_actions.is_empty():
		return
	if _rng.randf() > autonomous_ambient_chance_when_no_object:
		return
	var action := _pick_ambient_action()
	if action.is_empty():
		return
	_action_router.call("apply_ai_response", {
		"action": action,
		"source": "autonomous_companion",
	})
	_last_ambient_action = action
	mark_autonomous_movement_started()

func _pick_weighted_nearest(candidates: Array[Dictionary], allow_variation: bool = true) -> Dictionary:
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var score_a := float(a.get("distance", 9999.0)) - float(a.get("priority", 0)) * 0.5
		var score_b := float(b.get("distance", 9999.0)) - float(b.get("priority", 0)) * 0.5
		return score_a < score_b
	)
	var pool_size := mini(candidates.size(), 3)
	var selected_index := _rng.randi_range(0, pool_size - 1) if allow_variation else 0
	return candidates[selected_index].duplicate(true)

func _pick_ambient_action() -> String:
	var candidates: Array[String] = []
	for action in ambient_actions:
		var clean := String(action).strip_edges()
		if clean.is_empty() or clean == _last_ambient_action:
			continue
		candidates.append(clean)
	if candidates.is_empty():
		return String(ambient_actions[0]).strip_edges()
	return candidates[_rng.randi_range(0, candidates.size() - 1)]

func _has_any_rest_tag(entry: Dictionary) -> bool:
	var tags: Array = entry.get("tags", [])
	for tag in tags:
		var tag_text := String(tag)
		for rest_tag in rest_tags:
			if tag_text == String(rest_tag):
				return true
	return false

func _has_any_inspect_tag(entry: Dictionary) -> bool:
	var tags: Array = entry.get("tags", [])
	var actions: Array = entry.get("actions", [])
	for action in actions:
		var action_text := String(action).to_lower()
		if action_text.find("inspect") >= 0 or action_text.find("open") >= 0 or action_text.find("check") >= 0:
			return true
	for tag in tags:
		var tag_text := String(tag)
		for inspect_tag in inspect_tags:
			if tag_text == String(inspect_tag):
				return true
	return false

func _refresh_refs() -> void:
	_perception_component = null
	_action_router = null
	_action_controller = null
	if perception_component_path != NodePath():
		_perception_component = get_node_or_null(perception_component_path)
	if action_router_path != NodePath():
		_action_router = get_node_or_null(action_router_path)
	if action_controller_path != NodePath():
		_action_controller = get_node_or_null(action_controller_path)

func _extract_object_ref(entry: Dictionary) -> String:
	for key in ["id", "object_id", "name"]:
		var value: String = String(entry.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return ""

func _choose_rest_marker_role(entry: Dictionary) -> String:
	var preferred_role: String = String(autonomous_rest_marker_role).strip_edges()
	var marker_roles: Dictionary = entry.get("marker_roles", {})
	if not preferred_role.is_empty() and (marker_roles.is_empty() or marker_roles.has(preferred_role)):
		return preferred_role
	if marker_roles.has("approach"):
		return "approach"
	if not marker_roles.is_empty():
		return String(marker_roles.keys()[0])
	return preferred_role if not preferred_role.is_empty() else "approach"

func _choose_activity_marker_role(entry: Dictionary) -> String:
	if _has_any_rest_tag(entry) and not _has_any_inspect_tag(entry):
		return _choose_rest_marker_role(entry)
	var marker_roles: Dictionary = entry.get("marker_roles", {})
	if marker_roles.has("open"):
		return "open"
	if marker_roles.has("look"):
		return "look"
	if marker_roles.has("approach"):
		return "approach"
	if not marker_roles.is_empty():
		return String(marker_roles.keys()[0])
	return "approach"

func _is_action_controller_busy() -> bool:
	_refresh_refs()
	if _action_controller == null:
		return false
	if _action_controller.has_method("is_navigating") and bool(_action_controller.call("is_navigating")):
		return true
	if _action_controller.has_method("get_current_state_name"):
		var state_name := StringName(_action_controller.call("get_current_state_name"))
		if state_name == &"SittingIdle" or state_name == &"SitDown" or state_name == &"SitToStand" or state_name == &"Laying" or state_name == &"LayDown" or state_name == &"LayUp":
			return true
	return false

func _is_autonomous_source(ai_data: Dictionary) -> bool:
	return String(ai_data.get("source", "")).strip_edges() == "autonomous_companion"
