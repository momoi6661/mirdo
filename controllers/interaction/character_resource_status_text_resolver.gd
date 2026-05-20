@tool
extends Node
class_name CharacterResourceStatusTextResolver

const STAT_ORDER: PackedStringArray = ["hunger", "thirst", "mood", "favor"]

@export var rule_set: Resource
@export var separator_text: String = "、"
@export var fallback_text: String = ""

func build_status_text(snapshot: Dictionary) -> String:
	var words: PackedStringArray = []

	for stat_key in STAT_ORDER:
		var current_state: Resource = _select_current_state_resource(String(stat_key), snapshot)
		var display_text: String = String(_resource_value(current_state, "display_text", "")).strip_edges()
		if not display_text.is_empty() and not words.has(display_text):
			words.append(display_text)

	for rule_resource in _get_rule_entries():
		var extra_text: String = String(_resource_value(rule_resource, "display_text", "")).strip_edges()
		if extra_text.is_empty():
			continue
		if not _rule_matches_snapshot(rule_resource, snapshot):
			continue
		if words.has(extra_text):
			continue
		words.append(extra_text)

	if words.is_empty():
		return fallback_text.strip_edges()
	return separator_text.join(words)

func _select_current_state_resource(stat_key: String, snapshot: Dictionary) -> Resource:
	var entries: Array = _get_current_state_entries()
	var fallback: Resource = null
	for entry in entries:
		var resource := entry as Resource
		if resource == null:
			continue
		if not bool(_resource_value(resource, "enabled", true)):
			continue
		if String(_resource_value(resource, "stat_key", "")).strip_edges() != stat_key:
			continue
		if bool(_resource_value(resource, "is_default", false)):
			if fallback == null:
				fallback = resource
			continue
		if _current_state_matches(resource, snapshot):
			return resource
	return fallback

func _get_current_state_entries() -> Array:
	if rule_set == null:
		return []
	if _resource_has_property(rule_set, "entries"):
		var entry_value: Variant = _resource_value(rule_set, "entries", [])
		if entry_value is Array:
			var filtered_entries: Array = []
			for entry in entry_value:
				var resource := entry as Resource
				if resource == null:
					continue
				if _resource_has_property(resource, "stat_key"):
					filtered_entries.append(resource)
			if not filtered_entries.is_empty():
				return filtered_entries
	if _resource_has_property(rule_set, "current_states"):
		var current_value: Variant = _resource_value(rule_set, "current_states", [])
		if current_value is Array:
			return current_value
	return []

func _get_rule_entries() -> Array:
	if rule_set == null:
		return []
	if _resource_has_property(rule_set, "entries"):
		var entry_value: Variant = _resource_value(rule_set, "entries", [])
		if entry_value is Array:
			var filtered_entries: Array = []
			for entry in entry_value:
				var resource := entry as Resource
				if resource == null:
					continue
				if _resource_has_property(resource, "stat_key"):
					continue
				if _resource_has_property(resource, "display_text"):
					filtered_entries.append(resource)
			if not filtered_entries.is_empty():
				return filtered_entries
	if _resource_has_property(rule_set, "rules"):
		var rules_value: Variant = _resource_value(rule_set, "rules", [])
		if rules_value is Array:
			return rules_value
	return []

func _current_state_matches(resource: Resource, snapshot: Dictionary) -> bool:
	var stat_key: String = String(_resource_value(resource, "stat_key", "")).strip_edges()
	if stat_key.is_empty():
		return false
	var current_value: float = float(snapshot.get(stat_key, 0.0))
	var compare: int = int(_resource_value(resource, "compare", 0))
	var threshold_value: float = float(_resource_value(resource, "threshold_value", 0.0))
	match compare:
		0:
			return current_value <= threshold_value
		1:
			return current_value >= threshold_value
		_:
			return false

func _rule_matches_snapshot(rule_resource: Resource, snapshot: Dictionary) -> bool:
	if rule_resource == null:
		return false
	if not bool(_resource_value(rule_resource, "enabled", true)):
		return false
	if not _rule_has_any_condition(rule_resource):
		return false
	if bool(_resource_value(rule_resource, "hunger_enabled", false)) and not _matches_rule_value(
		float(snapshot.get("hunger", 0.0)),
		int(_resource_value(rule_resource, "hunger_compare", 0)),
		float(_resource_value(rule_resource, "hunger_value", 0.0))
	):
		return false
	if bool(_resource_value(rule_resource, "thirst_enabled", false)) and not _matches_rule_value(
		float(snapshot.get("thirst", 0.0)),
		int(_resource_value(rule_resource, "thirst_compare", 0)),
		float(_resource_value(rule_resource, "thirst_value", 0.0))
	):
		return false
	if bool(_resource_value(rule_resource, "mood_enabled", false)) and not _matches_rule_value(
		float(snapshot.get("mood", 0.0)),
		int(_resource_value(rule_resource, "mood_compare", 1)),
		float(_resource_value(rule_resource, "mood_value", 0.0))
	):
		return false
	if bool(_resource_value(rule_resource, "favor_enabled", false)) and not _matches_rule_value(
		float(snapshot.get("favor", 0.0)),
		int(_resource_value(rule_resource, "favor_compare", 1)),
		float(_resource_value(rule_resource, "favor_value", 0.0))
	):
		return false
	return true

func _rule_has_any_condition(rule_resource: Resource) -> bool:
	return (
		bool(_resource_value(rule_resource, "hunger_enabled", false))
		or bool(_resource_value(rule_resource, "thirst_enabled", false))
		or bool(_resource_value(rule_resource, "mood_enabled", false))
		or bool(_resource_value(rule_resource, "favor_enabled", false))
	)

func _matches_rule_value(current_value: float, comparator: int, expected_value: float) -> bool:
	match comparator:
		0:
			return current_value <= expected_value
		1:
			return current_value >= expected_value
		_:
			return false

func _resource_has_property(resource: Resource, property_name: String) -> bool:
	if resource == null:
		return false
	for property_info_variant in resource.get_property_list():
		var property_info := property_info_variant as Dictionary
		if property_info.is_empty():
			continue
		if String(property_info.get("name", "")) == property_name:
			return true
	return false

func _resource_value(resource: Resource, property_name: String, fallback: Variant) -> Variant:
	if resource == null:
		return fallback
	if not _resource_has_property(resource, property_name):
		return fallback
	return resource.get(property_name)

