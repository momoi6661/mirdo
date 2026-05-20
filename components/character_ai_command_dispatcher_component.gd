extends Node
class_name CharacterAICommandDispatcherComponent

@export var executor_path: NodePath
@export var character_root_path: NodePath
@export var character_group_name: StringName = &"AICharacter"
@export var fallback_group_names: PackedStringArray = PackedStringArray(["Mirdo"])

func dispatch_ai_payload(payload: Dictionary) -> Dictionary:
	var result := {"ok": false, "error": "", "summary": {}}
	var executor := _resolve_executor()
	if executor == null:
		result["error"] = "executor_not_found"
		return result
	if not executor.has_method("apply_ai_response"):
		result["error"] = "executor_missing_apply_ai_response"
		return result
	var summary: Variant = executor.call("apply_ai_response", payload.duplicate(true))
	if summary is Dictionary:
		result["summary"] = (summary as Dictionary).duplicate(true)
	result["ok"] = true
	return result

func _resolve_executor() -> Node:
	if executor_path != NodePath():
		var by_path := get_node_or_null(executor_path)
		if by_path != null and by_path.has_method("apply_ai_response"):
			return by_path
	if character_root_path != NodePath():
		var root := get_node_or_null(character_root_path)
		var by_root := _find_executor_from_node(root)
		if by_root != null:
			return by_root
	var tree := get_tree()
	if tree == null:
		return null
	var groups: Array[StringName] = [character_group_name]
	for name in fallback_group_names:
		groups.append(StringName(name))
	for group_name in groups:
		for entry in tree.get_nodes_in_group(group_name):
			var executor := _find_executor_from_node(entry as Node)
			if executor != null:
				return executor
	return null

func _find_executor_from_node(root: Node) -> Node:
	if root == null:
		return null
	if root.has_method("apply_ai_response"):
		return root
	for path in ["Components/CharacterAIActionExecutor", "CharacterAIActionExecutor", "Components/AIActionExecutor"]:
		var by_path := root.get_node_or_null(path)
		if by_path != null and by_path.has_method("apply_ai_response"):
			return by_path
	return _find_executor_recursive(root)

func _find_executor_recursive(root: Node) -> Node:
	for child in root.get_children():
		var node := child as Node
		if node == null:
			continue
		if node.has_method("apply_ai_response"):
			return node
		var nested := _find_executor_recursive(node)
		if nested != null:
			return nested
	return null
