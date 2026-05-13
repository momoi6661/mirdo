extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_ai_manager_injects_provider_from_ai_settings()
	await _test_ai_manager_keeps_local_server_transport()
	await _test_ai_manager_skips_incomplete_provider()
	await _test_editor_request_tool_injects_provider()
	_finish()

func _test_ai_manager_injects_provider_from_ai_settings() -> void:
	var settings_script: Script = load("res://ai/AISettings.gd") as Script
	var manager_script: Script = load("res://ai/AIManager.gd") as Script
	_expect(settings_script != null, "AISettings.gd should load")
	_expect(manager_script != null, "AIManager.gd should load")
	if settings_script == null or manager_script == null:
		return

	var settings := settings_script.new() as Node
	root.add_child(settings)
	settings.call("set_provider_settings", " http://localhost:11434/v1/ ", " sk-test ", " qwen3 ", false)

	var manager := manager_script.new() as Node
	root.add_child(manager)
	manager.set("enable_true_sse_stream", false)
	manager.call("set_settings_service_for_tests", settings)

	var payload: Dictionary = manager.call("build_chat_request", "你好", "s1", 2, 600, {"hunger": 1, "thirst": 2, "mood": 3, "favor": 4}, "", {}, 8)
	var normalized: Dictionary = manager.call("_normalize_chat_request", payload)
	_expect(normalized.has("provider"), "normalized payload should include provider from AISettings")
	var provider: Dictionary = normalized.get("provider", {})
	_expect(String(provider.get("base_url", "")) == "http://localhost:11434/v1", "provider base_url should come from AISettings")
	_expect(String(provider.get("api_key", "")) == "sk-test", "provider api_key should come from AISettings")
	_expect(String(provider.get("model", "")) == "qwen3", "provider model should come from AISettings")

	manager.queue_free()
	settings.queue_free()
	await process_frame

func _test_ai_manager_keeps_local_server_transport() -> void:
	var settings_script: Script = load("res://ai/AISettings.gd") as Script
	var manager_script: Script = load("res://ai/AIManager.gd") as Script
	if settings_script == null or manager_script == null:
		return

	var settings := settings_script.new() as Node
	root.add_child(settings)
	settings.call("set_provider_settings", " https://api.example.test/v1/ ", "", "model-x", false)

	var manager := manager_script.new() as Node
	root.add_child(manager)
	manager.call("set_settings_service_for_tests", settings)
	var url: String = String(manager.call("_build_url", "/chat"))
	_expect(url == "http://127.0.0.1:5678/chat", "AIManager should still call local Server on port 5678; provider base_url only goes in payload")

	manager.queue_free()
	settings.queue_free()
	await process_frame

func _test_ai_manager_skips_incomplete_provider() -> void:
	var settings_script: Script = load("res://ai/AISettings.gd") as Script
	var manager_script: Script = load("res://ai/AIManager.gd") as Script
	if settings_script == null or manager_script == null:
		return

	var settings := settings_script.new() as Node
	root.add_child(settings)
	settings.call("set_provider_settings", "", "", "", false)

	var manager := manager_script.new() as Node
	root.add_child(manager)
	manager.call("set_settings_service_for_tests", settings)
	var payload: Dictionary = manager.call("build_chat_request", "你好", "s1")
	var normalized: Dictionary = manager.call("_normalize_chat_request", payload)
	_expect(not normalized.has("provider"), "AIManager should not inject incomplete provider settings")
	_expect(bool(manager.get("enable_true_sse_stream")) == false, "AIManager should default to non-streaming /chat for current Server")

	manager.queue_free()
	settings.queue_free()
	await process_frame

func _test_editor_request_tool_injects_provider() -> void:
	var settings_script: Script = load("res://ai/AISettings.gd") as Script
	var tool_script: Script = load("res://ai/AIEditorRequestTool.gd") as Script
	if settings_script == null or tool_script == null:
		return

	var settings := settings_script.new() as Node
	root.add_child(settings)
	settings.call("set_provider_settings", " https://api.example.test/v1/ ", " editor-key ", " editor-model ", false)

	var tool := tool_script.new() as Node
	root.add_child(tool)
	tool.call("set_settings_service_for_tests", settings)
	var payload: Dictionary = tool.call("_build_chat_payload")
	_expect(payload.has("provider"), "AIEditorRequestTool payload should include provider from AISettings")
	var provider: Dictionary = payload.get("provider", {})
	_expect(String(provider.get("base_url", "")) == "https://api.example.test/v1", "editor provider base_url should be normalized")
	_expect(String(provider.get("api_key", "")) == "editor-key", "editor provider api_key should be normalized")
	_expect(String(provider.get("model", "")) == "editor-model", "editor provider model should be normalized")

	tool.queue_free()
	settings.queue_free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] ai manager settings bridge")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
