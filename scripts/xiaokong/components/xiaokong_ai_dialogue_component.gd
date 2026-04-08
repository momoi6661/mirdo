extends Node
class_name XiaokongAIDialogueComponent

signal dialogue_requested(payload: Dictionary)
signal dialogue_chunk_received(chunk: String)
signal dialogue_completed(report: Dictionary)
signal dialogue_failed(error_text: String)
signal model_probe_completed(response: Dictionary)
signal model_probe_failed(error_text: String)

@export var ai_manager_path: NodePath
@export var state_component_path: NodePath
@export var time_component_path: NodePath
@export var action_router_path: NodePath
@export var auto_apply_ai_response: bool = true
@export var use_local_fallback_on_error: bool = true
@export var fallback_reply_text: String = "信号不稳定，我们先留在避难所，稳住状态再行动。"
@export_range(-20.0, 20.0, 0.5) var fallback_mood_delta: float = 1.0
@export var session_id: String = "default_session"
@export var save_slot_name: String = "manual_save"
@export var always_log: bool = true
@export var transparent_request_debug: bool = true
@export var external_history_poll_enabled: bool = false
@export_range(0.2, 10.0, 0.1) var external_history_poll_interval_sec: float = 1.0
@export_range(1, 60, 1) var external_history_poll_limit: int = 20

var _ai_manager: AIManager
var _state_component: XiaokongStateComponent
var _time_component: XiaokongGameTimeComponent
var _action_router: XiaokongAIActionRouterComponent

var _request_in_flight: bool = false
var _last_payload: Dictionary = {}
var _history_poll_elapsed: float = 0.0
var _history_poll_in_flight: bool = false
var _last_seen_turn_id: int = 0

func _ready() -> void:
	_refresh_refs()
	_bind_ai_signals()
	set_process(external_history_poll_enabled)

# 极简调用：只要一行，就能发起对话。
# 返回 true 表示请求已成功发出（不是模型一定成功）。
func chat(text: String, given_item: String = "") -> bool:
	var result := send_player_text(text, given_item)
	return bool(result.get("ok", false))

func send_player_text(player_text: String, given_item: String = "") -> Dictionary:
	_refresh_refs()
	_bind_ai_signals()

	var text := player_text.strip_edges()
	if text.is_empty():
		_log("send_player_text rejected: empty_text")
		return {"ok": false, "error": "empty_text"}
	if _ai_manager == null:
		_log("send_player_text rejected: ai_manager_not_found")
		return {"ok": false, "error": "ai_manager_not_found"}
	if _request_in_flight or _ai_manager.is_requesting:
		_log("send_player_text rejected: ai_busy")
		return {"ok": false, "error": "ai_busy"}

	var payload := _build_dialogue_payload(text, given_item)
	_last_payload = payload.duplicate(true)
	dialogue_requested.emit(payload.duplicate(true))

	_request_in_flight = true
	_log("send_player_text request_start session_id=%s text=%s" % [session_id, text])
	var sent := false
	if _ai_manager.has_method("request_chat_stream"):
		sent = bool(_ai_manager.request_chat_stream(payload, {"type": "xiaokong_dialogue"}))
	else:
		sent = bool(_ai_manager.send_chat_payload(payload, {"type": "xiaokong_dialogue"}))
	if not sent:
		_request_in_flight = false
		_log("send_player_text request_send_failed")
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
		_log("send_subtitle_test rejected: ai_manager_not_found")
		return {"ok": false, "error": "ai_manager_not_found"}
	if _request_in_flight or _ai_manager.is_requesting:
		_log("send_subtitle_test rejected: ai_busy")
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
			"debug_transparent": transparent_request_debug,
			"request_source": "godot_debug_subtitle_test",
		},
	}

	_last_payload = payload.duplicate(true)
	dialogue_requested.emit(payload.duplicate(true))
	_request_in_flight = true
	_log("send_subtitle_test request_start session_id=%s text=%s" % [clean_session_id, text])
	var sent := false
	if _ai_manager.has_method("request_subtitle_test_stream"):
		sent = bool(_ai_manager.request_subtitle_test_stream(payload, {"type": "subtitle_test"}))
	else:
		sent = bool(_ai_manager.send_subtitle_test_stream(text, clean_session_id))
	if not sent:
		_request_in_flight = false
		_log("send_subtitle_test request_send_failed")
		return {"ok": false, "error": "request_send_failed"}

	return {
		"ok": true,
		"payload": payload,
		"debug": true,
	}

func set_external_history_poll_enabled(enabled: bool) -> void:
	external_history_poll_enabled = enabled
	if not external_history_poll_enabled:
		_history_poll_in_flight = false
		_history_poll_elapsed = 0.0
	set_process(external_history_poll_enabled)
	_log("external_history_poll_enabled=%s" % str(external_history_poll_enabled))

func pull_external_history_once(limit: int = -1) -> bool:
	_refresh_refs()
	if _ai_manager == null:
		return false
	if not _ai_manager.has_method("request_session_history"):
		return false
	if _history_poll_in_flight:
		return false
	var clean_session_id := session_id.strip_edges()
	if clean_session_id.is_empty():
		clean_session_id = "default_session"
		session_id = clean_session_id
	var safe_limit := external_history_poll_limit if limit <= 0 else limit
	_history_poll_in_flight = bool(_ai_manager.request_session_history(clean_session_id, safe_limit))
	return _history_poll_in_flight

func probe_model_once() -> bool:
	_refresh_refs()
	_bind_ai_signals()
	if _ai_manager == null:
		return false
	if not _ai_manager.has_method("request_model_probe"):
		return false
	return bool(_ai_manager.request_model_probe())

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

	var context_data := {
		"session_id": clean_session_id,
		"save_slot": save_slot_name.strip_edges(),
		"debug_transparent": transparent_request_debug,
		"request_source": "godot_runtime",
	}

	if _ai_manager != null and _ai_manager.has_method("build_chat_request"):
		return _ai_manager.build_chat_request(
			player_text,
			clean_session_id,
			day_index,
			time_minutes,
			stats.duplicate(true),
			given_item.strip_edges(),
			context_data,
			-1
		)

	return {
		"day": day_index,
		"time": time_minutes,
		"time_min": time_minutes,
		"session_id": clean_session_id,
		"npc_stats": stats.duplicate(true),
		"player_text": player_text,
		"given_item": given_item.strip_edges(),
		"context": context_data,
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

	if _ai_manager.has_signal("on_session_history_received"):
		var hist_cb := Callable(self, "_on_session_history_received")
		if not _ai_manager.on_session_history_received.is_connected(hist_cb):
			_ai_manager.on_session_history_received.connect(hist_cb)

	if _ai_manager.has_signal("on_session_history_error"):
		var hist_err_cb := Callable(self, "_on_session_history_error")
		if not _ai_manager.on_session_history_error.is_connected(hist_err_cb):
			_ai_manager.on_session_history_error.connect(hist_err_cb)

	if _ai_manager.has_signal("on_model_probe_received"):
		var probe_cb := Callable(self, "_on_model_probe_received")
		if not _ai_manager.on_model_probe_received.is_connected(probe_cb):
			_ai_manager.on_model_probe_received.connect(probe_cb)

	if _ai_manager.has_signal("on_model_probe_error"):
		var probe_err_cb := Callable(self, "_on_model_probe_error")
		if not _ai_manager.on_model_probe_error.is_connected(probe_err_cb):
			_ai_manager.on_model_probe_error.connect(probe_err_cb)

func _process(delta: float) -> void:
	if not external_history_poll_enabled:
		return
	if _request_in_flight:
		return
	if _ai_manager == null:
		return
	if not _ai_manager.has_method("request_session_history"):
		return
	if _history_poll_in_flight:
		return

	_history_poll_elapsed += delta
	if _history_poll_elapsed < external_history_poll_interval_sec:
		return
	_history_poll_elapsed = 0.0

	var clean_session_id := session_id.strip_edges()
	if clean_session_id.is_empty():
		clean_session_id = "default_session"
		session_id = clean_session_id

	_history_poll_in_flight = bool(_ai_manager.request_session_history(clean_session_id, external_history_poll_limit))

func _on_ai_chunk(chunk: String) -> void:
	if not _request_in_flight:
		return
	dialogue_chunk_received.emit(chunk)

func _on_ai_completed(final_data: Dictionary) -> void:
	if not _request_in_flight:
		return

	_request_in_flight = false
	_log("ai_completed keys=%s" % str(final_data.keys()))
	var turn_id := int(final_data.get("turn_id", 0))
	if turn_id > _last_seen_turn_id:
		_last_seen_turn_id = turn_id
	var backend_session_id := String(final_data.get("session_id", "")).strip_edges()
	if not backend_session_id.is_empty():
		session_id = backend_session_id

	var dialogue_text := _extract_dialogue(final_data)
	if dialogue_text.is_empty():
		dialogue_text = "……"
	_emit_dialogue_report(dialogue_text, final_data.duplicate(true), {
		"request_payload": _last_payload.duplicate(true),
		"turn_id": turn_id,
	})

func _on_ai_error(error_text: String) -> void:
	if not _request_in_flight:
		return
	_request_in_flight = false
	_log("ai_error %s" % error_text)

	if use_local_fallback_on_error:
		var fallback_data = {
			"dialogue": fallback_reply_text,
			"action": "Idle",
			"stat_change": {
				"mood": fallback_mood_delta,
			},
		}
		_emit_dialogue_report(fallback_reply_text, fallback_data, {
			"request_payload": _last_payload.duplicate(true),
			"fallback": true,
			"fallback_reason": error_text,
		})
		return

	dialogue_failed.emit(error_text)

func _on_session_history_received(session_id_value: String, response: Dictionary) -> void:
	_history_poll_in_flight = false
	_history_poll_elapsed = 0.0
	if session_id_value != session_id:
		return

	var turns_value: Variant = response.get("turns", [])
	if turns_value is not Array:
		return
	var turns := turns_value as Array

	var latest_turn_id := _last_seen_turn_id
	var latest_dialogue := ""
	var latest_payload: Dictionary = {}

	for turn_value in turns:
		if turn_value is not Dictionary:
			continue
		var turn := turn_value as Dictionary
		var role := String(turn.get("role", "")).strip_edges()
		if role != "assistant":
			continue
		var turn_id := int(turn.get("id", 0))
		if turn_id <= _last_seen_turn_id:
			continue
		if turn_id < latest_turn_id:
			continue
		latest_turn_id = turn_id
		latest_dialogue = String(turn.get("content", "")).strip_edges()
		var payload_value: Variant = turn.get("payload", {})
		if payload_value is Dictionary:
			latest_payload = (payload_value as Dictionary).duplicate(true)
		else:
			latest_payload = {}

	if latest_turn_id <= _last_seen_turn_id:
		return

	_last_seen_turn_id = latest_turn_id
	var dialogue_text := _extract_dialogue(latest_payload)
	if dialogue_text.is_empty():
		dialogue_text = latest_dialogue
	if dialogue_text.is_empty():
		dialogue_text = "……"
	if latest_payload.is_empty():
		latest_payload = {"dialogue": dialogue_text}
	if not latest_payload.has("turn_id"):
		latest_payload["turn_id"] = latest_turn_id

	_emit_dialogue_report(dialogue_text, latest_payload, {
		"external_pull": true,
		"turn_id": latest_turn_id,
	})

func _on_session_history_error(_session_id_value: String, _error_msg: String) -> void:
	_history_poll_in_flight = false

func _on_model_probe_received(response: Dictionary) -> void:
	_log("model_probe_received status=%s ok=%s" % [str(response.get("status", "")), str(response.get("ok", false))])
	model_probe_completed.emit(response.duplicate(true))

func _on_model_probe_error(error_text: String) -> void:
	_log("model_probe_error %s" % error_text)
	model_probe_failed.emit(error_text)

func _emit_dialogue_report(dialogue_text: String, ai_data: Dictionary, extras: Dictionary = {}) -> void:
	var route_summary := {}
	if auto_apply_ai_response and _action_router != null:
		route_summary = _action_router.apply_ai_response(ai_data)

	var report: Dictionary = {
		"ok": true,
		"dialogue": dialogue_text,
		"ai_data": ai_data.duplicate(true),
		"route_summary": route_summary,
		"request_payload": _last_payload.duplicate(true),
	}
	for key in extras.keys():
		report[key] = extras[key]
	dialogue_completed.emit(report)

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

func _log(message: String) -> void:
	if always_log:
		print("[XiaokongAIDialogue] %s" % message)
