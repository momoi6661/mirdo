extends Node

const SAFE_RESOURCE_LOADER := preload("res://addons/safe_resource_loader/safe_resource_loader.gd")
const SAVE_PROFILE_SCRIPT := preload("res://scripts/system/save_profile.gd")
const SAVE_DIR := "user://saves/"
const DEFAULT_SLOT := "slot_01"
const SAVE_EXTENSION := ".tres"
const PROFILE_PATH := "user://save_profile.tres"
const MAIN_MENU_SCENE_PATH := "res://levels/menu/MainMenu.tscn"
const MIN_LOAD_TRANSITION_TIME := 0.35
const TRANSITION_MESSAGE := "DATA_RESTORATION // IN_PROGRESS"
const AUTOSAVE_INTERVAL_SEC := 60.0
const EXTERNAL_LOAD_COVER_META := "external_load_cover_active"

signal save_started(slot_name: String)
signal save_finished(slot_name: String, success: bool, file_path: String)
signal load_started(slot_name: String)
signal load_finished(slot_name: String, success: bool)
signal load_failed(slot_name: String, reason: String)

var session_destroyed_objects: Array[String] = []
var is_saving: bool = false
var is_loading: bool = false
var last_error: String = ""
var current_slot_name: String = DEFAULT_SLOT
var last_loaded_slot_name: String = ""
var autosave_enabled: bool = true

var _autosave_timer: Timer


func _ready() -> void:
	_ensure_save_dir()
	_load_profile()
	_setup_autosave_timer()
	call_deferred("_try_boot_auto_load_from_non_menu_scene")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		auto_save_current_game()


func auto_load_game(slot_name: String = "") -> bool:
	var resolved_slot := _resolve_load_slot_name(slot_name)
	if not has_save(resolved_slot):
		print("[SaveManager] 未检测到存档，作为新游戏开始: ", resolved_slot)
		return false
	print("[SaveManager] 检测到存档，准备加载: ", resolved_slot)
	var loaded: bool = await load_game(resolved_slot)
	return loaded


func has_save(slot_name: String = "") -> bool:
	return FileAccess.file_exists(get_save_path(_resolve_load_slot_name(slot_name)))


func get_save_path(slot_name: String = "") -> String:
	var safe_slot := _resolve_slot_name(slot_name)
	return SAVE_DIR + safe_slot + SAVE_EXTENSION


func set_current_slot(slot_name: String) -> void:
	current_slot_name = _sanitize_slot_name(slot_name)
	_save_profile()


func get_current_slot() -> String:
	return _resolve_load_slot_name(current_slot_name)


func get_last_loaded_slot() -> String:
	return _resolve_load_slot_name(last_loaded_slot_name)


func save_current_game() -> bool:
	return save_game()


func auto_save_current_game() -> bool:
	if not _can_auto_save_now():
		return false
	return save_game()


func load_current_game() -> bool:
	var loaded: bool = await load_game()
	return loaded


func start_or_load_game(new_game_scene_path: String = "") -> bool:
	var slot_name := _resolve_load_slot_name()
	if has_save(slot_name):
		print("[SaveManager] 进入游戏前加载存档: ", slot_name)
		var loaded: bool = await load_game(slot_name)
		if loaded:
			return true
		push_warning("[SaveManager] 存档加载失败，不会自动新开: %s reason=%s" % [slot_name, last_error])
		return false
	last_error = "没有可用存档，无法继续游戏: " + slot_name
	print("[SaveManager] " + last_error)
	return false


func start_new_game(new_game_scene_path: String = "") -> bool:
	var use_external_cover := bool(get_meta(EXTERNAL_LOAD_COVER_META, false))
	_start_new_game_runtime()
	var target_scene := new_game_scene_path.strip_edges()
	if target_scene.is_empty():
		target_scene = "res://levels/level_bunker_render.tscn"
	if not ResourceLoader.exists(target_scene):
		last_error = "新游戏场景不存在: " + target_scene
		await _release_external_load_cover_if_needed(use_external_cover)
		return false
	var changed: bool = await _change_scene_after_threaded_load(target_scene, "进入新游戏场景失败")
	if not changed:
		await _release_external_load_cover_if_needed(use_external_cover)
		return false
	await _release_external_load_cover_if_needed(use_external_cover)
	current_slot_name = _resolve_slot_name(current_slot_name)
	last_loaded_slot_name = current_slot_name
	_save_profile(current_slot_name)
	return true


func _start_new_game_runtime() -> void:
	session_destroyed_objects.clear()
	var global_node := get_node_or_null("/root/Global")
	if global_node != null:
		if global_node.has_method("reset_shelter_inventory_runtime"):
			global_node.call("reset_shelter_inventory_runtime")
		if global_node.has_method("reset_outing_map_progress_runtime"):
			global_node.call("reset_outing_map_progress_runtime")
		if global_node.has_method("reset_time_state_runtime"):
			global_node.call("reset_time_state_runtime")


func list_save_slots() -> Array[Dictionary]:
	_ensure_save_dir()
	var result: Array[Dictionary] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return result
	for file_name in dir.get_files():
		if not file_name.ends_with(SAVE_EXTENSION):
			continue
		var slot_name := file_name.trim_suffix(SAVE_EXTENSION)
		var summary := get_save_summary(slot_name)
		if summary.is_empty():
			summary = {
				"slot_name": slot_name,
				"file_path": get_save_path(slot_name),
				"exists": true,
			}
		result.append(summary)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("unix_time", 0.0)) > float(b.get("unix_time", 0.0))
	)
	return result


func get_save_summary(slot_name: String = "") -> Dictionary:
	var resolved_slot := _resolve_slot_name(slot_name)
	var file_path := get_save_path(resolved_slot)
	if not FileAccess.file_exists(file_path):
		return {
			"slot_name": resolved_slot,
			"file_path": file_path,
			"exists": false,
		}
	var save_game := _load_save_resource(file_path)
	if save_game == null:
		return {
			"slot_name": resolved_slot,
			"file_path": file_path,
			"exists": true,
			"valid": false,
		}
	save_game.normalize()
	var metadata: Dictionary = save_game.metadata
	return {
		"slot_name": save_game.slot_name,
		"file_path": file_path,
		"exists": true,
		"valid": true,
		"last_saved_time": save_game.last_saved_time,
		"current_level_path": save_game.current_level_path,
		"display_name": save_game.get_display_name(),
		"unix_time": float(metadata.get("unix_time", 0.0)),
		"display_time": String(metadata.get("display_time", save_game.last_saved_time)),
		"scene_name": String(metadata.get("scene_name", save_game.current_level_path.get_file().get_basename())),
	}


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


func save_game(slot_name: String = "") -> bool:
	var resolved_slot := _resolve_slot_name(slot_name)
	if is_saving:
		last_error = "保存正在进行中"
		return false
	_ensure_save_dir()
	is_saving = true
	last_error = ""
	current_slot_name = resolved_slot
	save_started.emit(resolved_slot)

	var save_game := _build_save_game(resolved_slot)
	var file_path := get_save_path(resolved_slot)
	var result := ResourceSaver.save(save_game, file_path)
	var success := result == OK
	if success:
		last_loaded_slot_name = resolved_slot
		_save_profile(resolved_slot)
		print("[SaveManager] Game saved: ", file_path)
	else:
		last_error = "ResourceSaver.save failed: %d" % result
		push_error("[SaveManager] 保存失败 %s: %s" % [file_path, last_error])

	is_saving = false
	save_finished.emit(resolved_slot, success, file_path)
	return success


func load_game(slot_name: String = "") -> bool:
	var resolved_slot := _resolve_slot_name(slot_name)
	if is_loading:
		last_error = "读取正在进行中"
		return false
	var file_path := get_save_path(resolved_slot)
	if not FileAccess.file_exists(file_path):
		last_error = "存档不存在: " + file_path
		load_failed.emit(resolved_slot, last_error)
		return false

	is_loading = true
	last_error = ""
	current_slot_name = resolved_slot
	load_started.emit(resolved_slot)
	get_tree().paused = false

	var use_external_cover := bool(get_meta(EXTERNAL_LOAD_COVER_META, false))
	var transition_ui := null if use_external_cover else _ensure_transition_ui()
	var start_time := Time.get_ticks_msec()
	if not use_external_cover:
		_begin_transition(transition_ui)

	var save_game := _load_save_resource(file_path)
	if save_game == null:
		await _finish_load_transition(transition_ui, start_time)
		await _release_external_load_cover_if_needed(use_external_cover)
		is_loading = false
		last_error = "存档资源无法读取或类型不正确: " + file_path
		load_failed.emit(resolved_slot, last_error)
		load_finished.emit(resolved_slot, false)
		return false

	save_game.normalize()
	session_destroyed_objects = _string_array_from(save_game.destroyed_objects)
	_apply_global_payload(save_game.global_data)

	var scene_loaded := await _change_to_saved_scene(save_game.current_level_path)
	if not scene_loaded:
		await _finish_load_transition(transition_ui, start_time)
		await _release_external_load_cover_if_needed(use_external_cover)
		is_loading = false
		load_failed.emit(resolved_slot, last_error)
		load_finished.emit(resolved_slot, false)
		return false

	await _wait_scene_ready()
	_restore_scene_state(save_game)
	_apply_global_runtime_to_loaded_scene()
	await _wait_scene_ready()
	await _finish_load_transition(transition_ui, start_time)
	await _release_external_load_cover_if_needed(use_external_cover)

	is_loading = false
	last_loaded_slot_name = resolved_slot
	_save_profile(resolved_slot)
	load_finished.emit(resolved_slot, true)
	print("[SaveManager] Game loaded: ", file_path)
	return true


func set_external_load_cover_active(active: bool) -> void:
	set_meta(EXTERNAL_LOAD_COVER_META, active)


func _release_external_load_cover_if_needed(use_external_cover: bool) -> void:
	if not use_external_cover:
		return
	set_external_load_cover_active(false)
	var transition_ui := get_node_or_null("/root/TransitionUI")
	if transition_ui != null and transition_ui.has_method("release_cover"):
		await transition_ui.call("release_cover")
		if transition_ui.has_method("force_release_cover"):
			transition_ui.call("force_release_cover")


func delete_save(slot_name: String = "") -> bool:
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
		"display_time": _format_display_datetime_from_system(),
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
	var resource := SAFE_RESOURCE_LOADER.load(file_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	return resource as SaveGame


func _change_scene_after_threaded_load(target_scene: String, error_prefix: String) -> bool:
	if not ResourceLoader.exists(target_scene):
		last_error = "场景不存在: " + target_scene
		push_error("[SaveManager] " + last_error)
		return false
	var request_result := ResourceLoader.load_threaded_request(target_scene, "PackedScene", true)
	if request_result != OK and request_result != ERR_BUSY:
		last_error = "%s: %s (request %d)" % [error_prefix, target_scene, request_result]
		push_error("[SaveManager] " + last_error)
		return false
	while true:
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(target_scene, progress)
		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				var packed := ResourceLoader.load_threaded_get(target_scene) as PackedScene
				if packed == null:
					last_error = "%s: %s (not PackedScene)" % [error_prefix, target_scene]
					push_error("[SaveManager] " + last_error)
					return false
				var result := get_tree().change_scene_to_packed(packed)
				if result != OK:
					last_error = "%s: %s (%d)" % [error_prefix, target_scene, result]
					push_error("[SaveManager] " + last_error)
					return false
				await _wait_scene_ready()
				return true
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				last_error = "%s: %s (thread status %d)" % [error_prefix, target_scene, status]
				push_error("[SaveManager] " + last_error)
				return false
			_:
				await get_tree().process_frame
	return false


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
	var changed: bool = await _change_scene_after_threaded_load(target_scene, "切换存档场景失败")
	if not changed:
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
		_cleanup_save_data_before_restore(save_game.player_data)
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
		_cleanup_save_data_before_restore(data)
		var id := String(data.get("unique_id", ""))
		if id.is_empty() or session_destroyed_objects.has(id):
			continue
		if comp_dict.has(id) and is_instance_valid(comp_dict[id]):
			comp_dict[id].load_save_data(data)
		else:
			_restore_dynamic_object(current_scene, id, data)



func _cleanup_save_data_before_restore(data: Dictionary) -> void:
	if data.is_empty():
		return
	if data.has("inventory_payloads") and data["inventory_payloads"] is Dictionary:
		_remove_adapter_payload_entries(data["inventory_payloads"] as Dictionary)
	if data.has("component_states") and data["component_states"] is Dictionary:
		var component_states: Dictionary = data["component_states"]
		var keys_to_remove: Array = []
		for key in component_states.keys():
			var state := component_states.get(key, {}) as Dictionary
			if state.is_empty():
				continue
			var path_text := String(state.get("path", key))
			if _is_inventory_adapter_save_path(path_text):
				keys_to_remove.append(key)
		for key in keys_to_remove:
			component_states.erase(key)
	if data.has("siblings") and data["siblings"] is Dictionary:
		_remove_adapter_payload_entries(data["siblings"] as Dictionary)


func _remove_adapter_payload_entries(payloads: Dictionary) -> void:
	for key in payloads.keys().duplicate():
		if _is_inventory_adapter_save_path(String(key)):
			payloads.erase(key)


func _is_inventory_adapter_save_path(path_text: String) -> bool:
	return path_text.ends_with("LootContainerDataAdapter") or path_text == "LootContainerDataAdapter"

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
	var scene_path := tree.current_scene.scene_file_path.strip_edges()
	var global_node := get_node_or_null("/root/Global")
	if global_node != null and global_node.has_method("get_save_scene_path_override"):
		var override_path := String(global_node.call("get_save_scene_path_override", scene_path)).strip_edges()
		if not override_path.is_empty():
			return override_path
	return scene_path


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


func _apply_global_runtime_to_loaded_scene() -> void:
	var global_node := get_node_or_null("/root/Global")
	if global_node == null:
		return
	if global_node.has_method("apply_runtime_state_to_current_scene"):
		global_node.call("apply_runtime_state_to_current_scene")


func _load_profile() -> void:
	_ensure_save_dir()
	if not FileAccess.file_exists(PROFILE_PATH):
		current_slot_name = DEFAULT_SLOT
		last_loaded_slot_name = _find_newest_existing_slot()
		if not last_loaded_slot_name.is_empty() and has_save(last_loaded_slot_name):
			current_slot_name = last_loaded_slot_name
		print("[SaveManager] Profile missing, selected slot: ", current_slot_name, " last=", last_loaded_slot_name)
		return
	var profile := SAFE_RESOURCE_LOADER.load(PROFILE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	if profile == null:
		current_slot_name = DEFAULT_SLOT
		last_loaded_slot_name = _find_newest_existing_slot()
		if not last_loaded_slot_name.is_empty() and has_save(last_loaded_slot_name):
			current_slot_name = last_loaded_slot_name
		print("[SaveManager] Profile invalid, selected slot: ", current_slot_name, " last=", last_loaded_slot_name)
		return
	profile.normalize()
	current_slot_name = _sanitize_slot_name(String(profile.get("current_slot_name")))
	last_loaded_slot_name = _sanitize_slot_name(String(profile.get("last_loaded_slot_name")))
	if last_loaded_slot_name.is_empty() or not has_save(last_loaded_slot_name):
		last_loaded_slot_name = _find_newest_existing_slot()
	if not last_loaded_slot_name.is_empty() and has_save(last_loaded_slot_name):
		current_slot_name = last_loaded_slot_name
	elif not has_save(current_slot_name):
		var newest_slot := _find_newest_existing_slot()
		if not newest_slot.is_empty():
			current_slot_name = newest_slot
			last_loaded_slot_name = newest_slot
	print("[SaveManager] Profile loaded current=", current_slot_name, " last=", last_loaded_slot_name)


func _save_profile(loaded_slot_name: String = "") -> void:
	var profile := SAVE_PROFILE_SCRIPT.new() as Resource
	profile.set("current_slot_name", _resolve_slot_name(current_slot_name))
	var profile_last_slot := loaded_slot_name.strip_edges()
	if profile_last_slot.is_empty():
		profile_last_slot = last_loaded_slot_name.strip_edges()
	if profile_last_slot.is_empty():
		profile_last_slot = _resolve_slot_name(current_slot_name)
	last_loaded_slot_name = _sanitize_slot_name(profile_last_slot)
	profile.set("last_loaded_slot_name", last_loaded_slot_name)
	profile.set("last_saved_unix_time", Time.get_unix_time_from_system())
	profile.normalize()
	var result := ResourceSaver.save(profile, PROFILE_PATH)
	if result != OK:
		push_warning("[SaveManager] 保存全局进度配置失败 %s: %d" % [PROFILE_PATH, result])


func _setup_autosave_timer() -> void:
	if _autosave_timer != null:
		return
	_autosave_timer = Timer.new()
	_autosave_timer.name = "AutoSaveTimer"
	_autosave_timer.wait_time = AUTOSAVE_INTERVAL_SEC
	_autosave_timer.one_shot = false
	_autosave_timer.autostart = true
	_autosave_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_autosave_timer)
	_autosave_timer.timeout.connect(_on_autosave_timer_timeout)


func _on_autosave_timer_timeout() -> void:
	auto_save_current_game()


func _can_auto_save_now() -> bool:
	if not autosave_enabled or is_saving or is_loading:
		return false
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return false
	var scene_path := tree.current_scene.scene_file_path.strip_edges()
	if scene_path.is_empty() or scene_path == MAIN_MENU_SCENE_PATH:
		return false
	return true


func _try_boot_auto_load_from_non_menu_scene() -> void:
	await _wait_scene_ready()
	if is_loading or is_saving:
		return
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var scene_path := tree.current_scene.scene_file_path.strip_edges()
	if scene_path.is_empty() or scene_path == MAIN_MENU_SCENE_PATH:
		return
	var slot_name := _resolve_load_slot_name()
	if not has_save(slot_name):
		return
	print("[SaveManager] Debug/startup scene detected, auto-loading last progress: ", slot_name)
	await auto_load_game(slot_name)


func _find_newest_existing_slot() -> String:
	var newest_slot := ""
	var newest_time := -1.0
	for slot_name in [DEFAULT_SLOT, "slot_02", "slot_03"]:
		if not has_save(slot_name):
			continue
		var summary := get_save_summary(slot_name)
		var unix_time := float(summary.get("unix_time", 0.0))
		if unix_time > newest_time:
			newest_time = unix_time
			newest_slot = slot_name
	return newest_slot


func _format_display_datetime_from_system() -> String:
	var dt := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		int(dt.get("year", 0)),
		int(dt.get("month", 0)),
		int(dt.get("day", 0)),
		int(dt.get("hour", 0)),
		int(dt.get("minute", 0)),
		int(dt.get("second", 0)),
	]


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


func _resolve_slot_name(slot_name: String) -> String:
	var raw := slot_name.strip_edges()
	var safe := ""
	if not raw.is_empty():
		safe = _sanitize_slot_name(raw)
	if safe.is_empty():
		safe = _sanitize_slot_name(current_slot_name)
	if safe.is_empty():
		safe = DEFAULT_SLOT
	return safe


func _resolve_load_slot_name(slot_name: String = "") -> String:
	var raw := slot_name.strip_edges()
	if not raw.is_empty():
		return _sanitize_slot_name(raw)
	if not last_loaded_slot_name.strip_edges().is_empty() and FileAccess.file_exists(SAVE_DIR + _sanitize_slot_name(last_loaded_slot_name) + SAVE_EXTENSION):
		return _sanitize_slot_name(last_loaded_slot_name)
	if not current_slot_name.strip_edges().is_empty() and FileAccess.file_exists(SAVE_DIR + _sanitize_slot_name(current_slot_name) + SAVE_EXTENSION):
		return _sanitize_slot_name(current_slot_name)
	var newest_slot := _find_newest_existing_slot()
	if not newest_slot.is_empty():
		return newest_slot
	return _resolve_slot_name(current_slot_name)


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
