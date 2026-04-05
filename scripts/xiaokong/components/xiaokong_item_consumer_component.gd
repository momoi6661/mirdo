extends Node
class_name XiaokongItemConsumerComponent

signal item_consumed(item_name: String, applied_delta: Dictionary, suggested_action: StringName)

@export var state_component_path: NodePath

var _state_component: XiaokongStateComponent

func _ready() -> void:
	_state_component = get_node_or_null(state_component_path) as XiaokongStateComponent
	if _state_component == null:
		_state_component = _find_state_component()

func consume_item(item_data: Resource, reason: String = "consume_item") -> Dictionary:
	if item_data == null:
		return {"ok": false, "error": "item_data_is_null"}

	if _state_component == null:
		_state_component = _find_state_component()
		if _state_component == null:
			return {"ok": false, "error": "state_component_not_found"}

	var effect = _extract_effect(item_data)
	if effect == null:
		return {"ok": false, "error": "item_has_no_consumable_effect"}

	var delta = effect.to_stat_delta()
	if effect.bonus_mood_when_need_critical != 0 and _is_need_critical():
		delta["mood"] = float(delta.get("mood", 0.0)) + float(effect.bonus_mood_when_need_critical)

	var applied_delta = _state_component.apply_delta(delta, reason)
	var suggested_action: StringName = &""
	var item_name = _get_item_name(item_data)

	item_consumed.emit(item_name, applied_delta, suggested_action)
	return {
		"ok": true,
		"item_name": item_name,
		"applied_delta": applied_delta,
		"suggested_action": String(suggested_action),
	}

func consume_item_and_trigger_action(item_data: Resource, action_controller: Node, reason: String = "consume_item") -> Dictionary:
	var result = consume_item(item_data, reason)
	if not bool(result.get("ok", false)):
		return result

	if action_controller != null and action_controller.has_method("trigger_action"):
		var action_name = StringName(String(result.get("suggested_action", "")))
		if action_name != &"":
			action_controller.call("trigger_action", action_name)

	return result

func _extract_effect(item_data: Resource) -> XiaokongStatModifier:
	if item_data is ItemData:
		return (item_data as ItemData).consumable_effect

	var effect_value: Variant = item_data.get("consumable_effect")
	if effect_value is XiaokongStatModifier:
		return effect_value as XiaokongStatModifier
	return null

func _get_item_name(item_data: Resource) -> String:
	if item_data is ItemData:
		return String((item_data as ItemData).ItemName)

	if item_data.has_method("get"):
		var name_value: Variant = item_data.get("ItemName")
		if name_value != null:
			return String(name_value)

	return item_data.resource_name if not item_data.resource_name.is_empty() else "unknown_item"

func _is_need_critical() -> bool:
	if _state_component == null:
		return false
	return _state_component.is_critical(&"hunger") or _state_component.is_critical(&"thirst")

func _find_state_component() -> XiaokongStateComponent:
	var parent_node = get_parent()
	if parent_node == null:
		return null

	for child in parent_node.get_children():
		var state = child as XiaokongStateComponent
		if state != null:
			return state

	return null
