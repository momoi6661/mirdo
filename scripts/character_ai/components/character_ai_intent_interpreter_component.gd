extends Node
class_name CharacterAIIntentInterpreterComponent

const INTENT_FOLLOW_PLAYER := "follow_player"
const INTENT_STOP_FOLLOW := "stop_follow"
const INTENT_LOOK_AT_PLAYER := "look_at_player"
const INTENT_GO_TO_MARKER := "go_to_marker"
const INTENT_GO_TO_NAV_POINT := "go_to_nav_point"
const INTENT_GO_TO_OBJECT := "go_to_object"
const INTENT_SIT_DOWN := "sit_down"
const INTENT_STAND_UP := "stand_up"
const INTENT_PLAY_ACTION := "play_action"
const INTENT_SPEAK_HINT := "speak_hint"
const INTENT_SET_EXPRESSION := "set_expression"
const INTENT_GIVE_ITEM_TO_PLAYER := "give_item_to_player"
const INTENT_PICK_UP_ITEM := "pick_up_item"
const INTENT_USE_ITEM := "use_item"
const INTENT_EAT_ITEM := "eat_item"
const INTENT_TAKE_FROM_CONTAINER := "take_from_container"

const COMMAND_ALIASES := {
	"follow": INTENT_FOLLOW_PLAYER,
	"follow_me": INTENT_FOLLOW_PLAYER,
	"follow_player": INTENT_FOLLOW_PLAYER,
	"跟随": INTENT_FOLLOW_PLAYER,
	"跟随我": INTENT_FOLLOW_PLAYER,
	"跟着我": INTENT_FOLLOW_PLAYER,
	"跟我走": INTENT_FOLLOW_PLAYER,
	"stop_follow": INTENT_STOP_FOLLOW,
	"停止跟随": INTENT_STOP_FOLLOW,
	"别跟着我": INTENT_STOP_FOLLOW,
	"look_at_player": INTENT_LOOK_AT_PLAYER,
	"look_at_me": INTENT_LOOK_AT_PLAYER,
	"看着我": INTENT_LOOK_AT_PLAYER,
	"看我": INTENT_LOOK_AT_PLAYER,
	"面向我": INTENT_LOOK_AT_PLAYER,
	"go_to_marker": INTENT_GO_TO_MARKER,
	"goto_marker": INTENT_GO_TO_MARKER,
	"go_marker": INTENT_GO_TO_MARKER,
	"go_to_nav_point": INTENT_GO_TO_NAV_POINT,
	"goto_nav_point": INTENT_GO_TO_NAV_POINT,
	"go_nav_point": INTENT_GO_TO_NAV_POINT,
	"nav_point": INTENT_GO_TO_NAV_POINT,
	"go_to_object": INTENT_GO_TO_OBJECT,
	"goto_object": INTENT_GO_TO_OBJECT,
	"sit": INTENT_SIT_DOWN,
	"sit_down": INTENT_SIT_DOWN,
	"坐下": INTENT_SIT_DOWN,
	"坐着": INTENT_SIT_DOWN,
	"stand": INTENT_STAND_UP,
	"stand_up": INTENT_STAND_UP,
	"起身": INTENT_STAND_UP,
	"play_action": INTENT_PLAY_ACTION,
	"speak_hint": INTENT_SPEAK_HINT,
	"set_expression": INTENT_SET_EXPRESSION,
	"give_item": INTENT_GIVE_ITEM_TO_PLAYER,
	"give_item_to_player": INTENT_GIVE_ITEM_TO_PLAYER,
	"offer_item": INTENT_GIVE_ITEM_TO_PLAYER,
	"offer_item_to_player": INTENT_GIVE_ITEM_TO_PLAYER,
	"递给玩家": INTENT_GIVE_ITEM_TO_PLAYER,
	"给玩家物品": INTENT_GIVE_ITEM_TO_PLAYER,
	"给我物品": INTENT_GIVE_ITEM_TO_PLAYER,
	"pick_up_item": INTENT_PICK_UP_ITEM,
	"pickup_item": INTENT_PICK_UP_ITEM,
	"take_item": INTENT_PICK_UP_ITEM,
	"pick_up": INTENT_PICK_UP_ITEM,
	"拿起": INTENT_PICK_UP_ITEM,
	"拾取": INTENT_PICK_UP_ITEM,
	"拿物品": INTENT_PICK_UP_ITEM,
	"take_from_container": INTENT_TAKE_FROM_CONTAINER,
	"take_from_storage": INTENT_TAKE_FROM_CONTAINER,
	"从容器拿取": INTENT_TAKE_FROM_CONTAINER,
	"use_item": INTENT_USE_ITEM,
	"使用物品": INTENT_USE_ITEM,
	"使用": INTENT_USE_ITEM,
	"eat_item": INTENT_EAT_ITEM,
	"吃掉": INTENT_EAT_ITEM,
	"吃": INTENT_EAT_ITEM,
}

func interpret_payload(payload: Dictionary) -> Dictionary:
	var command_value: Variant = _extract_command_value(payload)
	var intent := _normalize_intent(command_value)
	if intent.is_empty():
		return {
			"ok": false,
			"intent": "",
			"error": "unsupported_intent",
			"raw": payload.duplicate(true),
		}
	var result := {
		"ok": true,
		"intent": intent,
		"target_ref": _extract_target_ref(payload),
		"target_nav_point": _extract_target_nav_point(payload),
		"marker_role": String(payload.get("marker_role", payload.get("role", ""))).strip_edges(),
		"action": String(payload.get("action", "")).strip_edges(),
		"item_id": _extract_item_id(payload),
		"item_path": _extract_item_path(payload),
		"amount": int(payload.get("amount", payload.get("count", 1))),
		"source": String(payload.get("source", "payload")).strip_edges(),
		"raw": payload.duplicate(true),
	}
	if String(result["marker_role"]).is_empty():
		result["marker_role"] = "approach"
	return result

func _extract_command_value(payload: Dictionary) -> Variant:
	for key in ["intent", "command", "navigation_command", "task", "operation", "navigation_intent"]:
		if payload.has(key):
			return payload[key]
	if payload.has("action"):
		var action_value: Variant = payload["action"]
		if not _normalize_intent(action_value).is_empty():
			return action_value
	for nested_key in ["action_hint", "navigation", "intent_payload", "command_payload"]:
		var nested_value: Variant = payload.get(nested_key, null)
		if nested_value is Dictionary:
			var nested_command: Variant = _extract_command_value(nested_value as Dictionary)
			if nested_command != null:
				return nested_command
	return null

func _normalize_intent(value: Variant) -> String:
	if value == null:
		return ""
	var raw: String = ""
	if value is Dictionary:
		for key in ["name", "intent", "command", "type", "task"]:
			if (value as Dictionary).has(key):
				raw = String((value as Dictionary)[key]).strip_edges()
				if not raw.is_empty():
					break
	else:
		raw = String(value).strip_edges()
	if raw.is_empty():
		return ""
	var key: String = _canonicalize(raw)
	if COMMAND_ALIASES.has(key):
		return String(COMMAND_ALIASES[key])
	return _guess_intent(raw, key)

func _guess_intent(raw: String, canonical: String) -> String:
	var lower: String = raw.to_lower()
	if canonical.contains("stop") and canonical.contains("follow"):
		return INTENT_STOP_FOLLOW
	if canonical.contains("follow"):
		return INTENT_FOLLOW_PLAYER
	if canonical.contains("look") and (canonical.contains("player") or canonical.contains("me")):
		return INTENT_LOOK_AT_PLAYER
	if canonical.contains("go_to_object") or canonical.contains("object"):
		return INTENT_GO_TO_OBJECT
	if canonical.contains("nav_point"):
		return INTENT_GO_TO_NAV_POINT
	if canonical.contains("go_to") or canonical.contains("marker"):
		return INTENT_GO_TO_MARKER
	if canonical.contains("give") and (canonical.contains("item") or canonical.contains("player")):
		return INTENT_GIVE_ITEM_TO_PLAYER
	if canonical.contains("offer") and canonical.contains("item"):
		return INTENT_GIVE_ITEM_TO_PLAYER
	if canonical.contains("take_from_container") or canonical.contains("take_from_storage"):
		return INTENT_TAKE_FROM_CONTAINER
	if canonical.contains("pick") or canonical.contains("take_item"):
		return INTENT_PICK_UP_ITEM
	if canonical.contains("use_item"):
		return INTENT_USE_ITEM
	if canonical.contains("eat_item"):
		return INTENT_EAT_ITEM
	if lower.find("给") >= 0 and (lower.find("物品") >= 0 or lower.find("道具") >= 0):
		return INTENT_GIVE_ITEM_TO_PLAYER
	if lower.find("拿") >= 0 or lower.find("拾取") >= 0:
		return INTENT_PICK_UP_ITEM
	if lower.find("使用") >= 0:
		return INTENT_USE_ITEM
	if lower.find("吃") >= 0:
		return INTENT_EAT_ITEM
	if lower.find("停止") >= 0 and lower.find("跟") >= 0:
		return INTENT_STOP_FOLLOW
	if (lower.find("跟着") >= 0 or lower.find("跟随") >= 0) and lower.find("别") < 0:
		return INTENT_FOLLOW_PLAYER
	if lower.find("看着我") >= 0 or lower.find("看我") >= 0 or lower.find("面向我") >= 0:
		return INTENT_LOOK_AT_PLAYER
	if lower.find("坐下") >= 0 or lower.find("坐着") >= 0:
		return INTENT_SIT_DOWN
	return ""

func _extract_item_id(payload: Dictionary) -> String:
	for key in ["item_id", "item", "given_item", "gift_item", "target_item"]:
		if payload.has(key):
			return String(payload[key]).strip_edges()
	var command_value: Variant = payload.get("command", null)
	if command_value is Dictionary:
		return _extract_item_id(command_value as Dictionary)
	for nested_key in ["action_hint", "intent_payload", "command_payload", "payload", "parameters", "args"]:
		var nested_value: Variant = payload.get(nested_key, null)
		if nested_value is Dictionary:
			var nested_item := _extract_item_id(nested_value as Dictionary)
			if not nested_item.is_empty():
				return nested_item
	return ""

func _extract_item_path(payload: Dictionary) -> String:
	for key in ["item_path", "item_resource", "item_res", "resource_path"]:
		if payload.has(key):
			return String(payload[key]).strip_edges()
	var command_value: Variant = payload.get("command", null)
	if command_value is Dictionary:
		return _extract_item_path(command_value as Dictionary)
	for nested_key in ["action_hint", "intent_payload", "command_payload", "payload", "parameters", "args"]:
		var nested_value: Variant = payload.get(nested_key, null)
		if nested_value is Dictionary:
			var nested_path := _extract_item_path(nested_value as Dictionary)
			if not nested_path.is_empty():
				return nested_path
	return ""

func _extract_target_nav_point(payload: Dictionary) -> String:
	for key in ["target_nav_point", "nav_point", "nav_point_id", "target_point", "point_id"]:
		if payload.has(key):
			return String(payload[key]).strip_edges()
	var command_value: Variant = payload.get("command", null)
	if command_value is Dictionary:
		return _extract_target_nav_point(command_value as Dictionary)
	for nested_key in ["action_hint", "navigation", "intent_payload", "command_payload", "payload", "parameters", "args"]:
		var nested_value: Variant = payload.get(nested_key, null)
		if nested_value is Dictionary:
			var nested_target := _extract_target_nav_point(nested_value as Dictionary)
			if not nested_target.is_empty():
				return nested_target
	return ""

func _extract_target_ref(payload: Dictionary) -> String:
	for key in ["target_ref", "target_object", "object_id", "target_marker_path", "marker_path", "target_marker", "marker", "marker_name", "target_marker_name"]:
		if payload.has(key):
			return String(payload[key]).strip_edges()
	var command_value: Variant = payload.get("command", null)
	if command_value is Dictionary:
		return _extract_target_ref(command_value as Dictionary)
	for nested_key in ["action_hint", "navigation", "intent_payload", "command_payload", "payload", "parameters", "args"]:
		var nested_value: Variant = payload.get(nested_key, null)
		if nested_value is Dictionary:
			var nested_target := _extract_target_ref(nested_value as Dictionary)
			if not nested_target.is_empty():
				return nested_target
	return ""

func _canonicalize(raw: String) -> String:
	var normalized: String = raw.strip_edges().to_lower()
	for token in [" ", "-", ".", ",", ";", ":", "/", "\\", "\n", "\t"]:
		normalized = normalized.replace(token, "_")
	while normalized.find("__") >= 0:
		normalized = normalized.replace("__", "_")
	return normalized.strip_edges()

