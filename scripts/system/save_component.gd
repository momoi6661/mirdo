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

# 手动标记该物体已被永久销毁（拾取、消耗等）
func mark_destroyed() -> void:
	if SaveManager.has_method("register_destroyed_object"):
		SaveManager.register_destroyed_object(unique_id)

func _exit_tree():
	# 自动检测销毁：确保不是因为场景整体切换导致的误判
	if not Engine.is_editor_hint() and get_parent().is_queued_for_deletion():
		if get_tree().current_scene != get_parent() and not get_tree().current_scene.is_queued_for_deletion():
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
	for child in parent.get_children():
		if child == self: continue
		if child.has_method("get_container_save_data"):
			sibling_data["loot"] = child.get_container_save_data()
		elif child.has_method("_get_custom_save_data"):
			sibling_data[child.name] = child._get_custom_save_data()
			
	if not sibling_data.is_empty():
		data["siblings"] = sibling_data
		
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
