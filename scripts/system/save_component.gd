extends Node
class_name SaveComponent

@export var unique_id: String = ""

func _ready() -> void:
	var parent = get_parent()
	if unique_id.is_empty():
		# 采用绝对路径作为稳定ID，解决场景加载时的ID冲突问题
		var path = str(parent.get_path())
		if "@" in path: 
			# 如果是动态生成的节点（带有@），使用时间戳
			unique_id = "dynamic_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000)
		else:
			unique_id = path
			
	add_to_group("SavableComponent")

func _get_save_manager() -> Node:
	return get_node_or_null("/root/SaveManager")

# 手动标记该物体已被永久销毁（拾取、消耗等）
func mark_destroyed() -> void:
	var save_manager := _get_save_manager()
	if save_manager != null and save_manager.has_method("register_destroyed_object"):
		save_manager.call("register_destroyed_object", unique_id)

func _exit_tree() -> void:
	# 自动检测销毁：确保不是因为场景整体切换导致的误判
	if Engine.is_editor_hint():
		return
	var parent = get_parent()
	if parent == null or not parent.is_queued_for_deletion():
		return
	var tree := get_tree()
	if tree == null:
		return
	var current_scene: Node = tree.current_scene
	if current_scene == null or current_scene == parent or current_scene.is_queued_for_deletion():
		return
	mark_destroyed()

func get_save_data() -> Dictionary:
	var parent = get_parent()
	var data = {
		"unique_id": unique_id,
		"scene_path": parent.scene_file_path, 
		"transform": parent.global_transform if parent is Node3D else null
	}
	
	# 1. 读取父节点数据
	if parent.has_method("_get_custom_save_data"):
		data["custom"] = parent._get_custom_save_data()
		
	# 2. 自动寻找同级组件并保存（无需在父节点写代码即可自动保存 LootContainerComponent！）
	var sibling_data = {}
	var inventory_payloads = {}
	for child in parent.get_children():
		if child == self: continue
		if child.has_method("get_container_save_data"):
			sibling_data["loot"] = child.get_container_save_data()
		elif child.has_method("_get_custom_save_data"):
			sibling_data[child.name] = child._get_custom_save_data()
		if child.has_method("build_inventory_save_payload"):
			inventory_payloads[child.name] = child.build_inventory_save_payload()
			
	if not sibling_data.is_empty():
		data["siblings"] = sibling_data
	if not inventory_payloads.is_empty():
		data["inventory_payloads"] = inventory_payloads

	# 3. 递归记录子树组件（支持像 rack_001/rack_001_col 这样的深层容器）
	var component_states := {}
	var descendants: Array = parent.find_children("*", "", true, false)
	for node_raw in descendants:
		var node := node_raw as Node
		if node == null or node == self:
			continue
		var state := {}
		if node.has_method("get_container_save_data"):
			state["loot"] = node.get_container_save_data()
		if node.has_method("_get_custom_save_data"):
			state["custom"] = node._get_custom_save_data()
		if node.has_method("build_inventory_save_payload"):
			state["inventory_payload"] = node.build_inventory_save_payload()
		if state.is_empty():
			continue
		var rel_path: NodePath = parent.get_path_to(node)
		state["path"] = rel_path
		component_states[String(rel_path)] = state

	if not component_states.is_empty():
		data["component_states"] = component_states
		
	return data

func load_save_data(data: Dictionary) -> void:
	var parent = get_parent()
	
	if data.has("unique_id"):
		unique_id = data["unique_id"]
		
	if data.has("transform") and data["transform"] != null and parent is Node3D:
		parent.global_transform = data["transform"]
		
	# 1. 恢复父节点数据
	if data.has("custom") and parent.has_method("_load_custom_save_data"):
		parent._load_custom_save_data(data["custom"])
		
	# 2. 自动恢复同级组件数据（直接恢复 LootContainerComponent 的箱子物品）
	if data.has("siblings"):
		var sibling_data = data["siblings"]
		for child in parent.get_children():
			if child == self: continue
			if child.has_method("load_container_save_data") and sibling_data.has("loot"):
				child.load_container_save_data(sibling_data["loot"])
			elif child.has_method("_load_custom_save_data") and sibling_data.has(child.name):
				child._load_custom_save_data(sibling_data[child.name])

	if data.has("inventory_payloads"):
		var payloads: Dictionary = data["inventory_payloads"]
		for child in parent.get_children():
			if child == self:
				continue
			if not child.has_method("apply_inventory_save_payload"):
				continue
			if payloads.has(child.name):
				child.apply_inventory_save_payload(payloads[child.name])

	# 3. 恢复递归组件状态（优先深层路径，兼容储物柜）
	if data.has("component_states"):
		var component_states: Dictionary = data["component_states"]
		for key in component_states.keys():
			var state: Dictionary = component_states.get(key, {}) as Dictionary
			if state.is_empty():
				continue
			var path_str: String = String(state.get("path", key))
			var target := parent.get_node_or_null(NodePath(path_str))
			if target == null:
				continue
			if state.has("loot") and target.has_method("load_container_save_data"):
				target.load_container_save_data(state["loot"])
			if state.has("custom") and target.has_method("_load_custom_save_data"):
				target._load_custom_save_data(state["custom"])
			if state.has("inventory_payload") and target.has_method("apply_inventory_save_payload"):
				target.apply_inventory_save_payload(state["inventory_payload"])
