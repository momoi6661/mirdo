@tool
extends Resource
class_name XiaokongStatusValueStateResource

enum Comparator {
	LESS_THAN_OR_EQUAL,
	GREATER_THAN_OR_EQUAL,
}

@export var id: StringName
@export_enum("hunger", "thirst", "mood", "favor") var stat_key: String = "hunger"
@export var label_text: String = ""
@export var display_text: String = ""
@export var enabled: bool = true
@export var is_default: bool = false
@export var compare: Comparator = Comparator.LESS_THAN_OR_EQUAL
@export_range(0.0, 100.0, 0.1) var threshold_value: float = 0.0

func matches_snapshot(snapshot: Dictionary) -> bool:
	if not enabled or is_default:
		return false
	var current_value: float = float(snapshot.get(stat_key, 0.0))
	match compare:
		Comparator.LESS_THAN_OR_EQUAL:
			return current_value <= threshold_value
		Comparator.GREATER_THAN_OR_EQUAL:
			return current_value >= threshold_value
		_:
			return false
