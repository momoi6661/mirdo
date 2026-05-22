@tool
extends Node
class_name AIEditorRequestTool

@export var server_host: String = "127.0.0.1"
@export_range(1, 65535, 1) var server_port: int = 5678
@export var use_https: bool = false

@export var chat_endpoint_path: String = "/chat"
@export var probe_endpoint_path: String = "/model/probe"
@export var clear_memory_endpoint_path: String = "/memory/clear"

@export var session_id: String = "default_session"
@export var shared_runtime_session_id: String = "current_save_slot"
@export var auto_map_editor_session: bool = true
@export var player_text: String = "你好，小空。"
@export var given_item: String = ""
@export var day: int = 1
@export_range(0, 1440, 1) var time_min: int = 540
@export var hunger: int = 50
@export var thirst: int = 50
@export var mood: int = 50
@export var favor: int = 20
@export var max_context_turns: int = 8

@export var debug_transparent: bool = true
@export var request_source: String = "godot_editor_tool"
@export_multiline var context_json: String = "{}"

@export_multiline var last_request_json: String = "{}"
@export_multiline var last_response_json: String = "{}"
@export var last_status: String = "idle"
@export var warn_when_game_not_running: bool = true
@export var use_ai_settings_service: bool = true

var _send_chat_trigger: bool = false
@export var send_chat_now: bool:
	get:
		return _send_chat_trigger
	set(value):
		_send_chat_trigger = value
		if value:
			call_deferred("_editor_send_chat")
			_send_chat_trigger = false

var _probe_trigger: bool = false
@export var probe_model_now: bool:
	get:
		return _probe_trigger
	set(value):
		_probe_trigger = value
		if value:
			call_deferred("_editor_probe_model")
			_probe_trigger = false

var _clear_memory_trigger: bool = false
@export var clear_memory_now: bool:
	get:
		return _clear_memory_trigger
	set(value):
		_clear_memory_trigger = value
		if value:
			call_deferred("_editor_clear_memory")
			_clear_memory_trigger = false

var _chat_request: HTTPRequest
var _probe_request: HTTPRequest
var _clear_request: HTTPRequest
var _chat_busy: bool = false
var _probe_busy: bool = false
var _clear_busy: bool = false
var _settings_service: Node = null

func _ready() -> void:
	_resolve_settings_service()
	_ensure_requests()

func send_chat_manual() -> void:
	_editor_send_chat()

func probe_model_manual() -> void:
	_editor_probe_model()

func clear_memory_manual() -> void:
	_editor_clear_memory()

func _editor_send_chat() -> void:
	_ensure_requests()
	if _chat_busy:
		last_status = "chat_busy"
		return

	var payload := _build_chat_payload()
	last_request_json = JSON.stringify(payload, "\t", false)
	var url := _build_url(_normalize_path(chat_endpoint_path, "/chat"))
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
	])
	var body := JSON.stringify(payload)
	var err := _chat_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		last_status = "chat_request_failed_%d" % err
		push_warning("[AIEditorRequestTool] %s" % last_status)
		return
	_chat_busy = true
	last_status = "chat_requesting"
	print("[AIEditorRequestTool] chat_request payload=%s" % last_request_json)
	if warn_when_game_not_running and not _is_editor_playing_scene():
		var hint := _get_editor_scene_hint()
		push_warning("[AIEditorRequestTool] 当前未运行游戏场景，3D字幕不会显示。请先运行关卡场景（建议 level_001）。当前编辑场景=%s" % hint)

func _editor_probe_model() -> void:
	_ensure_requests()
	if _probe_busy:
		last_status = "probe_busy"
		return

	last_request_json = "{}"
	var url := _build_url(_normalize_path(probe_endpoint_path, "/model/probe"))
	var headers := PackedStringArray(["Accept: application/json"])
	var err := _probe_request.request(url, headers, HTTPClient.METHOD_GET, "")
	if err != OK:
		last_status = "probe_request_failed_%d" % err
		push_warning("[AIEditorRequestTool] %s" % last_status)
		return
	_probe_busy = true
	last_status = "probe_requesting"
	print("[AIEditorRequestTool] probe_request url=%s" % url)

func _editor_clear_memory() -> void:
	_ensure_requests()
	if _clear_busy:
		last_status = "clear_memory_busy"
		return

	var clean_session := session_id.strip_edges()
	if clean_session.is_empty():
		clean_session = "default_session"
		session_id = clean_session
	clean_session = _resolve_effective_session_id(clean_session)
	session_id = clean_session
	var payload := {
		"clear_all": false,
		"session_id": clean_session,
	}
	last_request_json = JSON.stringify(payload, "\t", false)
	var url := _build_url(_normalize_path(clear_memory_endpoint_path, "/memory/clear"))
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
	])
	var err := _clear_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		last_status = "clear_memory_request_failed_%d" % err
		push_warning("[AIEditorRequestTool] %s" % last_status)
		return
	_clear_busy = true
	last_status = "clear_memory_requesting"
	print("[AIEditorRequestTool] clear_memory payload=%s" % last_request_json)

func _on_chat_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_chat_busy = false
	var body_text := body.get_string_from_utf8()
	var response_data := _parse_json_dict(body_text)
	last_response_json = _to_pretty_response(body_text)
	if result != HTTPRequest.RESULT_SUCCESS:
		last_status = "chat_network_error_%d" % result
	elif response_code < 200 or response_code >= 300:
		last_status = "chat_http_%d" % response_code
	elif response_data.has("ok") and not bool(response_data.get("ok", true)):
		var err_text := String(response_data.get("error", "backend_error"))
		last_status = "chat_backend_error_%s" % _error_to_status_suffix(err_text)
	else:
		last_status = "chat_ok_%d" % response_code
	print("[AIEditorRequestTool] %s response=%s" % [last_status, last_response_json])

func _on_probe_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_probe_busy = false
	var body_text := body.get_string_from_utf8()
	var response_data := _parse_json_dict(body_text)
	last_response_json = _to_pretty_response(body_text)
	if result != HTTPRequest.RESULT_SUCCESS:
		last_status = "probe_network_error_%d" % result
	elif response_code < 200 or response_code >= 300:
		last_status = "probe_http_%d" % response_code
	elif response_data.has("ok") and not bool(response_data.get("ok", true)):
		var probe_error := String(response_data.get("error", response_data.get("status", "probe_error")))
		last_status = "probe_backend_error_%s" % _error_to_status_suffix(probe_error)
	else:
		last_status = "probe_ok_%d" % response_code
	print("[AIEditorRequestTool] %s response=%s" % [last_status, last_response_json])

func _on_clear_memory_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_clear_busy = false
	var body_text := body.get_string_from_utf8()
	var response_data := _parse_json_dict(body_text)
	last_response_json = _to_pretty_response(body_text)
	if result != HTTPRequest.RESULT_SUCCESS:
		last_status = "clear_memory_network_error_%d" % result
	elif response_code < 200 or response_code >= 300:
		last_status = "clear_memory_http_%d" % response_code
	elif response_data.has("ok") and not bool(response_data.get("ok", true)):
		var clear_error := String(response_data.get("error", "clear_memory_failed"))
		last_status = "clear_memory_backend_error_%s" % _error_to_status_suffix(clear_error)
	else:
		last_status = "clear_memory_ok_%d" % response_code
	print("[AIEditorRequestTool] %s response=%s" % [last_status, last_response_json])

func _build_chat_payload() -> Dictionary:
	var clean_session := session_id.strip_edges()
	if clean_session.is_empty():
		clean_session = "default_session"
		session_id = clean_session
	clean_session = _resolve_effective_session_id(clean_session)
	session_id = clean_session

	var context_dict := _parse_context_json(context_json)
	var checkpoint := _build_ai_checkpoint_context(clean_session)
	for key in checkpoint.keys():
		context_dict[key] = checkpoint[key]
	context_dict["debug_transparent"] = debug_transparent
	context_dict["request_source"] = request_source.strip_edges() if not request_source.strip_edges().is_empty() else "godot_editor_tool"
	context_dict["source"] = context_dict["request_source"]

	var payload: Dictionary = {
		"day": day,
		"time": time_min,
		"time_min": time_min,
		"session_id": clean_session,
		"npc_stats": {
			"hunger": hunger,
			"thirst": thirst,
			"mood": mood,
			"favor": favor,
		},
		"player_text": player_text.strip_edges(),
		"given_item": given_item.strip_edges(),
		"context": context_dict,
	}
	var provider := _build_provider_from_settings()
	if not provider.is_empty():
		payload["provider"] = provider
	if max_context_turns > 0:
		payload["max_context_turns"] = max_context_turns
	return payload


func set_settings_service_for_tests(service: Node) -> void:
	_settings_service = service

func _resolve_settings_service() -> void:
	if not use_ai_settings_service:
		return
	if _settings_service != null and is_instance_valid(_settings_service):
		return
	_settings_service = get_node_or_null("/root/AISettings")

func _build_provider_from_settings() -> Dictionary:
	_resolve_settings_service()
	if _settings_service == null:
		return {}
	var base_url := String(_settings_service.get("base_url")).strip_edges()
	while base_url.length() > 1 and base_url.ends_with("/"):
		base_url = base_url.substr(0, base_url.length() - 1)
	var api_key := String(_settings_service.get("api_key")).strip_edges()
	var model := String(_settings_service.get("model")).strip_edges()
	var proxy_url := ""
	if _settings_service.get("proxy_url") != null:
		proxy_url = String(_settings_service.get("proxy_url")).strip_edges()
	if base_url.is_empty() or model.is_empty():
		return {}
	var provider := {
		"base_url": base_url,
		"api_key": api_key,
		"model": model,
	}
	if not proxy_url.is_empty():
		provider["proxy_url"] = proxy_url
	return provider

func _resolve_effective_session_id(raw_session_id: String) -> String:
	var clean := raw_session_id.strip_edges()
	if clean.is_empty():
		clean = "default_session"
	if auto_map_editor_session and clean == "editor_session":
		var mapped := shared_runtime_session_id.strip_edges()
		if not mapped.is_empty():
			clean = mapped
		else:
			clean = "default_session"
	if clean == "current_save_slot" or clean == "mirdo_session":
		return _build_save_scoped_session_id(_resolve_save_slot_name())
	return clean

func _resolve_save_slot_name() -> String:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("get_current_slot"):
		var current_slot := String(save_manager.call("get_current_slot")).strip_edges()
		if not current_slot.is_empty():
			return current_slot
	return "manual_save"

func _build_save_scoped_session_id(save_slot: String) -> String:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("get_current_ai_timeline_id"):
		var timeline := String(save_manager.call("get_current_ai_timeline_id")).strip_edges()
		if not timeline.is_empty():
			return timeline
	var slot := _sanitize_session_part(save_slot)
	if slot.is_empty():
		slot = "manual_save"
	return "mirdo:%s" % slot

func _sanitize_session_part(value: String) -> String:
	var clean := value.strip_edges()
	if clean.is_empty():
		return ""
	for ch in [" ", "\t", "\n", "\r", "/", "\\", ":", "?", "#", "&", "="]:
		clean = clean.replace(ch, "_")
	while clean.find("__") >= 0:
		clean = clean.replace("__", "_")
	return clean.trim_prefix("_").trim_suffix("_")


func _build_ai_checkpoint_context(clean_session_id: String) -> Dictionary:
	var context := {"session_id": clean_session_id, "save_slot": _resolve_save_slot_name()}
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("build_ai_checkpoint_context"):
		var checkpoint = save_manager.call("build_ai_checkpoint_context")
		if checkpoint is Dictionary:
			for key in (checkpoint as Dictionary).keys():
				context[key] = checkpoint[key]
	context["session_id"] = clean_session_id
	return context

func _parse_context_json(raw_text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(raw_text) == OK and parser.data is Dictionary:
		return (parser.data as Dictionary).duplicate(true)
	return {}

func _to_pretty_response(raw_text: String) -> String:
	var parser := JSON.new()
	if parser.parse(raw_text) == OK:
		return JSON.stringify(parser.data, "\t", false)
	return raw_text

func _parse_json_dict(raw_text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(raw_text) == OK and parser.data is Dictionary:
		return (parser.data as Dictionary).duplicate(true)
	return {}

func _error_to_status_suffix(raw_text: String) -> String:
	var clean := raw_text.strip_edges()
	if clean.is_empty():
		return "unknown_error"
	var safe := clean.replace(" ", "_").replace(":", "_").replace("/", "_").replace("\\", "_")
	if safe.length() > 48:
		safe = safe.substr(0, 48)
	return safe

func _build_url(path: String) -> String:
	var protocol := "https" if use_https else "http"
	return "%s://%s:%d%s" % [protocol, server_host, server_port, path]

func _normalize_path(path_text: String, fallback_path: String) -> String:
	var path := path_text.strip_edges()
	if path.is_empty():
		path = fallback_path
	if not path.begins_with("/"):
		path = "/" + path
	return path

func _ensure_requests() -> void:
	if _chat_request == null or not is_instance_valid(_chat_request):
		_chat_request = HTTPRequest.new()
		_chat_request.name = "EditorChatRequest"
		add_child(_chat_request)
		if not _chat_request.request_completed.is_connected(_on_chat_completed):
			_chat_request.request_completed.connect(_on_chat_completed)

	if _probe_request == null or not is_instance_valid(_probe_request):
		_probe_request = HTTPRequest.new()
		_probe_request.name = "EditorProbeRequest"
		add_child(_probe_request)
		if not _probe_request.request_completed.is_connected(_on_probe_completed):
			_probe_request.request_completed.connect(_on_probe_completed)

	if _clear_request == null or not is_instance_valid(_clear_request):
		_clear_request = HTTPRequest.new()
		_clear_request.name = "EditorClearMemoryRequest"
		add_child(_clear_request)
		if not _clear_request.request_completed.is_connected(_on_clear_memory_completed):
			_clear_request.request_completed.connect(_on_clear_memory_completed)

func _is_editor_playing_scene() -> bool:
	var editor_interface = Engine.get_singleton("EditorInterface")
	if editor_interface == null:
		return false
	return bool(editor_interface.is_playing_scene())

func _get_editor_scene_hint() -> String:
	var editor_interface = Engine.get_singleton("EditorInterface")
	if editor_interface == null:
		return "<unknown>"
	var scene = editor_interface.get_edited_scene_root()
	if scene == null:
		return "<none>"
	if not String(scene.scene_file_path).is_empty():
		return String(scene.scene_file_path)
	return String(scene.name)
