extends Node

const SAVE_DIR = "user://saves/"

# 运行时记录当前场景中被销毁的物体 ID
var session_destroyed_objects: Array[String] = []

func _ready() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_absolute(SAVE_DIR)
		
	# 游戏启动时不再自动执行读取
	# 取而代之的是，你可以在主菜单点击“继续游戏”或者需要时手动调用 auto_load_game()

# ==========================================
# 外部调用的自动加载接口
# ==========================================
func auto_load_game(slot_name: String = "manual_save") -> void:
	if has_save(slot_name):
		print("[SaveManager] 外部请求：检测到存档，准备加载...")
		
		# 立刻呼出遮罩，防止看到原本场景的闪烁
		var transition_ui = get_node_or_null("/root/TransitionUI")
		if transition_ui:
			transition_ui.start_transition("DATA_RESTORATION // IN_PROGRESS", false)
			
		# 等待遮罩完全盖住屏幕（例如 0.1 秒或者一两帧），然后再进行实质性的加载
		await get_tree().create_timer(0.1).timeout
		load_game(slot_name)
	else:
		print("[SaveManager] 外部请求：未检测到存档，作为新游戏开始。")

func has_save(slot_name: String = "manual_save") -> bool:
	return FileAccess.file_exists(SAVE_DIR + slot_name + ".tres")

# 提供给 SaveComponent 调用的接口
func register_destroyed_object(id: String):
	if not session_destroyed_objects.has(id):
		session_destroyed_objects.append(id)

func save_game(slot_name: String = "manual_save") -> void:
	var save_game = SaveGame.new()
	save_game.last_saved_time = Time.get_datetime_string_from_system()
	save_game.current_level_path = get_tree().current_scene.scene_file_path
	save_game.destroyed_objects = session_destroyed_objects.duplicate()
	
	var components = get_tree().get_nodes_in_group("SavableComponent")
	for comp in components:
		if comp is SaveComponent:
			var data = comp.get_save_data()
			if comp.get_parent().is_in_group("Player"):
				save_game.player_data = data
			else:
				save_game.world_objects_data.append(data)
	
	var file_path = SAVE_DIR + slot_name + ".tres"
	var result = ResourceSaver.save(save_game, file_path)
	if result == OK:
		print("Game saved to: ", file_path)
	else:
		push_error("Failed to save game: " + str(result))

func load_game(slot_name: String = "manual_save") -> void:
	var transition_ui = get_node_or_null("/root/TransitionUI")
	if transition_ui:
		transition_ui.start_transition("DATA_RESTORATION // IN_PROGRESS", false)
	
	var start_time = Time.get_ticks_msec()
	
	var file_path = SAVE_DIR + slot_name + ".tres"
	if not FileAccess.file_exists(file_path): 
		if transition_ui: transition_ui.stop_transition()
		return
	
	var save_game = ResourceLoader.load(file_path) as SaveGame
	if not save_game: 
		if transition_ui: transition_ui.stop_transition()
		return
		
	# 1. 恢复运行时的销毁记录
	session_destroyed_objects = save_game.destroyed_objects.duplicate()
		
	# 2. 场景切换逻辑（更加安全）
	if get_tree().current_scene.scene_file_path != save_game.current_level_path:
		get_tree().change_scene_to_file(save_game.current_level_path)
		# 等待场景切换完成 (通常需要两帧确保子节点_ready完毕)
		await get_tree().process_frame
		await get_tree().process_frame
	
	var components = get_tree().get_nodes_in_group("SavableComponent")
	var comp_dict = {}
	
	# 3. 处理当前场景原有的加载，拦截已销毁的物体
	for comp in components:
		# 如果这个物体在存档里记录为“已销毁”，我们必须立刻把它从场景中删除！
		if session_destroyed_objects.has(comp.unique_id):
			comp.get_parent().queue_free()
			continue # 跳过加载它的数据
			
		comp_dict[comp.unique_id] = comp
	
	# 4. 优先加载玩家
	for comp in components:
		if is_instance_valid(comp) and comp.get_parent().is_in_group("Player"):
			comp.load_save_data(save_game.player_data)
			if transition_ui: transition_ui.update_progress(50)
			break
	
	# 5. 加载其他世界物体，并动态生成“掉落的物品”
	var current_scene = get_tree().current_scene
	for data in save_game.world_objects_data:
		var id = data.get("unique_id", "")
		
		# 情景 A: 场景中本来就有这个物体，直接更新数据
		if comp_dict.has(id) and is_instance_valid(comp_dict[id]):
			comp_dict[id].load_save_data(data)
			
		# 情景 B: 场景中没有这个物体，检查它是否是动态创建的（例如玩家丢弃的物品）
		else:
			var scene_path = data.get("scene_path", "")
			if scene_path != "" and ResourceLoader.exists(scene_path):
				var packed_scene = load(scene_path) as PackedScene
				if packed_scene:
					var new_obj = packed_scene.instantiate()
					current_scene.add_child(new_obj)
					
					# 寻找新生成的物体中的 SaveComponent
					var new_comp = new_obj.get_node_or_null("SaveComponent")
					if not new_comp:
						for child in new_obj.get_children():
							if child is SaveComponent:
								new_comp = child
								break
					
					# 恢复它的数据（包括它里面的内容）
					if new_comp:
						new_comp.unique_id = id
						new_comp.load_save_data(data)
	
	# 6. 确保过渡界面至少显示一段时间
	var elapsed = (Time.get_ticks_msec() - start_time) / 1000.0
	var min_wait = 0.8
	if elapsed < min_wait:
		await get_tree().create_timer(min_wait - elapsed).timeout
	
	if transition_ui:
		transition_ui.update_progress(100)
		transition_ui.stop_transition()
		
	print("Game loaded successfully.")
