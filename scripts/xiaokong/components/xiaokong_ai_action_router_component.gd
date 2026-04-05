extends Node
class_name XiaokongAIActionRouterComponent

signal ai_response_applied(summary: Dictionary)

const KNOWN_ACTIONS: PackedStringArray = [
	"Idle",
	"StandingGreeting",
	"Drinking",
	"Salute",
	"Kiss",
	"SittingIdle",
	"Laying",
	"LeftTurn",
	"RightTurn",
]

@export var action_controller_path: NodePath = NodePath("..")
@export var state_component_path: NodePath
@export var fallback_action: StringName = &"Idle"

@export var action_aliases: Dictionary = {
	"idle": "Idle",
	"greet": "StandingGreeting",
	"greeting": "StandingGreeting",
	"drink": "Drinking",
	"salute": "Salute",
	"kiss": "Kiss",
	"sit": "SittingIdle",
	"lay": "Laying",
	"left_turn": "LeftTurn",
	"right_turn": "RightTurn",
	"walk_to_player": "Idle",
}

var _action_controller: Node
var _state_component: XiaokongStateComponent

func _ready() -> void:
	_refresh_refs()

func apply_ai_response(final_data: Dictionary) -> Dictionary:
	_refresh_refs()

	var summary = {
		"moved": false,
		"move_target": Vector3.ZERO,
		"action_requested": "",
		"action_applied": false,
		"stat_change_applied": {},
		"errors": [],
	}

	if final_data.is_empty():
		summary["errors"].append("empty_payload")
		ai_response_applied.emit(summary)
		return summary

	var parsed_move = _parse_move_target(_extract_move_target_value(final_data))
	if parsed_move != null:
		if _action_controller != null and _action_controller.has_method("navigate_to"):
			_action_controller.call("navigate_to", parsed_move)
			summary["moved"] = true
			summary["move_target"] = parsed_move
		else:
			summary["errors"].append("action_controller_has_no_navigate_to")

	var normalized_action = _normalize_action(final_data.get("action", ""))
	if normalized_action != &"":
		summary["action_requested"] = String(normalized_action)
		if _action_controller != null and _action_controller.has_method("trigger_action"):
			summary["action_applied"] = bool(_action_controller.call("trigger_action", normalized_action))
		else:
			summary["errors"].append("action_controller_has_no_trigger_action")

	if _state_component != null and final_data.has("stat_change") and final_data["stat_change"] is Dictionary:
		var normalized_delta = _normalize_stat_change(final_data["stat_change"])
		summary["stat_change_applied"] = _state_component.apply_delta(normalized_delta, "ai_response")

	ai_response_applied.emit(summary)
	return summary

func _refresh_refs() -> void:
	_action_controller = get_node_or_null(action_controller_path)
	_state_component = get_node_or_null(state_component_path) as XiaokongStateComponent
	if _state_component == null:
		_state_component = _find_state_component()

func _extract_move_target_value(payload: Dictionary) -> Variant:
	if payload.has("move_target"):
		return payload["move_target"]
	if payload.has("target_position"):
		return payload["target_position"]
	if payload.has("nav_target"):
		return payload["nav_target"]
	return null

func _parse_move_target(value: Variant) -> Variant:
	if value == null:
		return null

	if value is Vector3:
		return value

	if value is Dictionary:
		var dict_value = value as Dictionary
		if dict_value.has("x") and dict_value.has("y") and dict_value.has("z"):
			return Vector3(float(dict_value["x"]), float(dict_value["y"]), float(dict_value["z"]))

	if value is Array:
		var arr = value as Array
		if arr.size() >= 3:
			return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))

	if value is String:
		var text = String(value).strip_edges()
		if text.is_empty():
			return null
		var parts = text.split(",", false)
		if parts.size() == 3:
			return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))

	return null

func _normalize_action(action_value: Variant) -> StringName:
	var raw = String(action_value).strip_edges()
	if raw.is_empty():
		return &""

	if KNOWN_ACTIONS.has(raw):
		return StringName(raw)

	var alias_key = raw.to_lower()
	if action_aliases.has(alias_key):
		var mapped = String(action_aliases[alias_key]).strip_edges()
		if KNOWN_ACTIONS.has(mapped):
			return StringName(mapped)

	# Unknown action falls back to Idle to keep animation safe.
	return fallback_action

func _normalize_stat_change(raw_delta: Dictionary) -> Dictionary:
	var delta = {}
	var supported = PackedStringArray(["hunger", "thirst", "mood", "favor", "ai_hunger", "ai_thirst", "ai_mood", "ai_favor"])
	for key in supported:
		if raw_delta.has(key):
			delta[key] = float(raw_delta[key])
	return delta

func _find_state_component() -> XiaokongStateComponent:
	var parent_node = get_parent()
	if parent_node == null:
		return null

	for child in parent_node.get_children():
		var state = child as XiaokongStateComponent
		if state != null:
			return state
	return null
