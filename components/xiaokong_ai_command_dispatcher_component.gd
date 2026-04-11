extends Node
class_name XiaokongAICommandDispatcherComponent

@export var router_path: NodePath
@export var xiaokong_root_path: NodePath
@export var xiaokong_group_name: StringName = &"Xiaokong"

func dispatch_ai_payload(payload: Dictionary) -> Dictionary:
	var safe_payload: Dictionary = payload.duplicate(true)
	var result := {
		"ok": false,
		"error": "",
		"summary": {},
	}

	var router: Node = _resolve_router()
	if router == null:
		result["error"] = "router_not_found"
		return result

	if not router.has_method("apply_ai_response"):
		result["error"] = "router_missing_apply_ai_response"
		return result

	var summary_variant: Variant = router.call("apply_ai_response", safe_payload)
	if summary_variant is Dictionary:
		result["summary"] = (summary_variant as Dictionary).duplicate(true)

	result["ok"] = true
	return result

func _resolve_router() -> Node:
	if router_path != NodePath():
		var by_path: Node = get_node_or_null(router_path)
		if by_path != null and by_path.has_method("apply_ai_response"):
			return by_path

	if xiaokong_root_path != NodePath():
		var by_root_path: Node = get_node_or_null(xiaokong_root_path)
		var by_root_router: Node = _find_router_from_node(by_root_path)
		if by_root_router != null:
			return by_root_router

	var tree: SceneTree = get_tree()
	if tree == null:
		return null

	for entry in tree.get_nodes_in_group(xiaokong_group_name):
		var candidate: Node = entry as Node
		if candidate == null:
			continue
		var router: Node = _find_router_from_node(candidate)
		if router != null:
			return router

	return null

func _find_router_from_node(root_node: Node) -> Node:
	if root_node == null:
		return null

	if root_node.has_method("apply_ai_response"):
		return root_node

	var by_components: Node = root_node.get_node_or_null("Components/AIActionRouterComponent")
	if by_components != null and by_components.has_method("apply_ai_response"):
		return by_components

	var by_flat_name: Node = root_node.get_node_or_null("AIActionRouterComponent")
	if by_flat_name != null and by_flat_name.has_method("apply_ai_response"):
		return by_flat_name

	return _find_router_recursive(root_node)

func _find_router_recursive(root_node: Node) -> Node:
	if root_node == null:
		return null

	for child in root_node.get_children():
		var child_node: Node = child as Node
		if child_node == null:
			continue
		if child_node.has_method("apply_ai_response"):
			return child_node
		var nested: Node = _find_router_recursive(child_node)
		if nested != null:
			return nested
	return null
