extends Node
class_name CharacterPerceptionComponent

@export var observer_path: NodePath
@export var vision_area_path: NodePath
@export_range(0.1, 100.0, 0.1) var scan_radius: float = 8.0
@export_range(1, 64, 1) var max_objects: int = 12
@export_range(1, 64, 1) var max_areas: int = 6
@export_range(1, 64, 1) var max_visible_items: int = 8
@export var world_object_group: StringName = &"ai_world_object"
@export var perception_area_group: StringName = &"ai_perception_area"
@export var nav_point_group: StringName = &"ai_nav_point"
@export var prefer_vision_area_overlap: bool = true
@export var fallback_radius_scan: bool = true
@export var include_known_nav_points: bool = true
@export_range(1, 128, 1) var max_known_nav_points: int = 64

func build_perception_snapshot() -> Dictionary:
	var observer := _resolve_observer()
	var proxy_snapshot := _build_proxy_snapshot(observer)
	if not proxy_snapshot.is_empty():
		return _with_known_nav_points(proxy_snapshot, observer)
	var vision := {
		"source": "CharacterPerceptionComponent",
		"nearby_objects": _collect_nearby_objects(observer),
		"areas": _collect_nearby_areas(observer),
		"visible_items": [],
	}
	return _with_known_nav_points(vision, observer)

func _build_proxy_snapshot(observer: Node3D) -> Dictionary:
	if not prefer_vision_area_overlap:
		return {}
	var area := _resolve_vision_area()
	if area == null:
		return {}
	if area.has_method("build_vision_snapshot"):
		var value: Variant = area.call("build_vision_snapshot", observer)
		if value is Dictionary:
			var snapshot := (value as Dictionary).duplicate(true)
			if not snapshot.has("visible_items"):
				snapshot["visible_items"] = []
			var object_count := 0
			var area_count := 0
			if snapshot.get("nearby_objects", []) is Array:
				object_count = (snapshot.get("nearby_objects", []) as Array).size()
			if snapshot.get("areas", []) is Array:
				area_count = (snapshot.get("areas", []) as Array).size()
			if object_count > 0 or area_count > 0 or not fallback_radius_scan:
				return snapshot
	return {}

func build_known_nav_points(observer_override: Node3D = null) -> Array:
	var observer := observer_override if observer_override != null else _resolve_observer()
	return _collect_known_nav_points(observer)

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
	var seen := {}
	if prefer_vision_area_overlap:
		for node in _collect_vision_overlap_nodes(world_object_group):
			if node == null or not is_instance_valid(node):
				continue
			if not node.has_method("build_ai_object_summary"):
				continue
			var summary_value: Variant = node.call("build_ai_object_summary", observer)
			if summary_value is Dictionary:
				var id := String((summary_value as Dictionary).get("id", node.get_path())).strip_edges()
				seen[id] = true
				entries.append((summary_value as Dictionary).duplicate(true))
		if not entries.is_empty() and not fallback_radius_scan:
			_sort_by_distance(entries)
			return entries.slice(0, mini(max_objects, entries.size()))

	var tree := get_tree()
	if tree == null:
		return entries
	for candidate in tree.get_nodes_in_group(world_object_group):
		var node := candidate as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var object_key := _node_key(node)
		if seen.has(object_key):
			continue
		if not _is_within_radius(observer, node):
			continue
		if not node.has_method("build_ai_object_summary"):
			continue
		var summary_value: Variant = node.call("build_ai_object_summary", observer)
		if summary_value is Dictionary:
			var summary := (summary_value as Dictionary).duplicate(true)
			seen[String(summary.get("id", object_key))] = true
			entries.append(summary)
	_sort_by_distance(entries)
	return entries.slice(0, mini(max_objects, entries.size()))

func _collect_nearby_areas(observer: Node3D) -> Array:
	var entries: Array = []
	var seen := {}
	if prefer_vision_area_overlap:
		for node in _collect_vision_overlap_nodes(perception_area_group):
			if node == null or not is_instance_valid(node):
				continue
			if not node.has_method("build_ai_area_summary"):
				continue
			var summary_value: Variant = node.call("build_ai_area_summary", observer)
			if summary_value is Dictionary:
				var id := String((summary_value as Dictionary).get("id", node.get_path())).strip_edges()
				seen[id] = true
				entries.append((summary_value as Dictionary).duplicate(true))
		if not entries.is_empty() and not fallback_radius_scan:
			_sort_by_distance(entries)
			return entries.slice(0, mini(max_areas, entries.size()))

	var tree := get_tree()
	if tree == null:
		return entries
	for candidate in tree.get_nodes_in_group(perception_area_group):
		var node := candidate as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var area_key := _node_key(node)
		if seen.has(area_key):
			continue
		if not _is_within_radius(observer, node):
			continue
		if not node.has_method("build_ai_area_summary"):
			continue
		var summary_value: Variant = node.call("build_ai_area_summary", observer)
		if summary_value is Dictionary:
			var summary := (summary_value as Dictionary).duplicate(true)
			seen[String(summary.get("id", area_key))] = true
			entries.append(summary)
	_sort_by_distance(entries)
	return entries.slice(0, mini(max_areas, entries.size()))

func _with_known_nav_points(vision_snapshot: Dictionary, observer: Node3D) -> Dictionary:
	var snapshot := vision_snapshot.duplicate(true)
	snapshot["semantic_model"] = "vision_snapshot"
	snapshot["vision_note"] = "This snapshot is what the AI can currently see or sense nearby through its Area3D/fallback radius."
	if not include_known_nav_points:
		return snapshot
	var known := _collect_known_nav_points(observer)
	if not known.is_empty():
		snapshot["known_nav_points"] = known
		snapshot["known_nav_points_note"] = "Known global navigation map. These points are remembered map/interest points, not necessarily currently visible."
	return snapshot

func _collect_known_nav_points(observer: Node3D) -> Array:
	var entries: Array = []
	var tree := get_tree()
	if tree == null:
		return entries
	for candidate in tree.get_nodes_in_group(nav_point_group):
		if entries.size() >= max_known_nav_points:
			break
		var node := candidate as Node
		if node == null or not is_instance_valid(node):
			continue
		if not node.has_method("build_ai_nav_point_summary"):
			continue
		var summary_value: Variant = node.call("build_ai_nav_point_summary", observer)
		if summary_value is not Dictionary:
			continue
		var summary := (summary_value as Dictionary).duplicate(true)
		if bool(summary.get("enabled", true)) == false:
			continue
		summary["knowledge_scope"] = String(summary.get("knowledge_scope", "global_map"))
		summary["map_role"] = String(summary.get("map_role", "known_nav_point"))
		entries.append(summary)
	_sort_by_distance(entries)
	return entries

func _collect_vision_overlap_nodes(required_group: StringName) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var area := _resolve_vision_area()
	if area == null:
		return result
	for body in area.get_overlapping_bodies():
		_append_group_owner(body as Node, required_group, result)
	for overlapped_area in area.get_overlapping_areas():
		_append_group_owner(overlapped_area as Node, required_group, result)
	return result

func _append_group_owner(from_node: Node, required_group: StringName, result: Array[Node3D]) -> void:
	var group_owner := _find_group_owner(from_node, required_group) as Node3D
	if group_owner == null:
		return
	for existing in result:
		if existing == group_owner:
			return
	result.append(group_owner)

func _find_group_owner(from_node: Node, required_group: StringName) -> Node:
	var current := from_node
	while current != null:
		if current.is_in_group(required_group):
			return current
		current = current.get_parent()
	return null

func _resolve_vision_area() -> Area3D:
	if vision_area_path != NodePath():
		var by_path := get_node_or_null(vision_area_path) as Area3D
		if by_path != null:
			return by_path
	var parent_node := get_parent()
	if parent_node != null:
		return parent_node.get_node_or_null("AIVisionProxy3D") as Area3D
	return null

func _is_within_radius(observer: Node3D, target: Node3D) -> bool:
	if observer == null or target == null:
		return true
	return observer.global_position.distance_to(target.global_position) <= scan_radius

func _sort_by_distance(entries: Array) -> void:
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("distance", 0.0)) < float(b.get("distance", 0.0))
	)

func _node_key(node: Node) -> String:
	if node == null:
		return ""
	if node.has_method("build_ai_object_summary"):
		var id_value: Variant = node.get("object_id")
		var id := String(id_value).strip_edges()
		if not id.is_empty():
			return id
	if node.has_method("build_ai_area_summary"):
		var id_value: Variant = node.get("area_id")
		var id := String(id_value).strip_edges()
		if not id.is_empty():
			return id
	return String(node.get_path())

