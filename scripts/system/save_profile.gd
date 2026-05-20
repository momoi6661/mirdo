extends Resource
class_name SaveProfile

@export var current_slot_name: String = "slot_01"
@export var last_loaded_slot_name: String = ""
@export var last_saved_unix_time: float = 0.0


func normalize() -> void:
	current_slot_name = current_slot_name.strip_edges()
	if current_slot_name.is_empty() or current_slot_name == "manual_save":
		current_slot_name = "slot_01"
	last_loaded_slot_name = last_loaded_slot_name.strip_edges()
