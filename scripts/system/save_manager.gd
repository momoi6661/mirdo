extends Node

const SAVE_DIR := "user://saves/"
const DEFAULT_SLOT := "manual_save"
const SAVE_EXTENSION := ".tres"
const MIN_LOAD_TRANSITION_TIME := 0.35
const TRANSITION_MESSAGE := "DATA_RESTORATION // IN_PROGRESS"

signal save_started(slot_name: String)
signal save_finished(slot_name: String, success: bool, file_path: String)
signal load_started(slot_name: String)
signal load_finished(slot_name: String, success: bool)
signal load_failed(slot_name: String, reason: String)

var session_destroyed_objects: Array[String] = []
var is_saving: bool = false
var is_loading: bool = false
var last_error: String = ""


func _ready() -> void:
	_ensure_save_dir()


func auto_load_game(slot_name: String = DEFAULT_SLOT) -> bool:
	if not has_save(slot_name):
		print("[SaveManager] 未检测到存档，作为新游戏开始: ", slot_name)
		return false
	print("[SaveManager] 检测到存档，准备加载: ", slot_name)
	var loaded: bool = await load_game(slot_name)
	return loaded


func has_save(slot_name: String = DEFAULT_SLOT) -> bool:
	return FileAccess.file_exists(get_save_path(slot_name))


func get_save_path(slot_name: String = DEFAULT_SLOT) -> String:
	var safe_slot := _sanitize_slot_name(slot_name)
	return SAVE_DIR + safe_slot + SAVE_EXTENSION


func register_destroyed_object(id: String) -> void:
	var safe_id := id.strip_edges()
	if safe_id.is_empty():
		return
	if not session_destroyed_objects.has(safe_id):
		session_destroyed_objects.append(safe_id)


func unregister_destroyed_object(id: String) -> void:
	session_destroyed_objects.erase(id)


func clear_session_destroyed_objects() -> void:
	session_destroyed_objects.clear()


func save_game(slot_name: String = DEFAULT_SLOT) -> bool:
	if is_saving:
		last_error = "保存正在进行中"
		return false
	_ensure_save_dir()
	is_saving = true
	last_error = ""
	save_started.emit(slot_name)

	var save_game := _build_save_game(slot_name)
	var file_path := get_save_path(slot_name)
	var result := ResourceSaver.save(save_game, file_path)
	var success := result == OK
	if success:
		print("[SaveManager] Game saved: ", file_path)
	else:
		last_error = "ResourceSaver.save failed: %d" % result
		push_error("[SaveManager] 保存失败 %s: %s" % [file_path, last_error])

	is_saving = false
	save_finished.emit(slot_name, success, file_path)
	return success


func load_game(slot_name: String = DEFAULT_SLOT) -> bool:
	if is_loading:
		last_error = "读取正在进行中"
		return false
	var file_path := get_save_path(slot_name)
	if not FileAccess.file_exists(file_path):
		last_error = "存档不存在: " + file_path
		load_failed.emit(slot_name, last_error)
		return false

	is_loading = true
	last_error = ""
	load_started.emit(slot_name)
	get_tree().paused = false

	var transition_ui := _ensure_transition_ui()
	var start_time := Time.get_ticks_msec()
	_begin_transition(transition_ui)

	var save_game := _load_save_resource(file_path)
	if save_game == null:
		await _finish_load_transition(transition_ui, start_time)
		is_loading = false
		last_error = "存档资源无法读取或类型不正确: " + file_path
		load_failed.emit(slot_name, last_error)
		load_finished.emit(slot_name, false)
		return false

	save_game.normalize()
	session_destroyed_objects = _string_array_from(save_game.destroyed_objects)
	_apply_global_payload(save_game.global_data)

	var scene_loaded := await _change_to_saved_scene(save_game.current_level_path)
	if not scene_loaded:
		await _finish_load_transition(transition_ui, start_time)
		is_loading = false
		load_failed.emit(slot_name, last_error)
		load_finished.emit(slot_name, false)
		return false

	await _wait_scene_ready()
	_restore_scene_state(save_game)
	await _wait_scene_ready()
	await _finish_load_transition(transition_ui, start_time)

	is_loading = false
	load_finished.emit(slot_name, true)
	print("[SaveManager] Game loaded: ", file_path)
	return true


func delete_save(slot_name: String = DEFAULT_SLOT) -> bool:
	var file_path := get_save_path(slot_name)
	if not FileAccess.file_exists(file_path):
		return true
	var result := DirAccess.remove_absolute(file_path)
	if result != OK:
		last_error = "删除存档失败: %d" % result
		return false
	return true


func _build_save_game(slot_name: String) -> SaveGame:
	var save_game := SaveGame.new()
	save_game.schema_version = SaveGame.CURRENT_SCHEMA_VERSION
	save_game.slot_name = _sanitize_slot_name(slot_name)
	save_game.last_saved_time = Time.get_datetime_string_from_system()
	save_game.current_level_path = _get_current_scene_path()
	save_game.destroyed_objects = session_destroyed_objects.duplicate()
	save_game.global_data = _collect_global_payload()
	save_game.metadata = {
		"unix_time": Time.get_unix_time_from_system(),
		"scene_name": save_game.current_level_path.get_file().get_basename(),
		"savable_count": 0,
	}

	var world_data: Array[Dictionary] = []
	var components := _get_save_components()
	save_game.metadata["savable_count"] = components.size()
	for comp in components:
		if comp == null or not is_instance_valid(comp):
			continue
		var data: Dictionary = comp.get_save_data()
		if data.is_empty():
			continue
		var parent := comp.get_parent()
		if parent != null and parent.is_in_group("Player"):
			save_game.player_data = data
		else:
			world_data.append(data)
	save_game.world_objects_data = world_data
	save_game.normalize()
	return save_game


func _load_save_resource(file_path: String) -> SaveGame:
	var resource := ResourceLoader.load(file_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	return resource as SaveGame


func _change_to_saved_scene(scene_path: String) -> bool:
	var target_scene := scene_path.strip_edges()
	if target_scene.is_empty():
		return true
	if not ResourceLoader.exists(target_scene):
		last_error = "存档场景不存在: " + target_scene
		push_error("[SaveManager] " + last_error)
		return false
	var tree := get_tree()
	if tree == null:
		last_error = "SceneTree 不可用"
		return false
	var current_scene := tree.current_scene
	var current_path := ""
	if current_scene != null:
		current_path = current_scene.scene_file_path.strip_edges()
	if current_path == target_scene:
		return true
	var result := tree.change_scene_to_file(target_scene)
	if result != OK:
		last_error = "切换存档场景失败: %s (%d)" % [target_scene, result]
		push_error("[SaveManager] " + last_error)
		return false
	await _wait_scene_ready()
	return true


func _restore_scene_state(save_game: SaveGame) -> void:
	var components := _get_save_components()
	var comp_dict: Dictionary = {}
	for comp in components:
		if comp == null or not is_instance_valid(comp):
			continue
		var unique_id := String(comp.unique_id)
		if session_destroyed_objects.has(unique_id):
			var parent := comp.get_parent()
			if parent != null and parent != get_tree().current_scene:
				parent.queue_free()
			continue
		comp_dict[unique_id] = comp

	if not save_game.player_data.is_empty():
		var player_id := String(save_game.player_data.get("unique_id", ""))
		if comp_dict.has(player_id) and is_instance_valid(comp_dict[player_id]):
			comp_dict[player_id].load_save_data(save_game.player_data)
		else:
			_restore_first_player_component(save_game.player_data)

	var current_scene := get_tree().current_scene
	if current_scene == null:
		return
	for data_raw in save_game.world_objects_data:
		var data := data_raw as Dictionary
		if data.is_empty():
			continue
		var id := String(data.get("unique_id", ""))
		if id.is_empty() or session_destroyed_objects.has(id):
			continue
		if comp_dict.has(id) and is_instance_valid(comp_dict[id]):
			comp_dict[id].load_save_data(data)
		else:
			_restore_dynamic_object(current_scene, id, data)


func _restore_first_player_component(player_data: Dictionary) -> void:
	for comp in _get_save_components():
		if comp == null or not is_instance_valid(comp):
			continue
		var parent := comp.get_parent()
		if parent != null and parent.is_in_group("Player"):
			comp.load_save_data(player_data)
			return


func _restore_dynamic_object(current_scene: Node, id: String, data: Dictionary) -> void:
	var scene_path := String(data.get("scene_path", "")).strip_edges()
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return
	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		return
	var new_obj := packed_scene.instantiate()
	current_scene.add_child(new_obj)
	var new_comp := _find_save_component(new_obj)
	if new_comp == null:
		return
	new_comp.unique_id = id
	new_comp.load_save_data(data)


func _find_save_component(root_node: Node) -> SaveComponent:
	if root_node == null:
		return null
	if root_node is SaveComponent:
		return root_node as SaveComponent
	var direct := root_node.get_node_or_null("SaveComponent")
	if direct is SaveComponent:
		return direct as SaveComponent
	for child in root_node.find_children("*", "SaveComponent", true, false):
		if child is SaveComponent:
			return child as SaveComponent
	return null


func _get_save_components() -> Array[SaveComponent]:
	var result: Array[SaveComponent] = []
	for node in get_tree().get_nodes_in_group("SavableComponent"):
		if node is SaveComponent:
			result.append(node as SaveComponent)
	return result


func _get_current_scene_path() -> String:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return ""
	return tree.current_scene.scene_file_path.strip_edges()


func _collect_global_payload() -> Dictionary:
	var payload: Dictionary = {}
	var global_node := get_node_or_null("/root/Global")
	if global_node != null and global_node.has_method("build_global_save_payload"):
		var data = global_node.call("build_global_save_payload")
		if data is Dictionary:
			payload["Global"] = data
	return payload


func _apply_global_payload(payload: Dictionary) -> void:
	if payload.is_empty():
		return
	var global_node := get_node_or_null("/root/Global")
	if global_node == null or not global_node.has_method("apply_global_save_payload"):
		return
	var global_payload = payload.get("Global", {})
	if global_payload is Dictionary:
		global_node.call("apply_global_save_payload", global_payload)


func _ensure_save_dir() -> void:
	if DirAccess.dir_exists_absolute(SAVE_DIR):
		return
	var result := DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if result != OK:
		push_error("[SaveManager] 无法创建存档目录 %s: %d" % [SAVE_DIR, result])


func _sanitize_slot_name(slot_name: String) -> String:
	var safe := slot_name.strip_edges()
	if safe.is_empty():
		safe = DEFAULT_SLOT
	var invalid_chars := ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", " "]
	for invalid in invalid_chars:
		safe = safe.replace(invalid, "_")
	return safe


func _string_array_from(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		var text := String(value).strip_edges()
		if not text.is_empty() and not result.has(text):
			result.append(text)
	return result


func _ensure_transition_ui() -> Node:
	var existing := get_node_or_null("/root/TransitionUI")
	if existing != null:
		return existing
	var transition_scene := load("res://controllers/ui/transition_screen.tscn") as PackedScene
	if transition_scene == null:
		return null
	var instance := transition_scene.instantiate()
	instance.name = "TransitionUI"
	get_tree().root.add_child(instance)
	return instance


func _begin_transition(transition_ui: Node) -> void:
	if transition_ui == null:
		return
	if transition_ui.has_method("start_transition"):
		transition_ui.call("start_transition", TRANSITION_MESSAGE, false)


func _finish_load_transition(transition_ui: Node, start_time_msec: int) -> void:
	var elapsed := float(Time.get_ticks_msec() - start_time_msec) / 1000.0
	if elapsed < MIN_LOAD_TRANSITION_TIME:
		await get_tree().create_timer(MIN_LOAD_TRANSITION_TIME - elapsed).timeout
	if transition_ui != null and transition_ui.has_method("stop_transition"):
		await transition_ui.call("stop_transition")


func _wait_scene_ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
