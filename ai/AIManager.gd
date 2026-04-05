extends Node
class_name AIManager

signal on_ai_stream_chunk_received(chunk: String)
signal on_ai_response_completed(final_data: Dictionary)
signal on_ai_request_error(error_msg: String)

@export var server_host: String = "127.0.0.1"
@export_range(1, 65535, 1) var server_port: int = 8000
@export var endpoint_path: String = "/chat_stream"
@export var use_https: bool = false
@export var request_timeout_sec: float = 20.0
@export var debug_log: bool = false

var is_requesting: bool = false

var _http_request: HTTPRequest
var _last_request_payload: Dictionary = {}
var _last_request_context: Dictionary = {}

func _ready() -> void:
	_ensure_http_request()

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
	var request_data = {
		"day": day,
		"time": time,
		"time_min": time,
		"npc_stats": {
			"hunger": hunger,
			"thirst": thirst,
			"mood": mood,
			"favor": favor,
		},
		# Keep old compatibility keys for existing backend prompt logic.
		"ai_hunger": hunger,
		"ai_thirst": thirst,
		"ai_mood": mood,
		"ai_favor": favor,
		"player_text": text,
		"given_item": item,
	}
	return send_chat_payload(request_data, {"type": "interaction"})

func send_chat_payload(payload: Dictionary, context: Dictionary = {}) -> bool:
	_ensure_http_request()

	if is_requesting:
		_emit_error("request_in_progress")
		return false

	var trimmed_endpoint := endpoint_path.strip_edges()
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

	if debug_log:
		print("AIManager -> ", url)
		print("AIManager payload: ", payload)

	_http_request.timeout = request_timeout_sec
	var err := _http_request.request(
		url,
		headers,
		HTTPClient.METHOD_POST,
		body
	)
	if err != OK:
		_emit_error("request_failed_%d" % err)
		return false

	is_requesting = true
	_last_request_payload = payload.duplicate(true)
	_last_request_context = context.duplicate(true)
	return true

func cancel_request() -> void:
	if _http_request == null:
		return
	_http_request.cancel_request()
	is_requesting = false

func _ensure_http_request() -> void:
	if _http_request != null and is_instance_valid(_http_request):
		return

	_http_request = HTTPRequest.new()
	_http_request.name = "AIRequest"
	add_child(_http_request)
	if not _http_request.request_completed.is_connected(_on_request_completed):
		_http_request.request_completed.connect(_on_request_completed)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	is_requesting = false

	if result != HTTPRequest.RESULT_SUCCESS:
		_emit_error("network_error_%d" % result)
		return

	var body_text := body.get_string_from_utf8()
	if response_code < 200 or response_code >= 300:
		var compact_body = body_text.strip_edges()
		var tail = "" if compact_body.is_empty() else (": " + compact_body)
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
		_emit_error("empty_or_invalid_ai_response")
		return

	if chunks.is_empty():
		var one_shot_text := _extract_dialogue_text(final_data)
		if not one_shot_text.is_empty():
			on_ai_stream_chunk_received.emit(one_shot_text)

	if debug_log:
		print("AIManager final: ", final_data)

	on_ai_response_completed.emit(final_data)

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

func _emit_error(msg: String) -> void:
	is_requesting = false
	on_ai_request_error.emit(msg)
