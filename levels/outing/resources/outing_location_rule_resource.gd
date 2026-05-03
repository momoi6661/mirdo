extends Resource
class_name OutingLocationRuleResource

@export var location_id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var map_position: Vector2 = Vector2.ZERO
@export var icon_text: String = "LOC"
@export_range(0, 5, 1) var threat_level: int = 1
@export var travel_minutes: int = 120
@export var discoverable: bool = false
@export var start_unlocked: bool = false
@export var neighbor_location_ids: PackedStringArray = PackedStringArray()
@export var loot_bias_tags: PackedStringArray = PackedStringArray()
@export var recommended_auxiliary_tools: PackedStringArray = PackedStringArray()
@export var detail_notes: PackedStringArray = PackedStringArray()
@export_multiline var ai_exploration_rule: String = ""


func to_location_dictionary() -> Dictionary:
	return {
		"id": String(location_id),
		"name": display_name,
		"description": description,
		"position": map_position,
		"icon": icon_text,
		"threat": threat_level,
		"duration": _format_duration(),
		"loot": " / ".join(Array(loot_bias_tags)),
		"discoverable": discoverable,
		"unlocked": start_unlocked,
		"neighbors": neighbor_location_ids,
		"recommended": Array(recommended_auxiliary_tools),
		"notes": Array(detail_notes),
		"ai_rule": ai_exploration_rule,
	}


func _format_duration() -> String:
	var hours := travel_minutes / 60
	var minutes := travel_minutes % 60
	return "%02d:%02d" % [hours, minutes]
