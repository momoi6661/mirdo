extends Node
class_name CharacterAIActionExecutorComponent

@export var perception_component_path: NodePath
@export var world_object_group: StringName = &"ai_world_object"

func execute_intent(intent: Dictionary) -> Dictionary:
	var intent_name := String(intent.get("intent", "")).strip_edges()
	var report := {
		"ok": false,
		"intent": intent_name,
		"target_object_id": "",
		"target_marker_path": "",
		"errors": [],
	}
	if intent_name.is_empty():
		report["errors"].append("intent_empty")
		return report
	match intent_name:
		"go_to_object", "sit_down":
			_resolve_object_marker(intent, report)
		_:
			report["ok"] = true
	return report

func _resolve_object_marker(intent: Dictionary, report: Dictionary) -> void:
	var target_ref := String(intent.get("target_ref", intent.get("target_object_id", ""))).strip_edges()
	if target_ref.is_empty():
		report["errors"].append("target_ref_empty")
		return
	var target := _find_world_object(target_ref)
	if target == null:
		report["errors"].append("target_object_not_found")
		return
	var role := String(intent.get("marker_role", "approach")).strip_edges()
	if role.is_empty():
		role = "approach"
	var marker: Marker3D = null
	if target.has_method("get_marker_for_role"):
		marker = target.call("get_marker_for_role", role) as Marker3D
	if marker == null and target.has_method("get_nav_marker"):
		marker = target.call("get_nav_marker") as Marker3D
	if marker == null:
		report["errors"].append("target_marker_not_found")
		return
	report["ok"] = true
	report["target_object_id"] = _get_world_object_id(target)
	report["target_marker_path"] = String(marker.get_path())

func _find_world_object(target_ref: String) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for candidate in tree.get_nodes_in_group(world_object_group):
		var node := candidate as Node
		if node == null or not is_instance_valid(node):
			continue
		if _get_world_object_id(node) == target_ref:
			return node
		if String(node.name) == target_ref:
			return node
	return null

func _get_world_object_id(node: Node) -> String:
	if node == null:
		return ""
	var value: Variant = node.get("object_id")
	var clean := String(value).strip_edges()
	if not clean.is_empty():
		return clean
	return String(node.name)
