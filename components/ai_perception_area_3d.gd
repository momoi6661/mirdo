extends Area3D
class_name AIPerceptionArea3D

@export var area_id: StringName
@export var display_name: String = ""
@export_multiline var ai_description: String = ""
@export var tags: PackedStringArray = PackedStringArray()
@export var area_actions: PackedStringArray = PackedStringArray()
@export var manual_object_paths: Array[NodePath] = []
@export var auto_collect_world_objects: bool = true
@export var enabled: bool = true

func _ready() -> void:
	if enabled and not is_in_group("ai_perception_area"):
		add_to_group("ai_perception_area")
	monitoring = true

func build_ai_area_summary(observer: Node3D = null) -> Dictionary:
	var summary := {
		"id": _resolve_area_id(),
		"name": _resolve_display_name(),
		"description": ai_description.strip_edges(),
		"tags": _packed_to_array(tags),
		"actions": _packed_to_array(area_actions),
		"path": String(get_path()) if is_inside_tree() else "",
		"object_paths": _resolve_manual_object_paths(),
	}
	if observer != null and observer is Node3D and observer.is_inside_tree() and is_inside_tree():
		summary["distance"] = observer.global_position.distance_to(global_position)
	else:
		summary["distance"] = 0.0
	return summary

func _resolve_area_id() -> String:
	var clean_id := String(area_id).strip_edges()
	if not clean_id.is_empty():
		return clean_id
	return String(name)

func _resolve_display_name() -> String:
	var clean_name := display_name.strip_edges()
	if not clean_name.is_empty():
		return clean_name
	return String(name)

func _resolve_manual_object_paths() -> Array:
	var result: Array = []
	for object_path in manual_object_paths:
		if object_path == NodePath():
			continue
		var node := get_node_or_null(object_path)
		if node != null:
			result.append(String(node.get_path()))
	return result

func _packed_to_array(values: PackedStringArray) -> Array:
	var result: Array = []
	for value in values:
		var clean := String(value).strip_edges()
		if not clean.is_empty():
			result.append(clean)
	return result
