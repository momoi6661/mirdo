extends Resource
class_name OutingMapProgressResource

@export var unlocked_location_ids: PackedStringArray = PackedStringArray()
@export var discovered_unlock_keys: PackedStringArray = PackedStringArray()
@export var successful_explore_counts: Dictionary = {}


func is_unlocked(location_id: String) -> bool:
	return unlocked_location_ids.has(location_id)


func unlock_location(location_id: String) -> void:
	if location_id.is_empty() or unlocked_location_ids.has(location_id):
		return
	unlocked_location_ids.append(location_id)


func remember_unlock_key(unlock_key: String) -> void:
	if unlock_key.is_empty() or discovered_unlock_keys.has(unlock_key):
		return
	discovered_unlock_keys.append(unlock_key)


func record_success(location_id: String) -> int:
	var next_count := int(successful_explore_counts.get(location_id, 0)) + 1
	successful_explore_counts[location_id] = next_count
	return next_count
