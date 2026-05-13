extends Node3D
class_name AIWorldObjectComponent

@export var object_id: StringName
@export var display_name: String = ""
@export_multiline var ai_description: String = ""
@export_enum("generic", "storage", "table", "seat", "bed", "door", "food", "tool", "weapon", "medical", "exit") var object_type: String = "generic"
@export var tags: PackedStringArray = PackedStringArray()
@export var supported_actions: PackedStringArray = PackedStringArray()
@export var nav_marker_path: NodePath
@export var look_marker_path: NodePath
@export var marker_roles: Dictionary = {}
@export var priority: int = 0
@export var enabled: bool = true

func _ready() -> void:
	if enabled and not is_in_group("ai_world_object"):
		add_to_group("ai_world_object")

func build_ai_object_summary(observer: Node3D = null) -> Dictionary:
	var summary := {
		"id": _resolve_object_id(),
		"name": _resolve_display_name(),
		"type": object_type,
		"description": ai_description.strip_edges(),
		"tags": _packed_to_array(tags),
		"actions": _packed_to_array(supported_actions),
		"priority": priority,
		"path": String(get_path()) if is_inside_tree() else "",
		"marker_roles": _build_marker_role_paths(),
	}
	if observer != null and observer is Node3D:
		summary["distance"] = observer.global_position.distance_to(global_position)
	else:
		summary["distance"] = 0.0
	var nav_marker := get_nav_marker()
	if nav_marker != null:
		summary["nav_marker_path"] = String(nav_marker.get_path())
	var look_marker := get_look_marker()
	if look_marker != null:
		summary["look_marker_path"] = String(look_marker.get_path())
	return summary

func get_nav_marker() -> Marker3D:
	if nav_marker_path != NodePath():
		var marker := get_node_or_null(nav_marker_path) as Marker3D
		if marker != null:
			return marker
	return get_marker_for_role("approach")

func get_look_marker() -> Marker3D:
	if look_marker_path != NodePath():
		var marker := get_node_or_null(look_marker_path) as Marker3D
		if marker != null:
			return marker
	return get_marker_for_role("look")

func get_marker_for_role(role: String) -> Marker3D:
	var clean_role := role.strip_edges()
	if clean_role.is_empty() or not marker_roles.has(clean_role):
		return null
	var raw_value: Variant = marker_roles.get(clean_role)
	var path := NodePath(String(raw_value))
	if raw_value is NodePath:
		path = raw_value
	if path == NodePath():
		return null
	return get_node_or_null(path) as Marker3D

func supports_action(action_name: StringName) -> bool:
	var clean := String(action_name).strip_edges()
	if clean.is_empty():
		return false
	for action in supported_actions:
		if String(action) == clean:
			return true
	return false

func _resolve_object_id() -> String:
	var clean_id := String(object_id).strip_edges()
	if not clean_id.is_empty():
		return clean_id
	return String(name)

func _resolve_display_name() -> String:
	var clean_name := display_name.strip_edges()
	if not clean_name.is_empty():
		return clean_name
	return String(name)

func _build_marker_role_paths() -> Dictionary:
	var resolved := {}
	for raw_key in marker_roles.keys():
		var role := String(raw_key).strip_edges()
		if role.is_empty():
			continue
		var marker := get_marker_for_role(role)
		if marker != null:
			resolved[role] = String(marker.get_path())
	return resolved

func _packed_to_array(values: PackedStringArray) -> Array:
	var result: Array = []
	for value in values:
		var clean := String(value).strip_edges()
		if not clean.is_empty():
			result.append(clean)
	return result
