extends Node
class_name XiaokongAIDialogueComponent

signal dialogue_requested(payload: Dictionary)
signal dialogue_chunk_received(chunk: String)
signal dialogue_completed(report: Dictionary)
signal dialogue_failed(error_text: String)

@export var ai_manager_path: NodePath
@export var state_component_path: NodePath
@export var time_component_path: NodePath
@export var action_router_path: NodePath
@export var auto_apply_ai_response: bool = true
@export var use_local_fallback_on_error: bool = true
@export var fallback_reply_text: String = "Signal lost. Let's stay inside for now."
@export_range(-20.0, 20.0, 0.5) var fallback_mood_delta: float = 1.0
@export var session_id: String = "default_session"
@export var save_slot_name: String = "manual_save"

var _ai_manager: AIManager
var _state_component: XiaokongStateComponent
var _time_component: XiaokongGameTimeComponent
var _action_router: XiaokongAIActionRouterComponent

var _request_in_flight: bool = false
var _last_payload: Dictionary = {}

func _ready() -> void:
	_refresh_refs()
	_bind_ai_signals()

func send_player_text(player_text: String, given_item: String = "") -> Dictionary:
	_refresh_refs()
	_bind_ai_signals()

	var text := player_text.strip_edges()
	if text.is_empty():
		return {"ok": false, "error": "empty_text"}
	if _ai_manager == null:
		return {"ok": false, "error": "ai_manager_not_found"}
	if _request_in_flight or _ai_manager.is_requesting:
		return {"ok": false, "error": "ai_busy"}

	var payload := _build_dialogue_payload(text, given_item)
	_last_payload = payload.duplicate(true)
	dialogue_requested.emit(payload.duplicate(true))

	_request_in_flight = true
	var sent := _ai_manager.send_chat_payload(payload, {"type": "xiaokong_dialogue"})
	if not sent:
		_request_in_flight = false
		return {"ok": false, "error": "request_send_failed"}

	return {
		"ok": true,
		"payload": payload,
	}

func send_subtitle_test(test_text: String = "Subtitle debug test") -> Dictionary:
	_refresh_refs()
	_bind_ai_signals()

	var text := test_text.strip_edges()
	if text.is_empty():
		text = "Subtitle debug test"
	if _ai_manager == null:
		return {"ok": false, "error": "ai_manager_not_found"}
	if _request_in_flight or _ai_manager.is_requesting:
		return {"ok": false, "error": "ai_busy"}

	var clean_session_id := session_id.strip_edges()
	if clean_session_id.is_empty():
		clean_session_id = "default_session"
	session_id = clean_session_id

	var payload := {
		"day": 1,
		"time": 540,
		"time_min": 540,
		"session_id": clean_session_id,
		"npc_stats": {
			"hunger": 50,
			"thirst": 50,
			"mood": 50,
			"favor": 20,
		},
		"player_text": text,
		"given_item": "",
		"context": {
			"session_id": clean_session_id,
			"save_slot": save_slot_name.strip_edges(),
			"debug_subtitle_test": true,
		},
	}

	_last_payload = payload.duplicate(true)
	dialogue_requested.emit(payload.duplicate(true))
	_request_in_flight = true
	var sent := _ai_manager.send_subtitle_test_stream(text, clean_session_id)
	if not sent:
		_request_in_flight = false
		return {"ok": false, "error": "request_send_failed"}

	return {
		"ok": true,
		"payload": payload,
		"debug": true,
	}

func _build_dialogue_payload(player_text: String, given_item: String) -> Dictionary:
	var day_index := 1
	var time_minutes := 0
	if _time_component != null:
		day_index = _time_component.current_day
		time_minutes = int(round(_time_component.current_hour * 60.0))

	var stats := {
		"hunger": 50,
		"thirst": 50,
		"mood": 50,
		"favor": 20,
	}
	if _state_component != null:
		stats = _state_component.build_ai_stats()

	var clean_session_id := session_id.strip_edges()
	if clean_session_id.is_empty():
		clean_session_id = "default_session"
	session_id = clean_session_id

	return {
		"day": day_index,
		"time": time_minutes,
		"time_min": time_minutes,
		"session_id": clean_session_id,
		"npc_stats": stats.duplicate(true),
		"ai_hunger": int(stats.get("hunger", 50)),
		"ai_thirst": int(stats.get("thirst", 50)),
		"ai_mood": int(stats.get("mood", 50)),
		"ai_favor": int(stats.get("favor", 20)),
		"player_text": player_text,
		"given_item": given_item.strip_edges(),
		"context": {
			"session_id": clean_session_id,
			"save_slot": save_slot_name.strip_edges(),
		},
	}

func _bind_ai_signals() -> void:
	if _ai_manager == null:
		return

	var chunk_cb := Callable(self, "_on_ai_chunk")
	if not _ai_manager.on_ai_stream_chunk_received.is_connected(chunk_cb):
		_ai_manager.on_ai_stream_chunk_received.connect(chunk_cb)

	var done_cb := Callable(self, "_on_ai_completed")
	if not _ai_manager.on_ai_response_completed.is_connected(done_cb):
		_ai_manager.on_ai_response_completed.connect(done_cb)

	var err_cb := Callable(self, "_on_ai_error")
	if not _ai_manager.on_ai_request_error.is_connected(err_cb):
		_ai_manager.on_ai_request_error.connect(err_cb)

func _on_ai_chunk(chunk: String) -> void:
	if not _request_in_flight:
		return
	dialogue_chunk_received.emit(chunk)

func _on_ai_completed(final_data: Dictionary) -> void:
	if not _request_in_flight:
		return

	_request_in_flight = false
	var backend_session_id := String(final_data.get("session_id", "")).strip_edges()
	if not backend_session_id.is_empty():
		session_id = backend_session_id

	var route_summary := {}
	if auto_apply_ai_response and _action_router != null:
		route_summary = _action_router.apply_ai_response(final_data)

	var report = {
		"ok": true,
		"dialogue": _extract_dialogue(final_data),
		"ai_data": final_data.duplicate(true),
		"route_summary": route_summary,
		"request_payload": _last_payload.duplicate(true),
	}
	dialogue_completed.emit(report)

func _on_ai_error(error_text: String) -> void:
	if not _request_in_flight:
		return
	_request_in_flight = false

	if use_local_fallback_on_error:
		var fallback_data = {
			"dialogue": fallback_reply_text,
			"action": "Idle",
			"stat_change": {
				"mood": fallback_mood_delta,
			},
		}
		var route_summary := {}
		if auto_apply_ai_response and _action_router != null:
			route_summary = _action_router.apply_ai_response(fallback_data)
		dialogue_completed.emit({
			"ok": true,
			"dialogue": fallback_reply_text,
			"ai_data": fallback_data,
			"route_summary": route_summary,
			"request_payload": _last_payload.duplicate(true),
			"fallback": true,
			"fallback_reason": error_text,
		})
		return

	dialogue_failed.emit(error_text)

func _get_custom_save_data() -> Dictionary:
	return {
		"session_id": session_id,
		"save_slot_name": save_slot_name,
	}

func _load_custom_save_data(data: Dictionary) -> void:
	if data.has("session_id"):
		session_id = String(data["session_id"]).strip_edges()
	if data.has("save_slot_name"):
		save_slot_name = String(data["save_slot_name"]).strip_edges()

func _extract_dialogue(data: Dictionary) -> String:
	for key in ["dialogue", "reply", "text", "message", "summary"]:
		var value = String(data.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return ""

func _refresh_refs() -> void:
	_ai_manager = get_node_or_null(ai_manager_path) as AIManager
	if _ai_manager == null:
		_ai_manager = _find_ai_manager()

	_state_component = get_node_or_null(state_component_path) as XiaokongStateComponent
	if _state_component == null:
		_state_component = _find_state_component()

	_time_component = get_node_or_null(time_component_path) as XiaokongGameTimeComponent
	if _time_component == null:
		_time_component = _find_time_component()

	_action_router = get_node_or_null(action_router_path) as XiaokongAIActionRouterComponent
	if _action_router == null:
		_action_router = _find_action_router()

func _find_ai_manager() -> AIManager:
	var parent_node = get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var ai_manager = child as AIManager
		if ai_manager != null:
			return ai_manager
	return null

func _find_state_component() -> XiaokongStateComponent:
	var parent_node = get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var state_component = child as XiaokongStateComponent
		if state_component != null:
			return state_component
	return null

func _find_time_component() -> XiaokongGameTimeComponent:
	var parent_node = get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var time_component = child as XiaokongGameTimeComponent
		if time_component != null:
			return time_component
	return null

func _find_action_router() -> XiaokongAIActionRouterComponent:
	var parent_node = get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var router = child as XiaokongAIActionRouterComponent
		if router != null:
			return router
	return null
