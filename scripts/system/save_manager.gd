extends Node

const SAVE_DIR = "user://saves/"

func _ready() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_absolute(SAVE_DIR)
	
	if has_save("manual_save"):
		load_game.call_deferred("manual_save")

func has_save(slot_name: String = "manual_save") -> bool:
	return FileAccess.file_exists(SAVE_DIR + slot_name + ".tres")

func save_game(slot_name: String = "manual_save") -> void:
	var save_game = SaveGame.new()
	save_game.last_saved_time = Time.get_datetime_string_from_system()
	save_game.current_level_path = get_tree().current_scene.scene_file_path
	
	# 查找所有的存档组件
	var components = get_tree().get_nodes_in_group("SavableComponent")
	for comp in components:
		if comp is SaveComponent:
			var data = comp.get_save_data()
			# 如果父节点是玩家
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
		# 读档进入游戏通常是从菜单开始，所以 fade_in 设为 false，直接遮盖
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
		
	if get_tree().current_scene.scene_file_path != save_game.current_level_path:
		get_tree().change_scene_to_file(save_game.current_level_path)
		await get_tree().process_frame
	
	# 等待一帧确保场景节点 ready
	await get_tree().process_frame
	
	var components = get_tree().get_nodes_in_group("SavableComponent")
	var comp_dict = {}
	for comp in components:
		comp_dict[comp.unique_id] = comp
	
	# 优先加载玩家
	for comp in components:
		if comp.get_parent().is_in_group("Player"):
			comp.load_save_data(save_game.player_data)
			if transition_ui: transition_ui.update_progress(50)
			break
	
	# 加载其他物体
	for data in save_game.world_objects_data:
		var id = data.get("unique_id", "")
		if comp_dict.has(id):
			comp_dict[id].load_save_data(data)
	
	# 确保过渡界面至少显示一段时间（例如 0.8 秒），防止画面闪烁
	var elapsed = (Time.get_ticks_msec() - start_time) / 1000.0
	var min_wait = 0.8
	if elapsed < min_wait:
		await get_tree().create_timer(min_wait - elapsed).timeout
	
	if transition_ui:
		transition_ui.update_progress(100)
		transition_ui.stop_transition()
		
	print("Game loaded.")
