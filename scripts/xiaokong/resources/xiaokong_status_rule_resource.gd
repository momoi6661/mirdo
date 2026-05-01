@tool
extends Resource
class_name XiaokongStatusRuleResource

enum Comparator {
	LESS_THAN_OR_EQUAL,
	GREATER_THAN_OR_EQUAL,
}

@export var id: StringName
@export var display_text: String = ""
@export var enabled: bool = true

@export_group("Hunger")
@export var hunger_enabled: bool = false
@export var hunger_compare: Comparator = Comparator.LESS_THAN_OR_EQUAL
@export_range(0.0, 100.0, 0.1) var hunger_value: float = 0.0

@export_group("Thirst")
@export var thirst_enabled: bool = false
@export var thirst_compare: Comparator = Comparator.LESS_THAN_OR_EQUAL
@export_range(0.0, 100.0, 0.1) var thirst_value: float = 0.0

@export_group("Mood")
@export var mood_enabled: bool = false
@export var mood_compare: Comparator = Comparator.GREATER_THAN_OR_EQUAL
@export_range(0.0, 100.0, 0.1) var mood_value: float = 0.0

@export_group("Favor")
@export var favor_enabled: bool = false
@export var favor_compare: Comparator = Comparator.GREATER_THAN_OR_EQUAL
@export_range(0.0, 100.0, 0.1) var favor_value: float = 0.0


func matches_snapshot(snapshot: Dictionary) -> bool:
	if not enabled:
		return false
	if not _has_any_condition():
		return false
	if hunger_enabled and not _matches_value(float(snapshot.get("hunger", 0.0)), hunger_compare, hunger_value):
		return false
	if thirst_enabled and not _matches_value(float(snapshot.get("thirst", 0.0)), thirst_compare, thirst_value):
		return false
	if mood_enabled and not _matches_value(float(snapshot.get("mood", 0.0)), mood_compare, mood_value):
		return false
	if favor_enabled and not _matches_value(float(snapshot.get("favor", 0.0)), favor_compare, favor_value):
		return false
	return true


func _has_any_condition() -> bool:
	return hunger_enabled or thirst_enabled or mood_enabled or favor_enabled


func _matches_value(current_value: float, comparator: Comparator, expected_value: float) -> bool:
	match comparator:
		Comparator.LESS_THAN_OR_EQUAL:
			return current_value <= expected_value
		Comparator.GREATER_THAN_OR_EQUAL:
			return current_value >= expected_value
		_:
			return false
