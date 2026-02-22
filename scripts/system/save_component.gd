extends Node
class_name SaveComponent

@export var unique_id: String = ""

func _ready() -> void:
	if unique_id.is_empty():
		unique_id = get_parent().name
	add_to_group("SavableComponent")

func get_save_data() -> Dictionary:
	var parent = get_parent()
	var data = {
		"unique_id": unique_id,
		"transform": parent.global_transform if parent is Node3D else null
	}
	if parent.has_method("_get_custom_save_data"):
		data["custom"] = parent._get_custom_save_data()
	return data

func load_save_data(data: Dictionary) -> void:
	var parent = get_parent()
	if data.has("transform") and data["transform"] != null and parent is Node3D:
		parent.global_transform = data["transform"]
	if data.has("custom") and parent.has_method("_load_custom_save_data"):
		parent._load_custom_save_data(data["custom"])
