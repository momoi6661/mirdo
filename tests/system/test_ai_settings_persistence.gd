extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_settings_resource_roundtrip()
	await _test_settings_panel_auto_saves()
	await _test_pause_menu_loads_ai_settings_panel()
	_finish()


func _test_settings_resource_roundtrip() -> void:
	var script: Script = load("res://ai/AISettings.gd") as Script
	_expect(script != null, "AISettings.gd should load")
	if script == null:
		return

	var path := "user://codex_test_ai_settings.cfg"
	_delete_user_file("codex_test_ai_settings.cfg")

	var settings := script.new() as Node
	_expect(settings != null, "AISettings should instantiate as Node")
	if settings == null:
		return
	root.add_child(settings)
	settings.call("set_config_path_for_tests", path)
	settings.call("load_settings")

	_expect(String(settings.get("base_url")) == "http://127.0.0.1:18080", "default base_url should target local backend")
	_expect(String(settings.get("api_key")) == "", "default api_key should be empty")
	_expect(String(settings.get("model")) == "", "default model should be empty")

	settings.call("set_provider_settings", " http://localhost:11434/v1/ ", " sk-test ", " qwen3 ")
	_expect(String(settings.get("base_url")) == "http://localhost:11434/v1", "base_url should trim whitespace and trailing slash")
	_expect(String(settings.get("api_key")) == "sk-test", "api_key should trim whitespace")
	_expect(String(settings.get("model")) == "qwen3", "model should trim whitespace")

	var saved: bool = bool(settings.call("save_settings"))
	_expect(saved, "save_settings should return true")
	settings.queue_free()
	await process_frame

	var loaded_settings := script.new() as Node
	root.add_child(loaded_settings)
	loaded_settings.call("set_config_path_for_tests", path)
	loaded_settings.call("load_settings")
	_expect(String(loaded_settings.get("base_url")) == "http://localhost:11434/v1", "base_url should roundtrip")
	_expect(String(loaded_settings.get("api_key")) == "sk-test", "api_key should roundtrip")
	_expect(String(loaded_settings.get("model")) == "qwen3", "model should roundtrip")
	loaded_settings.queue_free()
	await process_frame
	_delete_user_file("codex_test_ai_settings.cfg")


func _test_settings_panel_auto_saves() -> void:
	var settings_script: Script = load("res://ai/AISettings.gd") as Script
	var panel_scene: PackedScene = load("res://controllers/ui/AISettingsPanel.tscn") as PackedScene
	_expect(settings_script != null, "AISettings.gd should load for panel test")
	_expect(panel_scene != null, "AISettingsPanel.tscn should load")
	if settings_script == null or panel_scene == null:
		return

	var path := "user://codex_test_ai_settings_panel.cfg"
	_delete_user_file("codex_test_ai_settings_panel.cfg")

	var settings := settings_script.new() as Node
	root.add_child(settings)
	settings.call("set_config_path_for_tests", path)
	settings.call("load_settings")

	var panel := panel_scene.instantiate() as CanvasLayer
	root.add_child(panel)
	panel.call("set_settings_service", settings)
	panel.call("open_panel")
	await process_frame

	_expect(panel.layer >= 20, "AI settings panel should render above pause menu shader overlay")
	var drawer := panel.get_node_or_null("%DrawerPanel") as Panel
	_expect(drawer != null, "AI settings panel should use a right-side DrawerPanel")
	if drawer != null:
		_expect(drawer.anchor_left == 1.0 and drawer.anchor_right == 1.0, "DrawerPanel should be anchored to the right edge")
		_expect(drawer.custom_minimum_size.x >= 700.0, "DrawerPanel should be a large side panel, not a small modal")

	var base_line := panel.get_node_or_null("%BaseUrlLineEdit") as LineEdit
	var key_line := panel.get_node_or_null("%ApiKeyLineEdit") as LineEdit
	var model_line := panel.get_node_or_null("%ModelLineEdit") as LineEdit
	_expect(base_line != null, "BaseUrlLineEdit should exist")
	_expect(key_line != null, "ApiKeyLineEdit should exist")
	_expect(model_line != null, "ModelLineEdit should exist")
	if base_line == null or key_line == null or model_line == null:
		panel.queue_free()
		settings.queue_free()
		return

	base_line.text = " http://localhost:9999/v1/ "
	base_line.text_changed.emit(base_line.text)
	key_line.text = " panel-key "
	key_line.text_changed.emit(key_line.text)
	model_line.text = " panel-model "
	model_line.text_changed.emit(model_line.text)

	await _wait_seconds(0.8)

	var loaded_settings := settings_script.new() as Node
	root.add_child(loaded_settings)
	loaded_settings.call("set_config_path_for_tests", path)
	loaded_settings.call("load_settings")
	_expect(String(loaded_settings.get("base_url")) == "http://localhost:9999/v1", "panel should auto-save base_url")
	_expect(String(loaded_settings.get("api_key")) == "panel-key", "panel should auto-save api_key")
	_expect(String(loaded_settings.get("model")) == "panel-model", "panel should auto-save model")

	loaded_settings.queue_free()
	panel.queue_free()
	settings.queue_free()
	await process_frame
	_delete_user_file("codex_test_ai_settings_panel.cfg")


func _test_pause_menu_loads_ai_settings_panel() -> void:
	var pause_scene: PackedScene = load("res://controllers/ui/pause_menu.tscn") as PackedScene
	_expect(pause_scene != null, "pause_menu.tscn should load with AI settings panel dependency")
	if pause_scene == null:
		return
	var pause_menu := pause_scene.instantiate() as CanvasLayer
	_expect(pause_menu != null, "pause_menu should instantiate as CanvasLayer")
	if pause_menu == null:
		return
	root.add_child(pause_menu)
	await process_frame
	var panel := pause_menu.get_node_or_null("%AISettingsPanel")
	_expect(panel != null, "pause menu should contain AISettingsPanel unique node")
	if panel != null:
		_expect((panel as CanvasLayer).layer >= 20, "pause menu AISettingsPanel should render above shader overlay")
	if pause_menu.has_method("_on_options_pressed"):
		pause_menu.call("_on_options_pressed")
		await process_frame
		if panel != null:
			_expect(bool(panel.get("visible")), "options button should open AI settings panel")
	pause_menu.queue_free()
	await process_frame


func _wait_seconds(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var delta := process_frame
		await delta
		left -= 0.016


func _delete_user_file(file_name: String) -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists(file_name):
		dir.remove(file_name)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] ai settings persistence")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
