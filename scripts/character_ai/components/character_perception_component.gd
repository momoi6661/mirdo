extends Node
class_name CharacterPerceptionComponent

@export var observer_path: NodePath
@export_range(0.1, 100.0, 0.1) var scan_radius: float = 8.0
@export_range(1, 64, 1) var max_objects: int = 12
@export_range(1, 64, 1) var max_areas: int = 6
@export_range(1, 64, 1) var max_visible_items: int = 8
@export var world_object_group: StringName = &"ai_world_object"
@export var perception_area_group: StringName = &"ai_perception_area"

func build_perception_snapshot() -> Dictionary:
	var observer := _resolve_observer()
	return {
		"nearby_objects": _collect_nearby_objects(observer),
		"areas": _collect_nearby_areas(observer),
		"visible_items": [],
	}

func _resolve_observer() -> Node3D:
	if observer_path != NodePath():
		var by_path := get_node_or_null(observer_path) as Node3D
		if by_path != null:
			return by_path
	var parent_node := get_parent() as Node3D
	if parent_node != null:
		return parent_node
	return null

func _collect_nearby_objects(observer: Node3D) -> Array:
	var entries: Array = []
	var tree := get_tree()
	if tree == null:
		return entries
	for candidate in tree.get_nodes_in_group(world_object_group):
		var node := candidate as Node3D
		if node == null or not is_instance_valid(node):
			continue
		if not _is_within_radius(observer, node):
			continue
		if not node.has_method("build_ai_object_summary"):
			continue
		var summary_value: Variant = node.call("build_ai_object_summary", observer)
		if summary_value is Dictionary:
			entries.append((summary_value as Dictionary).duplicate(true))
	_sort_by_distance(entries)
	return entries.slice(0, mini(max_objects, entries.size()))

func _collect_nearby_areas(observer: Node3D) -> Array:
	var entries: Array = []
	var tree := get_tree()
	if tree == null:
		return entries
	for candidate in tree.get_nodes_in_group(perception_area_group):
		var node := candidate as Node3D
		if node == null or not is_instance_valid(node):
			continue
		if not _is_within_radius(observer, node):
			continue
		if not node.has_method("build_ai_area_summary"):
			continue
		var summary_value: Variant = node.call("build_ai_area_summary", observer)
		if summary_value is Dictionary:
			entries.append((summary_value as Dictionary).duplicate(true))
	_sort_by_distance(entries)
	return entries.slice(0, mini(max_areas, entries.size()))

func _is_within_radius(observer: Node3D, target: Node3D) -> bool:
	if observer == null or target == null:
		return true
	return observer.global_position.distance_to(target.global_position) <= scan_radius

func _sort_by_distance(entries: Array) -> void:
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("distance", 0.0)) < float(b.get("distance", 0.0))
	)

