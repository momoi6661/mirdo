extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var save_manager := root.get_node_or_null("SaveManager")
	var global_node := root.get_node_or_null("Global")
	_expect(save_manager != null, "SaveManager autoload should exist")
	_expect(global_node != null, "Global autoload should exist")
	if save_manager == null or global_node == null:
		_finish()
		return

	_test_current_slot_save(save_manager)
	_test_legacy_save_entrypoints_follow_current_slot(save_manager)
	_test_save_time_and_last_played_slot(save_manager)
	_test_ai_context_uses_current_save_slot(save_manager)
	_test_outing_map_save_scene_override(save_manager, global_node)
	_test_save_slot_menu_scene_loads()
	_test_outing_time_without_scene_time_component(global_node)
	_finish()


func _test_current_slot_save(save_manager: Node) -> void:
	var slot_name := "codex_slot_resource_save"
	save_manager.delete_save(slot_name)
	save_manager.set_current_slot(slot_name)
	var saved: bool = save_manager.save_game()
	_expect(saved, "save_game() with empty argument should save current slot")
	_expect(save_manager.has_save(slot_name), "current slot save file should exist")
	var summary: Dictionary = save_manager.get_save_summary(slot_name)
	_expect(bool(summary.get("valid", false)), "saved slot summary should be valid")
	_expect(String(summary.get("slot_name", "")) == slot_name, "saved slot summary should keep slot name")
	var listed := false
	for entry_raw in save_manager.list_save_slots():
		var entry := entry_raw as Dictionary
		if String(entry.get("slot_name", "")) == slot_name:
			listed = true
			break
	_expect(listed, "list_save_slots should include current slot")
	save_manager.delete_save(slot_name)


func _test_legacy_save_entrypoints_follow_current_slot(save_manager: Node) -> void:
	var slot_name := "codex_legacy_current_slot"
	save_manager.delete_save(slot_name)
	save_manager.set_current_slot(slot_name)
	var saved := false
	if save_manager.has_method("save_current_game"):
		saved = bool(save_manager.call("save_current_game"))
	else:
		saved = bool(save_manager.call("save_game"))
	_expect(saved, "legacy save entrypoint should save the current slot")
	_expect(save_manager.has_save(slot_name), "legacy save entrypoint should not fall back to manual_save")
	save_manager.delete_save(slot_name)


func _test_save_time_and_last_played_slot(save_manager: Node) -> void:
	var slot_name := "codex_last_played_slot"
	save_manager.delete_save(slot_name)
	save_manager.set_current_slot(slot_name)
	var saved := bool(save_manager.call("save_current_game"))
	_expect(saved, "save_current_game should write current slot for last-played tracking")
	var summary: Dictionary = save_manager.get_save_summary(slot_name)
	_expect(String(summary.get("display_time", "")).strip_edges() != "", "save summary should expose display_time")
	_expect(String(save_manager.call("get_last_loaded_slot")) == slot_name, "saving current progress should mark this as the last played slot")
	save_manager.delete_save(slot_name)


func _test_ai_context_uses_current_save_slot(save_manager: Node) -> void:
	var slot_name := "codex_ai_context_slot"
	save_manager.set_current_slot(slot_name)

	var xiaokong_script := load("res://scripts/xiaokong/components/xiaokong_ai_dialogue_component.gd") as Script
	var xiaokong := xiaokong_script.new() as Node
	root.add_child(xiaokong)
	var x_payload: Dictionary = xiaokong.call("_build_dialogue_payload", "测试", "")
	var x_context: Dictionary = x_payload.get("context", {}) as Dictionary
	_expect(String(x_context.get("save_slot", "")) == slot_name, "Xiaokong AI context should use SaveManager current slot when no explicit override is set")
	xiaokong.call("_load_custom_save_data", {"save_slot_name": "manual_save"})
	_expect(String(xiaokong.get("save_slot_name")) == "", "legacy Xiaokong manual_save field should migrate to dynamic current slot")
	xiaokong.queue_free()

	var character_script := load("res://scripts/character_ai/components/character_ai_dialogue_component.gd") as Script
	var character := character_script.new() as Node
	root.add_child(character)
	var c_payload: Dictionary = character.call("_build_chat_payload", "测试", "")
	var c_context: Dictionary = c_payload.get("context", {}) as Dictionary
	_expect(String(c_context.get("save_slot", "")) == slot_name, "Generic character AI context should use SaveManager current slot when no explicit override is set")
	character.queue_free()


func _test_outing_map_save_scene_override(save_manager: Node, global_node: Node) -> void:
	var slot_name := "codex_outing_scene_override"
	var return_path := "res://levels/bunker_local_pbr.tscn"
	var previous_scene := current_scene
	var previous_return_path := String(global_node.get("outing_return_scene_path"))
	var dummy_scene := Node.new()
	dummy_scene.name = "DummyOutingMapScene"
	dummy_scene.scene_file_path = "res://levels/outing/OutingMap.tscn"
	root.add_child(dummy_scene)
	current_scene = dummy_scene
	global_node.set("outing_return_scene_path", return_path)
	save_manager.delete_save(slot_name)
	var saved: bool = save_manager.save_game(slot_name)
	_expect(saved, "saving while on OutingMap should succeed")
	var summary: Dictionary = save_manager.get_save_summary(slot_name)
	_expect(String(summary.get("current_level_path", "")) == return_path, "OutingMap save should store return shelter scene instead of the map scene")
	save_manager.delete_save(slot_name)
	global_node.set("outing_return_scene_path", previous_return_path)
	current_scene = previous_scene
	dummy_scene.queue_free()


func _test_save_slot_menu_scene_loads() -> void:
	var scene := load("res://controllers/ui/SaveSlotMenu.tscn") as PackedScene
	_expect(scene != null, "SaveSlotMenu scene should load")
	if scene == null:
		return
	var instance := scene.instantiate()
	root.add_child(instance)
	_expect(instance.has_method("open_panel"), "SaveSlotMenu should expose open_panel")
	instance.call("open_panel", "progress")
	_expect(instance.visible, "SaveSlotMenu should become visible when opened")
	var slot_list := instance.get_node_or_null("%SlotList")
	_expect(slot_list != null and slot_list.get_child_count() == 3, "SaveSlotMenu should render exactly three progress slots")
	instance.queue_free()


func _test_outing_time_without_scene_time_component(global_node: Node) -> void:
	global_node.call("apply_global_save_payload", {
		"version": 3,
		"time_state": {
			"version": 1,
			"current_day": 2,
			"current_hour": 22.5,
			"day_length_hours": 24.0,
			"realtime_enabled": false,
		},
	})
	global_node.call("advance_outing_time_minutes", 180, "test_outing")
	var payload: Dictionary = global_node.call("build_global_save_payload")
	var time_state: Dictionary = payload.get("time_state", {}) as Dictionary
	_expect(int(time_state.get("current_day", 0)) == 3, "outing time should roll over to next day without a scene TimeComponent")
	_expect(absf(float(time_state.get("current_hour", 0.0)) - 1.5) < 0.001, "outing time should keep the post-expedition hour")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] save slots and outing time")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
