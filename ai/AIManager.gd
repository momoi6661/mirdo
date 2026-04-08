extends Node
class_name AIManager

signal on_ai_stream_chunk_received(chunk: String)
signal on_ai_response_completed(final_data: Dictionary)
signal on_ai_request_error(error_msg: String)
signal on_session_history_received(session_id: String, response: Dictionary)
signal on_session_history_error(session_id: String, error_msg: String)
signal on_session_event_received(session_id: String, event: Dictionary)
signal on_session_event_error(session_id: String, error_msg: String)
signal on_session_event_stream_state_changed(session_id: String, connected: bool)
signal on_model_probe_received(response: Dictionary)
signal on_model_probe_error(error_msg: String)

@export var server_host: String = "127.0.0.1"
@export_range(1, 65535, 1) var server_port: int = 18080
@export var chat_stream_endpoint_path: String = "/chat_stream"
@export var chat_endpoint_path: String = "/chat"
@export var debug_subtitle_endpoint_path: String = "/debug/subtitle_test_stream"
@export var debug_subtitle_once_endpoint_path: String = "/debug/subtitle_test"
@export var model_probe_endpoint_path: String = "/model/probe"
@export var session_event_stream_endpoint_template: String = "/session/{session_id}/events/stream"
@export var endpoint_path: String = "/chat_stream" # deprecated: kept for old scenes
@export var use_https: bool = false
@export var request_timeout_sec: float = 20.0
@export var enable_true_sse_stream: bool = false
@export var session_event_stream_enabled: bool = false
@export_range(0.005, 0.2, 0.005) var stream_poll_interval_sec: float = 0.02
@export_range(0.5, 60.0, 0.5) var session_event_keepalive_timeout_sec: float = 30.0
@export_range(0.2, 10.0, 0.1) var session_event_reconnect_delay_sec: float = 1.5
@export var debug_log: bool = false
@export var always_log: bool = true

var is_requesting: bool = false

var _http_request: HTTPRequest
var _history_request: HTTPRequest
var _probe_request: HTTPRequest
var _last_request_payload: Dictionary = {}
var _last_request_context: Dictionary = {}
var _history_requesting: bool = false
var _history_request_session_id: String = ""
var _probe_requesting: bool = false
var _stream_client: HTTPClient
var _stream_active: bool = false
var _stream_request_sent: bool = false
var _stream_response_code: int = 0
var _stream_headers: PackedStringArray = PackedStringArray()
var _stream_path: String = ""
var _stream_body: String = ""
var _stream_raw_body: String = ""
var _stream_sse_buffer: String = ""
var _stream_chunks: Array[String] = []
var _stream_last_event: Dictionary = {}
var _stream_full_json_so_far: String = ""
var _stream_done: bool = false
var _stream_elapsed_sec: float = 0.0
var _stream_poll_elapsed: float = 0.0
var _event_client: HTTPClient
var _event_stream_active: bool = false
var _event_stream_request_sent: bool = false
var _event_stream_response_code: int = 0
var _event_stream_session_id: String = ""
var _event_stream_path: String = ""
var _event_sse_buffer: String = ""
var _event_elapsed_sec: float = 0.0
var _event_last_io_sec: float = 0.0
var _event_poll_elapsed: float = 0.0
var _event_reconnect_left_sec: float = -1.0
var _event_last_turn_id: int = 0

func _ready() -> void:
	_ensure_http_request()
	_ensure_history_request()
	_ensure_probe_request()
	set_process(true)

func _process(delta: float) -> void:
	_process_chat_stream(delta)
	_process_event_stream(delta)

func _process_chat_stream(delta: float) -> void:
	if not _stream_active:
		return
	_stream_elapsed_sec += delta
	if request_timeout_sec > 0.0 and _stream_elapsed_sec >= request_timeout_sec:
		_stop_stream_client()
		_emit_error("stream_timeout")
		return
	_stream_poll_elapsed += delta
	if _stream_poll_elapsed < stream_poll_interval_sec:
		return
	_stream_poll_elapsed = 0.0
	_poll_stream_client()

func _process_event_stream(delta: float) -> void:
	if _event_reconnect_left_sec >= 0.0:
		_event_reconnect_left_sec -= delta
		if _event_reconnect_left_sec <= 0.0:
			_event_reconnect_left_sec = -1.0
			if session_event_stream_enabled and (not _event_stream_session_id.is_empty()):
				_start_session_event_stream_internal(_event_stream_session_id)

	if not _event_stream_active:
		return

	_event_elapsed_sec += delta
	_event_last_io_sec += delta
	if session_event_keepalive_timeout_sec > 0.0 and _event_last_io_sec >= session_event_keepalive_timeout_sec:
		_schedule_event_stream_reconnect("event_keepalive_timeout")
		return

	_event_poll_elapsed += delta
	if _event_poll_elapsed < stream_poll_interval_sec:
		return
	_event_poll_elapsed = 0.0
	_poll_event_stream_client()

# 标准入口：构建与后端 ChatRequest 对齐的 payload。
# 后端字段：day,time,time_min,npc_stats,session_id,max_context_turns,player_text,given_item,context
func build_chat_request(
		text: String,
		session_id: String = "default_session",
		day: int = 1,
		time_min: int = 0,
		npc_stats: Dictionary = {},
		given_item: String = "",
		context: Dictionary = {},
		max_context_turns: int = -1
	) -> Dictionary:
	var clean_text := text.strip_edges()

	var clean_session_id := session_id.strip_edges()
	if clean_session_id.is_empty():
		clean_session_id = "default_session"

	var clean_stats := _normalize_npc_stats(npc_stats)
	var payload: Dictionary = {
		"day": int(day),
		"time": int(time_min),
		"time_min": int(time_min),
		"session_id": clean_session_id,
		"npc_stats": clean_stats,
		"player_text": clean_text,
		"given_item": given_item.strip_edges(),
		"context": context.duplicate(true),
	}
	if max_context_turns > 0:
		payload["max_context_turns"] = int(max_context_turns)
	return payload

# 标准入口：流式对话，对应后端 POST /chat_stream
func request_chat_stream(request_payload: Dictionary, context: Dictionary = {}) -> bool:
	var normalized := _normalize_chat_request(request_payload)
	if not enable_true_sse_stream:
		return _send_json_request(normalized, context, _resolve_chat_endpoint())
	return _send_stream_request(normalized, context, _resolve_chat_stream_endpoint())

# 标准入口：一次性对话，对应后端 POST /chat
func request_chat_once(request_payload: Dictionary, context: Dictionary = {}) -> bool:
	var normalized := _normalize_chat_request(request_payload)
	return _send_json_request(normalized, context, _resolve_chat_endpoint())

# 标准入口：调试字幕流，对应后端 POST /debug/subtitle_test_stream
func request_subtitle_test_stream(request_payload: Dictionary, context: Dictionary = {}) -> bool:
	var normalized := _normalize_chat_request(request_payload)
	if not enable_true_sse_stream:
		var once_endpoint := debug_subtitle_once_endpoint_path.strip_edges()
		if once_endpoint.is_empty():
			once_endpoint = "/debug/subtitle_test"
		return _send_json_request(normalized, context, once_endpoint)
	return _send_stream_request(normalized, context, debug_subtitle_endpoint_path)

# 标准入口：拉取会话历史，对应后端 GET /session/{session_id}/history?limit=N
func request_session_history(session_id: String, limit: int = 20) -> bool:
	_ensure_history_request()
	if _history_requesting:
		return false

	var clean_session_id := session_id.strip_edges()
	if clean_session_id.is_empty():
		clean_session_id = "default_session"
	var safe_limit := maxi(1, mini(int(limit), 200))
	var path := "/session/%s/history?limit=%d" % [clean_session_id.uri_encode(), safe_limit]
	var url := _build_url(path)
	var headers := PackedStringArray(["Accept: application/json"])

	var err := _history_request.request(url, headers, HTTPClient.METHOD_GET, "")
	if err != OK:
		on_session_history_error.emit(clean_session_id, "request_failed_%d" % err)
		_log("history_request_failed session_id=%s err=%d" % [clean_session_id, err])
		return false

	_history_requesting = true
	_history_request_session_id = clean_session_id
	_log("history_request_start session_id=%s limit=%d" % [clean_session_id, safe_limit])
	return true

# 标准入口：模型可用性探测，对应后端 GET /model/probe
func request_model_probe() -> bool:
	_ensure_probe_request()
	if _probe_requesting:
		return false

	var path := model_probe_endpoint_path.strip_edges()
	if path.is_empty():
		path = "/model/probe"
	if not path.begins_with("/"):
		path = "/" + path

	var url := _build_url(path)
	var headers := PackedStringArray(["Accept: application/json"])
	var err := _probe_request.request(url, headers, HTTPClient.METHOD_GET, "")
	if err != OK:
		on_model_probe_error.emit("request_failed_%d" % err)
		_log("model_probe_request_failed err=%d" % err)
		return false

	_probe_requesting = true
	_log("model_probe_request_start url=%s" % url)
	return true

func start_session_event_stream(session_id: String, last_turn_id: int = -1) -> bool:
	if not session_event_stream_enabled:
		return false

	var clean_session_id := session_id.strip_edges()
	if clean_session_id.is_empty():
		clean_session_id = "default_session"

	if clean_session_id != _event_stream_session_id and last_turn_id < 0:
		_event_last_turn_id = 0

	if last_turn_id >= 0:
		_event_last_turn_id = maxi(_event_last_turn_id, int(last_turn_id))

	if _event_stream_active and clean_session_id == _event_stream_session_id:
		return true

	_event_reconnect_left_sec = -1.0
	return _start_session_event_stream_internal(clean_session_id)

func stop_session_event_stream() -> void:
	_event_reconnect_left_sec = -1.0
	_stop_event_stream_client(true)
	_event_stream_session_id = ""

func set_session_event_last_turn_id(turn_id: int) -> void:
	_event_last_turn_id = maxi(_event_last_turn_id, int(turn_id))

# 兼容旧接口：极简调用
func send_text_simple(
		text: String,
		session_id: String = "default_session",
		given_item: String = "",
		context: Dictionary = {}
	) -> bool:
	var payload := build_chat_request(text, session_id, 1, 0, {}, given_item, context, -1)
	if String(payload.get("player_text", "")).is_empty():
		_emit_error("empty_text")
		return false
	return request_chat_stream(payload, {"type": "simple_chat"})

func send_interaction_stream(
		day: int,
		time: int,
		hunger: int,
		thirst: int,
		mood: int,
		favor: int,
		text: String,
		item: String = ""
	) -> bool:
	var request_data := build_chat_request(
		text,
		"default_session",
		day,
		time,
		{
			"hunger": hunger,
			"thirst": thirst,
			"mood": mood,
			"favor": favor,
		},
		item,
		{},
		-1
	)
	return request_chat_stream(request_data, {"type": "interaction"})

func send_subtitle_test_stream(test_text: String = "Subtitle debug test", session_id: String = "fps_subtitle_test") -> bool:
	var clean_session_id := session_id.strip_edges()
	if clean_session_id.is_empty():
		clean_session_id = "fps_subtitle_test"

	var payload := build_chat_request(
		test_text.strip_edges(),
		clean_session_id,
		1,
		540,
		{},
		"",
		{"source": "fps_subtitle_debug"},
		-1
	)
	return request_subtitle_test_stream(payload, {"type": "subtitle_test"})

# 兼容旧接口：保留，但统一走标准请求发送。
func send_chat_payload(payload: Dictionary, context: Dictionary = {}, endpoint_override: String = "") -> bool:
	var normalized := _normalize_chat_request(payload)
	var endpoint := endpoint_override.strip_edges()
	if endpoint.is_empty():
		endpoint = _resolve_chat_stream_endpoint()

	var chat_once_endpoint := _resolve_chat_endpoint().strip_edges()
	var chat_stream_endpoint := _resolve_chat_stream_endpoint().strip_edges()
	var compare_endpoint := endpoint
	if not compare_endpoint.begins_with("/"):
		compare_endpoint = "/" + compare_endpoint
	if not chat_once_endpoint.begins_with("/"):
		chat_once_endpoint = "/" + chat_once_endpoint
	if not chat_stream_endpoint.begins_with("/"):
		chat_stream_endpoint = "/" + chat_stream_endpoint

	if not enable_true_sse_stream and compare_endpoint == chat_stream_endpoint:
		return _send_json_request(normalized, context, chat_once_endpoint)

	if compare_endpoint == chat_once_endpoint:
		return _send_json_request(normalized, context, compare_endpoint)
	return _send_stream_request(normalized, context, compare_endpoint)

func _send_json_request(payload: Dictionary, context: Dictionary = {}, endpoint_override: String = "") -> bool:
	_ensure_http_request()

	if is_requesting:
		_log("request_rejected reason=request_in_progress")
		_emit_error("request_in_progress")
		return false

	var resolved_endpoint := endpoint_override
	if resolved_endpoint.strip_edges().is_empty():
		resolved_endpoint = _resolve_chat_endpoint() if (not enable_true_sse_stream) else _resolve_chat_stream_endpoint()
	var trimmed_endpoint := resolved_endpoint.strip_edges()
	if trimmed_endpoint.is_empty():
		_emit_error("endpoint_path_empty")
		return false
	if not trimmed_endpoint.begins_with("/"):
		trimmed_endpoint = "/" + trimmed_endpoint

	var url := _build_url(trimmed_endpoint)
	var headers = PackedStringArray([
		"Content-Type: application/json",
		"Accept: text/event-stream, application/json",
	])
	var body := JSON.stringify(payload)

	var session_id_text := String(payload.get("session_id", "")).strip_edges()
	var player_text := String(payload.get("player_text", "")).strip_edges()
	if player_text.length() > 48:
		player_text = player_text.substr(0, 48) + "..."
	_log("request_start url=%s session_id=%s text=%s" % [url, session_id_text, player_text])
	var transparent_payload := false
	var context_value: Variant = payload.get("context", {})
	if context_value is Dictionary:
		transparent_payload = bool((context_value as Dictionary).get("debug_transparent", false))
	if debug_log or transparent_payload:
		_log("payload=%s" % JSON.stringify(payload))

	_http_request.timeout = request_timeout_sec
	var err := _http_request.request(
		url,
		headers,
		HTTPClient.METHOD_POST,
		body
	)
	if err != OK:
		_log("request_failed err=%d" % err)
		_emit_error("request_failed_%d" % err)
		return false

	is_requesting = true
	_last_request_payload = payload.duplicate(true)
	_last_request_context = context.duplicate(true)
	return true

func _send_stream_request(payload: Dictionary, context: Dictionary = {}, endpoint_override: String = "") -> bool:
	if not enable_true_sse_stream:
		return _send_json_request(payload, context, endpoint_override)

	if is_requesting:
		_log("request_rejected reason=request_in_progress")
		_emit_error("request_in_progress")
		return false

	var resolved_endpoint := _resolve_chat_stream_endpoint() if endpoint_override.strip_edges().is_empty() else endpoint_override
	var trimmed_endpoint := resolved_endpoint.strip_edges()
	if trimmed_endpoint.is_empty():
		_emit_error("endpoint_path_empty")
		return false
	if not trimmed_endpoint.begins_with("/"):
		trimmed_endpoint = "/" + trimmed_endpoint

	var body := JSON.stringify(payload)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: text/event-stream, application/json",
		"Cache-Control: no-cache",
		"Connection: keep-alive",
	])
	var url := _build_url(trimmed_endpoint)

	var session_id_text := String(payload.get("session_id", "")).strip_edges()
	var player_text := String(payload.get("player_text", "")).strip_edges()
	if player_text.length() > 48:
		player_text = player_text.substr(0, 48) + "..."
	_log("stream_request_start url=%s session_id=%s text=%s" % [url, session_id_text, player_text])
	var transparent_payload := false
	var context_value: Variant = payload.get("context", {})
	if context_value is Dictionary:
		transparent_payload = bool((context_value as Dictionary).get("debug_transparent", false))
	if debug_log or transparent_payload:
		_log("stream_payload=%s" % JSON.stringify(payload))

	_stop_stream_client()
	_stream_client = HTTPClient.new()
	var connect_err := OK
	if use_https:
		connect_err = _stream_client.connect_to_host(server_host, server_port, TLSOptions.client())
	else:
		connect_err = _stream_client.connect_to_host(server_host, server_port)
	if connect_err != OK:
		_log("stream_connect_failed err=%d" % connect_err)
		_emit_error("stream_connect_failed_%d" % connect_err)
		return false

	_stream_active = true
	_stream_request_sent = false
	_stream_response_code = 0
	_stream_headers = headers
	_stream_path = trimmed_endpoint
	_stream_body = body
	_stream_raw_body = ""
	_stream_sse_buffer = ""
	_stream_chunks.clear()
	_stream_last_event = {}
	_stream_full_json_so_far = ""
	_stream_done = false
	_stream_elapsed_sec = 0.0
	_stream_poll_elapsed = 0.0
	is_requesting = true
	_last_request_payload = payload.duplicate(true)
	_last_request_context = context.duplicate(true)
	return true

func _poll_stream_client() -> void:
	if _stream_client == null:
		_stop_stream_client()
		_emit_error("stream_client_missing")
		return

	var poll_err := _stream_client.poll()
	if poll_err != OK:
		_stop_stream_client()
		_emit_error("stream_poll_failed_%d" % poll_err)
		return

	var status := _stream_client.get_status()
	match status:
		HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			_stop_stream_client()
			_emit_error("stream_connection_error_%d" % status)
			return
		HTTPClient.STATUS_CONNECTED:
			if not _stream_request_sent:
				var request_err := _stream_client.request(HTTPClient.METHOD_POST, _stream_path, _stream_headers, _stream_body)
				if request_err != OK:
					_stop_stream_client()
					_emit_error("stream_request_failed_%d" % request_err)
					return
				_stream_request_sent = true
				return
			if _stream_request_sent and _stream_response_code != 0:
				_finalize_stream_request()
			return
		HTTPClient.STATUS_REQUESTING:
			return
		HTTPClient.STATUS_BODY:
			if _stream_response_code == 0:
				_stream_response_code = _stream_client.get_response_code()
				_log("stream_response_header code=%d" % _stream_response_code)
			_read_stream_body_chunks()
			if _stream_done:
				_finalize_stream_request()
			return
		HTTPClient.STATUS_DISCONNECTED:
			if _stream_request_sent:
				_read_stream_body_chunks()
				_finalize_stream_request()
				return
			_stop_stream_client()
			_emit_error("stream_disconnected")
			return
		_:
			return

func _start_session_event_stream_internal(clean_session_id: String) -> bool:
	_stop_event_stream_client(false)
	_event_stream_session_id = clean_session_id

	_event_client = HTTPClient.new()
	var connect_err := OK
	if use_https:
		connect_err = _event_client.connect_to_host(server_host, server_port, TLSOptions.client())
	else:
		connect_err = _event_client.connect_to_host(server_host, server_port)
	if connect_err != OK:
		_stop_event_stream_client(false)
		on_session_event_error.emit(clean_session_id, "event_connect_failed_%d" % connect_err)
		return false

	_event_stream_path = _build_session_event_stream_path(clean_session_id, _event_last_turn_id)
	_event_stream_active = true
	_event_stream_request_sent = false
	_event_stream_response_code = 0
	_event_sse_buffer = ""
	_event_elapsed_sec = 0.0
	_event_last_io_sec = 0.0
	_event_poll_elapsed = 0.0
	_log("event_stream_start session_id=%s path=%s" % [clean_session_id, _event_stream_path])
	return true

func _poll_event_stream_client() -> void:
	if _event_client == null:
		_schedule_event_stream_reconnect("event_client_missing")
		return

	var poll_err := _event_client.poll()
	if poll_err != OK:
		_schedule_event_stream_reconnect("event_poll_failed_%d" % poll_err)
		return

	var status := _event_client.get_status()
	match status:
		HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			_schedule_event_stream_reconnect("event_connection_error_%d" % status)
			return
		HTTPClient.STATUS_CONNECTED:
			if not _event_stream_request_sent:
				var headers := PackedStringArray([
					"Accept: text/event-stream",
					"Cache-Control: no-cache",
					"Connection: keep-alive",
				])
				var request_err := _event_client.request(HTTPClient.METHOD_GET, _event_stream_path, headers, "")
				if request_err != OK:
					_schedule_event_stream_reconnect("event_request_failed_%d" % request_err)
					return
				_event_stream_request_sent = true
			return
		HTTPClient.STATUS_REQUESTING:
			return
		HTTPClient.STATUS_BODY:
			if _event_stream_response_code == 0:
				_event_stream_response_code = _event_client.get_response_code()
				if _event_stream_response_code < 200 or _event_stream_response_code >= 300:
					_schedule_event_stream_reconnect("event_http_%d" % _event_stream_response_code)
					return
				on_session_event_stream_state_changed.emit(_event_stream_session_id, true)
				_log("event_stream_connected session_id=%s code=%d" % [_event_stream_session_id, _event_stream_response_code])
			_read_event_stream_body_chunks()
			return
		HTTPClient.STATUS_DISCONNECTED:
			_schedule_event_stream_reconnect("event_disconnected")
			return
		_:
			return

func _read_event_stream_body_chunks() -> void:
	if _event_client == null:
		return

	while true:
		var chunk := _event_client.read_response_body_chunk()
		if chunk.is_empty():
			break
		var text_part := chunk.get_string_from_utf8()
		if text_part.is_empty():
			continue
		_event_last_io_sec = 0.0
		_event_sse_buffer += text_part
		_consume_event_sse_buffer(false)

func _consume_event_sse_buffer(force_flush: bool) -> void:
	_event_sse_buffer = _event_sse_buffer.replace("\r\n", "\n").replace("\r", "\n")
	while true:
		var sep_idx := _event_sse_buffer.find("\n\n")
		if sep_idx < 0:
			break
		var raw_event := _event_sse_buffer.substr(0, sep_idx)
		_event_sse_buffer = _event_sse_buffer.substr(sep_idx + 2)
		_consume_event_sse_event(raw_event)
	if force_flush and not _event_sse_buffer.strip_edges().is_empty():
		_consume_event_sse_event(_event_sse_buffer)
		_event_sse_buffer = ""

func _consume_event_sse_event(raw_event: String) -> void:
	var lines := raw_event.split("\n")
	var payload_text := ""

	for line in lines:
		var trimmed_line := line.strip_edges()
		if trimmed_line.begins_with(":"):
			_event_last_io_sec = 0.0
			continue
		if not trimmed_line.begins_with("data:"):
			continue
		var data_part := trimmed_line.substr(5).strip_edges()
		if data_part.is_empty():
			continue
		if not payload_text.is_empty():
			payload_text += "\n"
		payload_text += data_part

	payload_text = payload_text.strip_edges()
	if payload_text.is_empty() or payload_text == "[DONE]":
		return

	var parser := JSON.new()
	if parser.parse(payload_text) != OK or parser.data is not Dictionary:
		return

	var packet := parser.data as Dictionary
	var event_value: Variant = packet.get("event", {})
	if event_value is not Dictionary:
		return
	var event_data := (event_value as Dictionary).duplicate(true)
	var event_session := String(event_data.get("session_id", _event_stream_session_id)).strip_edges()
	if event_session != _event_stream_session_id:
		return

	var turn_id := int(event_data.get("turn_id", 0))
	if turn_id > _event_last_turn_id:
		_event_last_turn_id = turn_id
	on_session_event_received.emit(_event_stream_session_id, event_data)

func _schedule_event_stream_reconnect(reason: String) -> void:
	var session_id := _event_stream_session_id
	_stop_event_stream_client(true)
	if session_id.is_empty():
		return
	on_session_event_error.emit(session_id, reason)
	if not session_event_stream_enabled:
		return
	_event_reconnect_left_sec = session_event_reconnect_delay_sec
	_log("event_stream_reconnect session_id=%s delay=%.2f reason=%s" % [session_id, session_event_reconnect_delay_sec, reason])

func _stop_event_stream_client(emit_disconnect: bool) -> void:
	if _event_client != null:
		_event_client.close()
	_event_client = null
	if emit_disconnect and (not _event_stream_session_id.is_empty()):
		on_session_event_stream_state_changed.emit(_event_stream_session_id, false)
	_event_stream_active = false
	_event_stream_request_sent = false
	_event_stream_response_code = 0
	_event_stream_path = ""
	_event_sse_buffer = ""
	_event_elapsed_sec = 0.0
	_event_last_io_sec = 0.0
	_event_poll_elapsed = 0.0

func _build_session_event_stream_path(session_id: String, last_turn_id: int = 0) -> String:
	var template := session_event_stream_endpoint_template.strip_edges()
	if template.is_empty():
		template = "/session/{session_id}/events/stream"
	var path := template.replace("{session_id}", session_id.uri_encode())
	if not path.begins_with("/"):
		path = "/" + path
	if last_turn_id > 0:
		var sep := "?" if path.find("?") < 0 else "&"
		path += "%slast_turn_id=%d" % [sep, int(last_turn_id)]
	return path

func _read_stream_body_chunks() -> void:
	if _stream_client == null:
		return

	while true:
		var chunk := _stream_client.read_response_body_chunk()
		if chunk.is_empty():
			break
		var text_part := chunk.get_string_from_utf8()
		if text_part.is_empty():
			continue
		_stream_raw_body += text_part
		_stream_sse_buffer += text_part
		_consume_sse_buffer(false)

func _consume_sse_buffer(force_flush: bool) -> void:
	_stream_sse_buffer = _stream_sse_buffer.replace("\r\n", "\n").replace("\r", "\n")

	while true:
		var sep_idx := _stream_sse_buffer.find("\n\n")
		if sep_idx < 0:
			break
		var raw_event := _stream_sse_buffer.substr(0, sep_idx)
		_stream_sse_buffer = _stream_sse_buffer.substr(sep_idx + 2)
		_consume_sse_event(raw_event)

	if force_flush and not _stream_sse_buffer.strip_edges().is_empty():
		_consume_sse_event(_stream_sse_buffer)
		_stream_sse_buffer = ""

func _consume_sse_event(raw_event: String) -> void:
	var lines := raw_event.split("\n")
	var payload_text := ""
	for line in lines:
		var trimmed_line := line.strip_edges()
		if not trimmed_line.begins_with("data:"):
			continue
		var data_part := trimmed_line.substr(5).strip_edges()
		if data_part.is_empty():
			continue
		if not payload_text.is_empty():
			payload_text += "\n"
		payload_text += data_part

	payload_text = payload_text.strip_edges()
	if payload_text.is_empty():
		return
	if payload_text == "[DONE]":
		_stream_done = true
		return

	var parser := JSON.new()
	if parser.parse(payload_text) != OK or parser.data is not Dictionary:
		return

	var event_data: Dictionary = parser.data
	_stream_last_event = event_data.duplicate(true)

	var chunk_text := String(event_data.get("dialogue_chunk", ""))
	if not chunk_text.is_empty():
		_stream_chunks.append(chunk_text)
		on_ai_stream_chunk_received.emit(chunk_text)

	var full_json_candidate := String(event_data.get("full_json_so_far", ""))
	if not full_json_candidate.is_empty():
		_stream_full_json_so_far = full_json_candidate

	if bool(event_data.get("is_done", false)):
		_stream_done = true

func _finalize_stream_request() -> void:
	_consume_sse_buffer(true)

	var response_code := _stream_response_code
	var raw_body := _stream_raw_body
	var emitted_chunks_count := _stream_chunks.size()

	var final_data: Dictionary = {}
	if not _stream_full_json_so_far.is_empty():
		var final_parser := JSON.new()
		if final_parser.parse(_stream_full_json_so_far) == OK and final_parser.data is Dictionary:
			final_data = final_parser.data
	if final_data.is_empty() and not _stream_last_event.is_empty():
		final_data = _stream_last_event.duplicate(true)

	var fallback_chunks: Array = []
	if final_data.is_empty():
		var parsed := _parse_response(raw_body)
		fallback_chunks = parsed.get("chunks", [])
		final_data = parsed.get("final", {})

	_stop_stream_client()
	is_requesting = false

	if response_code < 200 or response_code >= 300:
		var compact_body := raw_body.strip_edges()
		var tail := "" if compact_body.is_empty() else (": " + compact_body)
		_log("http_error code=%d body=%s" % [response_code, compact_body])
		_emit_error("http_%d%s" % [response_code, tail])
		return

	if final_data.is_empty():
		_log("parse_error reason=empty_or_invalid_ai_response raw_len=%d" % raw_body.length())
		_emit_error("empty_or_invalid_ai_response")
		return

	if emitted_chunks_count <= 0:
		for chunk_value in fallback_chunks:
			var chunk_text := String(chunk_value)
			if not chunk_text.is_empty():
				on_ai_stream_chunk_received.emit(chunk_text)
				emitted_chunks_count += 1

	if emitted_chunks_count <= 0:
		var one_shot_text := _extract_dialogue_text(final_data)
		if not one_shot_text.is_empty():
			on_ai_stream_chunk_received.emit(one_shot_text)
			emitted_chunks_count = 1

	_log("stream_request_ok chunks=%d final_keys=%s" % [emitted_chunks_count, str(final_data.keys())])
	if debug_log:
		_log("final=%s" % JSON.stringify(final_data))

	on_ai_response_completed.emit(final_data)

func _stop_stream_client() -> void:
	if _stream_client != null:
		_stream_client.close()
	_stream_client = null
	_stream_active = false
	_stream_request_sent = false
	_stream_response_code = 0
	_stream_headers = PackedStringArray()
	_stream_path = ""
	_stream_body = ""
	_stream_raw_body = ""
	_stream_sse_buffer = ""
	_stream_chunks.clear()
	_stream_last_event = {}
	_stream_full_json_so_far = ""
	_stream_done = false
	_stream_elapsed_sec = 0.0
	_stream_poll_elapsed = 0.0

func cancel_request() -> void:
	_stop_stream_client()
	if _http_request != null:
		_http_request.cancel_request()
	if _probe_request != null:
		_probe_request.cancel_request()
	_probe_requesting = false
	is_requesting = false

func _ensure_http_request() -> void:
	if _http_request != null and is_instance_valid(_http_request):
		return

	_http_request = HTTPRequest.new()
	_http_request.name = "AIRequest"
	add_child(_http_request)
	if not _http_request.request_completed.is_connected(_on_request_completed):
		_http_request.request_completed.connect(_on_request_completed)

func _ensure_history_request() -> void:
	if _history_request != null and is_instance_valid(_history_request):
		return

	_history_request = HTTPRequest.new()
	_history_request.name = "AIHistoryRequest"
	add_child(_history_request)
	if not _history_request.request_completed.is_connected(_on_history_request_completed):
		_history_request.request_completed.connect(_on_history_request_completed)

func _ensure_probe_request() -> void:
	if _probe_request != null and is_instance_valid(_probe_request):
		return

	_probe_request = HTTPRequest.new()
	_probe_request.name = "AIModelProbeRequest"
	add_child(_probe_request)
	if not _probe_request.request_completed.is_connected(_on_probe_request_completed):
		_probe_request.request_completed.connect(_on_probe_request_completed)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	is_requesting = false
	_log("request_completed result=%d response_code=%d body_bytes=%d" % [result, response_code, body.size()])

	if result != HTTPRequest.RESULT_SUCCESS:
		_emit_error("network_error_%d" % result)
		return

	var body_text := body.get_string_from_utf8()
	if response_code < 200 or response_code >= 300:
		var compact_body = body_text.strip_edges()
		var tail = "" if compact_body.is_empty() else (": " + compact_body)
		_log("http_error code=%d body=%s" % [response_code, compact_body])
		_emit_error("http_%d%s" % [response_code, tail])
		return

	var parsed = _parse_response(body_text)
	var chunks: Array = parsed.get("chunks", [])
	for chunk_value in chunks:
		var chunk_text := String(chunk_value)
		if not chunk_text.is_empty():
			on_ai_stream_chunk_received.emit(chunk_text)

	var final_data: Dictionary = parsed.get("final", {})
	if final_data.is_empty():
		_log("parse_error reason=empty_or_invalid_ai_response raw_len=%d" % body_text.length())
		_emit_error("empty_or_invalid_ai_response")
		return

	if chunks.is_empty():
		var one_shot_text := _extract_dialogue_text(final_data)
		if not one_shot_text.is_empty():
			on_ai_stream_chunk_received.emit(one_shot_text)

	_log("request_ok chunks=%d final_keys=%s" % [chunks.size(), str(final_data.keys())])
	if debug_log:
		_log("final=%s" % JSON.stringify(final_data))

	on_ai_response_completed.emit(final_data)

func _on_history_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var target_session_id := _history_request_session_id
	_history_requesting = false
	_history_request_session_id = ""
	_log("history_request_completed result=%d code=%d body_bytes=%d" % [result, response_code, body.size()])

	if result != HTTPRequest.RESULT_SUCCESS:
		on_session_history_error.emit(target_session_id, "network_error_%d" % result)
		return

	var body_text := body.get_string_from_utf8()
	if response_code < 200 or response_code >= 300:
		on_session_history_error.emit(target_session_id, "http_%d" % response_code)
		return

	var parser := JSON.new()
	if parser.parse(body_text) != OK or parser.data is not Dictionary:
		on_session_history_error.emit(target_session_id, "invalid_history_json")
		return

	on_session_history_received.emit(target_session_id, parser.data)

func _on_probe_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_probe_requesting = false
	_log("model_probe_completed result=%d code=%d body_bytes=%d" % [result, response_code, body.size()])

	if result != HTTPRequest.RESULT_SUCCESS:
		on_model_probe_error.emit("network_error_%d" % result)
		return

	var body_text := body.get_string_from_utf8()
	if response_code < 200 or response_code >= 300:
		on_model_probe_error.emit("http_%d" % response_code)
		return

	var parser := JSON.new()
	if parser.parse(body_text) != OK or parser.data is not Dictionary:
		on_model_probe_error.emit("invalid_probe_json")
		return

	on_model_probe_received.emit(parser.data)

func _parse_response(raw_text: String) -> Dictionary:
	# 1) Try direct JSON first.
	var direct_json := JSON.new()
	if direct_json.parse(raw_text) == OK and direct_json.data is Dictionary:
		return {
			"chunks": [],
			"final": direct_json.data,
		}

	# 2) Parse SSE lines: data: {...}
	var chunks: Array[String] = []
	var full_json_so_far := ""
	var last_event: Dictionary = {}

	var lines = raw_text.split("\n")
	for line in lines:
		var trimmed = line.strip_edges()
		if not trimmed.begins_with("data:"):
			continue

		var payload_text = trimmed.substr(5).strip_edges()
		if payload_text.is_empty() or payload_text == "[DONE]":
			continue

		var event_json := JSON.new()
		if event_json.parse(payload_text) != OK or event_json.data is not Dictionary:
			continue

		var event_data: Dictionary = event_json.data
		last_event = event_data

		var chunk_text = String(event_data.get("dialogue_chunk", ""))
		if not chunk_text.is_empty():
			chunks.append(chunk_text)

		var full_json_candidate = String(event_data.get("full_json_so_far", ""))
		if not full_json_candidate.is_empty():
			full_json_so_far = full_json_candidate

		if bool(event_data.get("is_done", false)):
			break

	if not full_json_so_far.is_empty():
		var final_json := JSON.new()
		if final_json.parse(full_json_so_far) == OK and final_json.data is Dictionary:
			return {
				"chunks": chunks,
				"final": final_json.data,
			}

	# 3) Fallback to last SSE event data.
	if not last_event.is_empty():
		return {
			"chunks": chunks,
			"final": last_event,
		}

	return {
		"chunks": chunks,
		"final": {},
	}

func _extract_dialogue_text(final_data: Dictionary) -> String:
	for key in ["dialogue", "reply", "text", "message", "summary"]:
		var value = String(final_data.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return ""

func _build_url(path: String) -> String:
	var protocol = "https" if use_https else "http"
	return "%s://%s:%d%s" % [protocol, server_host, server_port, path]

func _resolve_chat_stream_endpoint() -> String:
	var endpoint := chat_stream_endpoint_path.strip_edges()
	if endpoint.is_empty():
		endpoint = endpoint_path.strip_edges()
	if endpoint.is_empty():
		endpoint = "/chat_stream"
	return endpoint

func _resolve_chat_endpoint() -> String:
	var endpoint := chat_endpoint_path.strip_edges()
	if endpoint.is_empty():
		endpoint = "/chat"
	return endpoint

func _normalize_npc_stats(raw_stats: Dictionary) -> Dictionary:
	var source := raw_stats.duplicate(true)
	return {
		"hunger": int(source.get("hunger", 50)),
		"thirst": int(source.get("thirst", 50)),
		"mood": int(source.get("mood", 50)),
		"favor": int(source.get("favor", 20)),
	}

func _normalize_chat_request(raw_payload: Dictionary) -> Dictionary:
	var payload := raw_payload.duplicate(true)

	var day_value := int(payload.get("day", 1))
	var time_min_value := int(payload.get("time_min", payload.get("time", 0)))
	var session_id_value := String(payload.get("session_id", "default_session")).strip_edges()
	if session_id_value.is_empty():
		session_id_value = "default_session"

	var text_value := String(payload.get("player_text", "")).strip_edges()
	var item_value := String(payload.get("given_item", "")).strip_edges()

	var context_value := {}
	var raw_context = payload.get("context", {})
	if raw_context is Dictionary:
		context_value = (raw_context as Dictionary).duplicate(true)

	var stats_value := {}
	var raw_stats = payload.get("npc_stats", {})
	if raw_stats is Dictionary:
		stats_value = (raw_stats as Dictionary).duplicate(true)

	var normalized := {
		"day": day_value,
		"time": time_min_value,
		"time_min": time_min_value,
		"npc_stats": _normalize_npc_stats(stats_value),
		"session_id": session_id_value,
		"player_text": text_value,
		"given_item": item_value,
		"context": context_value,
	}
	if payload.has("max_context_turns"):
		var max_context_turns_value := int(payload.get("max_context_turns", 0))
		if max_context_turns_value > 0:
			normalized["max_context_turns"] = max_context_turns_value
	return normalized

func _emit_error(msg: String) -> void:
	is_requesting = false
	_log("request_error %s" % msg)
	on_ai_request_error.emit(msg)

func _log(message: String) -> void:
	if always_log or debug_log:
		print("[AIManager] %s" % message)
