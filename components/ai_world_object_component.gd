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

## 语义能力的额外描述，不暴露给后端的 NodePath。
## 例如：{"take_item": {"requires": ["open"], "result": "item_in_hand"}}。
@export var affordance_metadata: Dictionary = {}

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
		"affordances": get_ai_affordances(),
		"priority": priority,
		"path": String(get_path()) if is_inside_tree() else "",
		"marker_roles": _build_marker_role_paths(),
	}
	if observer != null and observer is Node3D and observer.is_inside_tree() and is_inside_tree():
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

## 构造给 Agent 的实体摘要。
##
## 导航点是 Godot 的实现细节；Agent 只需要知道“这个实体能做什么”。
## 具体的 approach/sit/stand Marker 仍由 get_marker_for_role() 在本地解析。
func build_ai_entity_summary(observer: Node3D = null) -> Dictionary:
	var summary := {
		"id": _resolve_object_id(),
		"name": _resolve_display_name(),
		"kind": object_type,
		"description": ai_description.strip_edges(),
		"tags": _packed_to_array(tags),
		"affordances": get_ai_affordances(),
		"availability": _build_availability_snapshot(),
		"priority": priority,
		"relation": "known",
	}
	if observer != null and observer is Node3D and observer.is_inside_tree() and is_inside_tree():
		summary["distance"] = observer.global_position.distance_to(global_position)
	else:
		summary["distance"] = 0.0
	return summary

## 返回稳定的语义能力名称，并把坐下/打开等角色映射转换为能力。
func get_ai_affordances() -> Array[String]:
	var result: Array[String] = []
	for raw_action in supported_actions:
		var action := String(raw_action).strip_edges()
		if not action.is_empty() and not result.has(action):
			result.append(action)
	for raw_role in marker_roles.keys():
		var role := String(raw_role).strip_edges().to_lower()
		if role in ["approach", "look"] or role.is_empty():
			continue
		if not result.has(role):
			result.append(role)
	return result

## 查询一个能力的执行契约；返回的是语义信息，不包含场景路径。
func resolve_ai_affordance(affordance: String) -> Dictionary:
	var affordance_name := affordance.strip_edges().to_lower()
	if affordance_name.is_empty() or not get_ai_affordances().has(affordance_name):
		return {}
	var metadata: Dictionary = {}
	var raw_metadata: Variant = affordance_metadata.get(affordance_name, {})
	if raw_metadata is Dictionary:
		metadata = (raw_metadata as Dictionary).duplicate(true)
	var result := {
		"name": affordance_name,
		"requires_navigation": affordance_name not in ["look_at_player", "listen"],
		"marker_role": _preferred_marker_role_for_affordance(affordance_name),
		"metadata": metadata,
	}
	for key in ["requires", "result", "post_action", "preconditions"]:
		if metadata.has(key):
			result[key] = metadata[key]
	return result

func _preferred_marker_role_for_affordance(affordance: String) -> String:
	if affordance in ["sit", "sit_down", "seated_idle"] and marker_roles.has("sit"):
		return "sit"
	if marker_roles.has(affordance):
		return affordance
	if affordance in ["open", "inspect", "take_item", "take_from_container"] and marker_roles.has("approach"):
		return "approach"
	return "approach" if marker_roles.has("approach") else ""

func _build_availability_snapshot() -> Dictionary:
	# 容器/物品组件可以通过方法提供动态库存；没有库存接口时保持空对象。
	for method_name in [&"build_ai_inventory_snapshot", &"get_ai_inventory_snapshot", &"get_inventory_snapshot"]:
		if has_method(method_name):
			var value: Variant = call(method_name)
			if value is Dictionary:
				return (value as Dictionary).duplicate(true)
	var child_snapshot := _find_child_inventory_snapshot(self)
	if not child_snapshot.is_empty():
		return child_snapshot
	return {}

func _find_child_inventory_snapshot(root: Node) -> Dictionary:
	if root == null:
		return {}
	for child in root.get_children():
		var node := child as Node
		if node == null:
			continue
		for method_name in [&"build_ai_inventory_snapshot", &"get_ai_inventory_snapshot", &"get_inventory_snapshot"]:
			if not node.has_method(method_name):
				continue
			var value: Variant = node.call(method_name)
			if value is Dictionary:
				return (value as Dictionary).duplicate(true)
		var nested := _find_child_inventory_snapshot(node)
		if not nested.is_empty():
			return nested
	return {}

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
		return _find_matching_ai_nav_point(clean_role)
	var raw_value: Variant = marker_roles.get(clean_role)
	var path := NodePath(String(raw_value))
	if raw_value is NodePath:
		path = raw_value
	if path == NodePath():
		return _find_matching_ai_nav_point(clean_role)
	var marker := get_node_or_null(path) as Marker3D
	if marker != null:
		return marker
	return _find_matching_ai_nav_point(clean_role)

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

func _find_matching_ai_nav_point(role: String = "approach") -> Marker3D:
	if not is_inside_tree():
		return null
	var id := _resolve_object_id()
	if id.is_empty():
		return null
	var role_key := role.strip_edges().to_lower()
	var best: Marker3D = null
	var best_distance := INF
	for entry in get_tree().get_nodes_in_group(&"ai_nav_point"):
		var marker := entry as Marker3D
		if marker == null or not is_instance_valid(marker):
			continue
		if String(marker.get("target_object_id")).strip_edges() != id:
			continue
		var marker_role := _nav_point_marker_role(marker)
		if not role_key.is_empty() and marker_role != role_key:
			if role_key == "approach" and marker_role.is_empty():
				pass
			else:
				continue
		if role_key == "sit" and marker_role != "sit":
			continue
		var distance := global_position.distance_squared_to(marker.global_position)
		if distance < best_distance:
			best_distance = distance
			best = marker
	return best

func _nav_point_marker_role(marker: Marker3D) -> String:
	if marker == null:
		return ""
	if "marker_role" in marker:
		return String(marker.get("marker_role")).strip_edges().to_lower()
	if marker.has_meta("marker_role"):
		return String(marker.get_meta("marker_role")).strip_edges().to_lower()
	return ""

func _nav_point_has_tag(marker: Marker3D, tag: String) -> bool:
	var values: Variant = marker.get("tags")
	if values is PackedStringArray:
		for item in values:
			if String(item).strip_edges().to_lower() == tag:
				return true
	elif values is Array:
		for item in values:
			if String(item).strip_edges().to_lower() == tag:
				return true
	return false
