extends Node
class_name XiaokongAIDialogueComponent

signal dialogue_requested(payload: Dictionary)
signal dialogue_chunk_received(chunk: String)
signal dialogue_action_hint_received(action_hint: Dictionary)
signal dialogue_stream_finished(dialogue_text: String)
signal dialogue_completed(report: Dictionary)
signal dialogue_failed(error_text: String)
signal model_probe_completed(response: Dictionary)
signal model_probe_failed(error_text: String)

@export var ai_manager_path: NodePath
@export var state_component_path: NodePath
@export var time_component_path: NodePath
@export var action_router_path: NodePath
@export var perception_component_path: NodePath
@export var affective_director_path: NodePath
@export var companion_director_path: NodePath
@export var auto_apply_ai_response: bool = true
@export var use_local_fallback_on_error: bool = true
@export var fallback_reply_text: String = "信号不稳定，我们先留在避难所，稳住状态再行动。"
@export_range(-20.0, 20.0, 0.5) var fallback_mood_delta: float = 1.0
@export var session_id: String = "default_session"
@export var save_slot_name: String = ""
@export_category("NPC Contract")
@export var npc_display_name: String = "小空"
@export_multiline var npc_role_prompt: String = "末日避难所便利站的少女 NPC，谨慎、温和、可靠，会把玩家称为老师。"
@export var available_body_actions: PackedStringArray = PackedStringArray(["Idle", "Talk", "Follow", "Navigate", "GiveItem", "Rest", "Alert"])
@export var available_expressions: PackedStringArray = PackedStringArray(["neutral", "joy", "fun", "angry", "sorrow", "surprised"])
@export var available_visemes: PackedStringArray = PackedStringArray(["aa", "ih", "ou", "E", "oh"])
@export_category("Debug")
@export var always_log: bool = true
@export var transparent_request_debug: bool = true
@export var external_history_poll_enabled: bool = false
@export_range(0.2, 10.0, 0.1) var external_history_poll_interval_sec: float = 1.0
@export_range(1, 60, 1) var external_history_poll_limit: int = 20
@export var external_poll_session_id: String = ""
@export var bootstrap_skip_existing_external_reply: bool = true
@export var direct_subtitle_fallback_enabled: bool = true
@export var suppress_error_dialogue_output: bool = true
@export var subtitle_target_path: NodePath = NodePath("../WorldSubtitleComponent")
@export var subtitle_speaker_name: String = "Xiaokong"
@export var local_object_intent_fallback_enabled: bool = true

var _ai_manager: AIManager
var _state_component: XiaokongStateComponent
var _time_component: Node
var _action_router: Node
var _subtitle_target: Node
var _perception_component: Node
var _affective_director: Node
var _companion_director: Node

var _request_in_flight: bool = false
var _last_payload: Dictionary = {}
var _history_poll_elapsed: float = 0.0
var _history_poll_in_flight: bool = false
var _last_seen_turn_id: int = 0
var _skip_external_emit_once: bool = false
var _tracking_session_id: String = ""
var _early_action_applied: String = ""
var _stream_first_chunk_received: bool = false
var _pending_action_hint: Dictionary = {}

func _ready() -> void:
	_refresh_refs()
	_bind_ai_signals()
	clear_local_dialogue_tracking(false)
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
	_early_action_applied = ""
	_reset_stream_sync_state()

	_request_in_flight = true
	_log("send_player_text request_start session_id=%s text=%s" % [session_id, text])
	var sent := false
	if _ai_manager.has_method("request_chat_stream"):
		sent = bool(_ai_manager.request_chat_stream(payload, {"type": "xiaokong_dialogue"}))
	else:
		sent = bool(_ai_manager.send_chat_payload(payload, {"type": "xiaokong_dialogue"}))
	if not sent:
		_request_in_flight = false
		_reset_stream_sync_state()
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
			"save_slot": _resolve_save_slot_name(),
			"debug_subtitle_test": true,
			"debug_transparent": transparent_request_debug,
			"request_source": "godot_debug_subtitle_test",
		},
	}

	_last_payload = payload.duplicate(true)
	dialogue_requested.emit(payload.duplicate(true))
	_early_action_applied = ""
	_reset_stream_sync_state()
	_request_in_flight = true
	_log("send_subtitle_test request_start session_id=%s text=%s" % [clean_session_id, text])
	var sent := false
	if _ai_manager.has_method("request_subtitle_test_stream"):
		sent = bool(_ai_manager.request_subtitle_test_stream(payload, {"type": "subtitle_test"}))
	else:
		sent = bool(_ai_manager.send_subtitle_test_stream(text, clean_session_id))
	if not sent:
		_request_in_flight = false
		_reset_stream_sync_state()
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

# 只清理 Godot 侧追踪状态，不删除后端会话。
func clear_local_dialogue_tracking(reset_session_id: bool = false) -> void:
	_history_poll_elapsed = 0.0
	_history_poll_in_flight = false
	_last_seen_turn_id = 0
	_tracking_session_id = ""
	_skip_external_emit_once = bootstrap_skip_existing_external_reply
	if reset_session_id:
		session_id = "default_session"
		external_poll_session_id = ""

func pull_external_history_once(limit: int = -1) -> bool:
	_refresh_refs()
	if _ai_manager == null:
		return false
	if not _ai_manager.has_method("request_session_events_pull") and not _ai_manager.has_method("request_session_history"):
		return false
	if _history_poll_in_flight:
		return false
	var clean_session_id := _resolve_external_poll_session_id()
	_ensure_tracking_session(clean_session_id)
	var safe_limit := external_history_poll_limit if limit <= 0 else limit
	if _ai_manager.has_method("request_session_events_pull"):
		_history_poll_in_flight = bool(_ai_manager.request_session_events_pull(clean_session_id, _last_seen_turn_id, safe_limit))
	else:
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
		day_index = int(_time_component.get("current_day"))
		time_minutes = int(round(float(_time_component.get("current_hour")) * 60.0))

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
		"save_slot": _resolve_save_slot_name(),
		"debug_transparent": transparent_request_debug,
		"request_source": "godot_runtime",
		"npc": _build_npc_contract_context(),
	}
	var perception_snapshot: Dictionary = _build_compact_perception_context()
	if not perception_snapshot.is_empty():
		context_data["perception"] = perception_snapshot

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

func _build_npc_contract_context() -> Dictionary:
	var npc := {
		"name": npc_display_name.strip_edges(),
		"role_prompt": npc_role_prompt.strip_edges(),
		"available_body_actions": _packed_to_clean_array(available_body_actions),
		"available_expressions": _packed_to_clean_array(available_expressions),
		"available_visemes": _packed_to_clean_array(available_visemes),
	}
	return npc

func _packed_to_clean_array(values: PackedStringArray) -> Array:
	var out: Array = []
	for value in values:
		var clean := String(value).strip_edges()
		if not clean.is_empty():
			out.append(clean)
	return out

func _bind_ai_signals() -> void:
	if _ai_manager == null:
		return

	var chunk_cb := Callable(self, "_on_ai_chunk")
	if not _ai_manager.on_ai_stream_chunk_received.is_connected(chunk_cb):
		_ai_manager.on_ai_stream_chunk_received.connect(chunk_cb)

	if _ai_manager.has_signal("on_ai_action_hint_received"):
		var action_hint_cb := Callable(self, "_on_ai_action_hint")
		if not _ai_manager.on_ai_action_hint_received.is_connected(action_hint_cb):
			_ai_manager.on_ai_action_hint_received.connect(action_hint_cb)

	if _ai_manager.has_signal("on_ai_stream_dialogue_finished"):
		var stream_done_cb := Callable(self, "_on_ai_stream_dialogue_finished")
		if not _ai_manager.on_ai_stream_dialogue_finished.is_connected(stream_done_cb):
			_ai_manager.on_ai_stream_dialogue_finished.connect(stream_done_cb)

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

	if _ai_manager.has_signal("on_session_events_pull_received"):
		var events_pull_cb := Callable(self, "_on_session_events_pull_received")
		if not _ai_manager.on_session_events_pull_received.is_connected(events_pull_cb):
			_ai_manager.on_session_events_pull_received.connect(events_pull_cb)

	if _ai_manager.has_signal("on_session_events_pull_error"):
		var events_pull_err_cb := Callable(self, "_on_session_events_pull_error")
		if not _ai_manager.on_session_events_pull_error.is_connected(events_pull_err_cb):
			_ai_manager.on_session_events_pull_error.connect(events_pull_err_cb)

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
		_refresh_refs()
		_bind_ai_signals()
	if _ai_manager == null:
		_log("history_skip ai_manager_missing")
		return
	if not _ai_manager.has_method("request_session_events_pull") and not _ai_manager.has_method("request_session_history"):
		return
	if _history_poll_in_flight:
		return

	_history_poll_elapsed += delta
	if _history_poll_elapsed < external_history_poll_interval_sec:
		return
	_history_poll_elapsed = 0.0

	var clean_session_id := _resolve_external_poll_session_id()
	_ensure_tracking_session(clean_session_id)

	if _ai_manager.has_method("request_session_events_pull"):
		_history_poll_in_flight = bool(_ai_manager.request_session_events_pull(clean_session_id, _last_seen_turn_id, external_history_poll_limit))
	else:
		_history_poll_in_flight = bool(_ai_manager.request_session_history(clean_session_id, external_history_poll_limit))

func _on_ai_chunk(chunk: String) -> void:
	if not _request_in_flight:
		return
	dialogue_chunk_received.emit(chunk)
	if not _stream_first_chunk_received:
		_stream_first_chunk_received = true
		if not _pending_action_hint.is_empty():
			_apply_action_hint(_pending_action_hint)
			_pending_action_hint = {}

func _on_ai_action_hint(action_hint: Dictionary) -> void:
	if action_hint.is_empty():
		return
	if not _request_in_flight:
		_apply_affective_response(action_hint)
		return
	if not _stream_first_chunk_received:
		_pending_action_hint = action_hint.duplicate(true)
		return
	_apply_action_hint(action_hint)

func _on_ai_stream_dialogue_finished(dialogue_text: String) -> void:
	if not _request_in_flight:
		return
	var text := dialogue_text.strip_edges()
	if text.is_empty():
		return
	dialogue_stream_finished.emit(text)

func _on_ai_completed(final_data: Dictionary) -> void:
	if not _request_in_flight:
		return

	_request_in_flight = false
	_reset_stream_sync_state()
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
	if _should_suppress_error_dialogue(dialogue_text, final_data) and use_local_fallback_on_error:
		var error_reason := _extract_error_reason(dialogue_text, final_data)
		var fallback_data = {
			"dialogue": fallback_reply_text,
			"action": "Idle",
			"stat_change": {
				"mood": fallback_mood_delta,
			},
		}
		_log("ai_completed_error_fallback reason=%s" % error_reason)
		_emit_dialogue_report(fallback_reply_text, fallback_data, {
			"request_payload": _last_payload.duplicate(true),
			"fallback": true,
			"fallback_reason": error_reason,
		})
		_early_action_applied = ""
		return
	_emit_dialogue_report(dialogue_text, final_data.duplicate(true), {
		"request_payload": _last_payload.duplicate(true),
		"turn_id": turn_id,
	})
	_early_action_applied = ""

func _on_ai_error(error_text: String) -> void:
	if not _request_in_flight:
		return
	_request_in_flight = false
	_reset_stream_sync_state()
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
		_early_action_applied = ""
		return

	dialogue_failed.emit(error_text)
	_early_action_applied = ""

func _on_session_history_received(session_id_value: String, response: Dictionary) -> void:
	_history_poll_in_flight = false
	_history_poll_elapsed = 0.0
	var expected_session_id := _resolve_external_poll_session_id()
	if session_id_value != expected_session_id:
		_log("history_skip session_mismatch incoming=%s expected=%s" % [session_id_value, expected_session_id])
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
		_log("history_skip no_new_turn last_seen=%d" % _last_seen_turn_id)
		return

	if _skip_external_emit_once:
		_skip_external_emit_once = false
		_last_seen_turn_id = latest_turn_id
		_log("history_bootstrap_skip turn_id=%d" % latest_turn_id)
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
	_log("history_emit turn_id=%d text_len=%d" % [latest_turn_id, dialogue_text.length()])

func _on_session_history_error(_session_id_value: String, _error_msg: String) -> void:
	_history_poll_in_flight = false

func _on_session_events_pull_received(session_id_value: String, response: Dictionary) -> void:
	_history_poll_in_flight = false
	_history_poll_elapsed = 0.0
	var expected_session_id := _resolve_external_poll_session_id()
	if session_id_value != expected_session_id:
		_log("events_pull_skip session_mismatch incoming=%s expected=%s" % [session_id_value, expected_session_id])
		return

	var events_value: Variant = response.get("events", [])
	if events_value is not Array:
		return
	var events := events_value as Array
	if events.is_empty():
		return

	var latest_turn_id := _last_seen_turn_id
	var latest_dialogue := ""
	var latest_payload: Dictionary = {}

	for event_value in events:
		if event_value is not Dictionary:
			continue
		var event := event_value as Dictionary
		var turn_id := int(event.get("turn_id", 0))
		if turn_id <= _last_seen_turn_id:
			continue
		if turn_id < latest_turn_id:
			continue
		latest_turn_id = turn_id
		latest_dialogue = String(event.get("dialogue", "")).strip_edges()
		var payload_value: Variant = event.get("payload", {})
		if payload_value is Dictionary:
			latest_payload = (payload_value as Dictionary).duplicate(true)
		else:
			latest_payload = {}

	if latest_turn_id <= _last_seen_turn_id:
		_log("events_pull_skip no_new_turn last_seen=%d" % _last_seen_turn_id)
		return

	if _skip_external_emit_once:
		_skip_external_emit_once = false
		_last_seen_turn_id = latest_turn_id
		_log("events_pull_bootstrap_skip turn_id=%d" % latest_turn_id)
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
		"events_pull": true,
	})
	_log("events_pull_emit turn_id=%d text_len=%d" % [latest_turn_id, dialogue_text.length()])

func _on_session_events_pull_error(_session_id_value: String, _error_msg: String) -> void:
	_history_poll_in_flight = false

func _on_model_probe_received(response: Dictionary) -> void:
	_log("model_probe_received status=%s ok=%s" % [str(response.get("status", "")), str(response.get("ok", false))])
	model_probe_completed.emit(response.duplicate(true))

func _on_model_probe_error(error_text: String) -> void:
	_log("model_probe_error %s" % error_text)
	model_probe_failed.emit(error_text)

func _emit_dialogue_report(dialogue_text: String, ai_data: Dictionary, extras: Dictionary = {}) -> void:
	if _should_suppress_error_dialogue(dialogue_text, ai_data):
		var reason := _extract_error_reason(dialogue_text, ai_data)
		_log("suppress_error_dialogue reason=%s" % reason)
		dialogue_failed.emit(reason)
		return

	_refresh_refs()
	var route_summary := {}
	if auto_apply_ai_response and _action_router != null and _action_router.has_method("apply_ai_response"):
		var routed_data := ai_data.duplicate(true)
		routed_data = _apply_local_object_intent_fallback(routed_data, extras)
		_notify_companion_external_action(routed_data)
		var final_action := String(routed_data.get("action", "")).strip_edges()
		if (not _early_action_applied.is_empty()) and final_action == _early_action_applied:
			routed_data.erase("action")
		route_summary = _action_router.apply_ai_response(routed_data)
		if not _early_action_applied.is_empty():
			route_summary["early_action_applied"] = _early_action_applied

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

	# Fallback path: if no consumer is connected to dialogue_completed,
	# still render subtitles directly so editor-side external pull can be seen in game.
	if direct_subtitle_fallback_enabled and (not _has_dialogue_completed_listener()):
		_show_subtitle_direct(dialogue_text)

func _get_custom_save_data() -> Dictionary:
	return {
		"session_id": session_id,
		"save_slot_name": save_slot_name,
	}

func _load_custom_save_data(data: Dictionary) -> void:
	if data.has("session_id"):
		session_id = String(data["session_id"]).strip_edges()
	if data.has("save_slot_name"):
		var loaded_slot := String(data["save_slot_name"]).strip_edges()
		# 旧存档会把 AI 上下文固定到 manual_save；迁移后留空，跟随 SaveManager 当前槽位。
		save_slot_name = "" if loaded_slot == "manual_save" else loaded_slot


func _resolve_save_slot_name() -> String:
	var explicit_slot := save_slot_name.strip_edges()
	if not explicit_slot.is_empty():
		return explicit_slot
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("get_current_slot"):
		var current_slot := String(save_manager.call("get_current_slot")).strip_edges()
		if not current_slot.is_empty():
			return current_slot
	return "manual_save"


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

	_time_component = get_node_or_null(time_component_path) as Node
	if _time_component == null:
		_time_component = _find_time_component()

		_action_router = get_node_or_null(action_router_path)
	if _action_router == null:
		_action_router = _find_action_router()

	_affective_director = _resolve_affective_director()
	_companion_director = _resolve_companion_director()

	_subtitle_target = get_node_or_null(subtitle_target_path)
	if _subtitle_target == null:
		_subtitle_target = _find_subtitle_target()

	_perception_component = _resolve_perception_component()

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

func _find_time_component() -> Node:
	var parent_node = get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var node := child as Node
		if node == null:
			continue
		if node.has_method("get_day_time_text") and node.has_method("pass_hours"):
			return node
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

func _find_subtitle_target() -> Node:
	var parent_node := get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var node := child as Node
		if node == null:
			continue
		if node.has_method("show_once"):
			return node
	return null

func _resolve_affective_director() -> Node:
	if affective_director_path != NodePath():
		var by_path := get_node_or_null(affective_director_path)
		if by_path != null:
			return by_path
	var parent_node = get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var node := child as Node
		if node != null and node.has_method("apply_ai_response") and node.has_method("resolve_expression_for_emotion"):
			return node
	return null

func _resolve_companion_director() -> Node:
	if companion_director_path != NodePath():
		var by_path := get_node_or_null(companion_director_path)
		if by_path != null:
			return by_path
	var parent_node = get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var node := child as Node
		if node != null and node.has_method("notify_external_ai_action"):
			return node
	return null

func _build_compact_perception_context() -> Dictionary:
	var perception: Node = _resolve_perception_component()
	if perception == null or not perception.has_method("build_perception_snapshot"):
		return {}
	var snapshot_value: Variant = perception.call("build_perception_snapshot")
	if snapshot_value is not Dictionary:
		return {}
	var snapshot: Dictionary = snapshot_value as Dictionary
	var compact: Dictionary = {}
	var nearby_objects: Array = _compact_perception_entries(snapshot.get("nearby_objects", []), 8)
	if not nearby_objects.is_empty():
		compact["nearby_objects"] = nearby_objects
	var areas: Array = _compact_perception_entries(snapshot.get("areas", []), 4)
	if not areas.is_empty():
		compact["areas"] = areas
	var visible_items: Array = _compact_perception_entries(snapshot.get("visible_items", []), 6)
	if not visible_items.is_empty():
		compact["visible_items"] = visible_items
	return compact

func _compact_perception_entries(entries_value: Variant, limit: int) -> Array:
	var compact_entries: Array = []
	if entries_value is not Array:
		return compact_entries
	var entries: Array = entries_value as Array
	var safe_limit: int = maxi(0, limit)
	for entry_value in entries:
		if compact_entries.size() >= safe_limit:
			break
		if entry_value is not Dictionary:
			continue
		var entry: Dictionary = entry_value as Dictionary
		var compact: Dictionary = {}
		for key in ["id", "name", "type", "description", "tags", "actions", "distance", "marker_roles"]:
			if entry.has(key):
				compact[key] = entry[key]
		if not compact.is_empty():
			compact_entries.append(compact)
	return compact_entries

func _resolve_perception_component() -> Node:
	if perception_component_path == NodePath():
		return _perception_component if _perception_component != null and is_instance_valid(_perception_component) else null
	var by_path: Node = get_node_or_null(perception_component_path)
	if by_path != null:
		_perception_component = by_path
		return by_path
	if _perception_component != null and is_instance_valid(_perception_component):
		return _perception_component
	return null

func _resolve_external_poll_session_id() -> String:
	var sid := external_poll_session_id.strip_edges()
	if sid.is_empty():
		sid = session_id.strip_edges()
	if sid.is_empty():
		sid = "default_session"
	return sid

func _ensure_tracking_session(clean_session_id: String) -> void:
	if clean_session_id == _tracking_session_id:
		return
	_tracking_session_id = clean_session_id
	_last_seen_turn_id = 0
	_skip_external_emit_once = bootstrap_skip_existing_external_reply
	_log("history_tracking_session switched session=%s bootstrap_skip=%s" % [clean_session_id, str(_skip_external_emit_once)])

func _has_dialogue_completed_listener() -> bool:
	var connections := dialogue_completed.get_connections()
	return connections.size() > 0

func _show_subtitle_direct(dialogue_text: String) -> void:
	var text := dialogue_text.strip_edges()
	if text.is_empty():
		return
	if _subtitle_target == null or not is_instance_valid(_subtitle_target):
		_subtitle_target = get_node_or_null(subtitle_target_path)
	if _subtitle_target == null or not is_instance_valid(_subtitle_target):
		_subtitle_target = _find_subtitle_target()
	if _subtitle_target == null:
		return
	if _subtitle_target.has_method("show_once"):
		_subtitle_target.call("show_once", text, subtitle_speaker_name.strip_edges())

func _should_suppress_error_dialogue(dialogue_text: String, ai_data: Dictionary) -> bool:
	if not suppress_error_dialogue_output:
		return false
	if ai_data.has("ok") and not bool(ai_data.get("ok", true)):
		return true
	var emotion := String(ai_data.get("emotion", "")).strip_edges().to_lower()
	if emotion == "error" or emotion == "failed":
		return true
	var explicit_error := String(ai_data.get("error", ai_data.get("model_error", ""))).strip_edges()
	if not explicit_error.is_empty():
		return true
	var tags_value: Variant = ai_data.get("memory_tags", [])
	if tags_value is Array:
		for tag_value in (tags_value as Array):
			var tag := String(tag_value).strip_edges().to_lower()
			if tag == "model_error" or tag.find("error") >= 0:
				return true
	var text := dialogue_text.strip_edges()
	if text.begins_with("[error]"):
		return true
	if text.begins_with("模型调用失败"):
		return true
	if text.begins_with("请求失败"):
		return true
	if text.begins_with("调用失败"):
		return true
	return false

func _extract_error_reason(dialogue_text: String, ai_data: Dictionary) -> String:
	var explicit_error := String(ai_data.get("error", ai_data.get("model_error", ""))).strip_edges()
	if not explicit_error.is_empty():
		return explicit_error
	var text := dialogue_text.strip_edges()
	if not text.is_empty():
		return text
	return "dialogue_error"

func _reset_stream_sync_state() -> void:
	_stream_first_chunk_received = false
	_pending_action_hint = {}

func _apply_local_object_intent_fallback(ai_data: Dictionary, extras: Dictionary = {}) -> Dictionary:
	if not local_object_intent_fallback_enabled:
		return ai_data
	if _ai_data_has_navigation_command(ai_data):
		return ai_data
	var request_payload: Dictionary = {}
	var request_value: Variant = extras.get("request_payload", _last_payload)
	if request_value is Dictionary:
		request_payload = request_value as Dictionary
	var player_text := String(request_payload.get("player_text", "")).strip_edges()
	if player_text.is_empty():
		return ai_data
	var target_ref := _infer_target_object_from_player_text(player_text)
	if target_ref.is_empty():
		return ai_data
	ai_data["command"] = "go_to_object"
	ai_data["target_object"] = target_ref
	ai_data["marker_role"] = _infer_marker_role_from_player_text(player_text)
	ai_data["source"] = "player_text_intent_fallback"
	var command_payload: Dictionary = {}
	var existing_payload: Variant = ai_data.get("command_payload", {})
	if existing_payload is Dictionary:
		command_payload = (existing_payload as Dictionary).duplicate(true)
	command_payload["target_object"] = target_ref
	command_payload["marker_role"] = ai_data["marker_role"]
	ai_data["command_payload"] = command_payload
	_log("local_object_intent_fallback text=%s target=%s role=%s" % [player_text, target_ref, String(ai_data["marker_role"])])
	return ai_data

func _ai_data_has_navigation_command(ai_data: Dictionary) -> bool:
	if not String(ai_data.get("command", "")).strip_edges().is_empty():
		return true
	for nested_key in ["command_payload", "navigation", "intent_payload", "action_hint"]:
		var nested_value: Variant = ai_data.get(nested_key, null)
		if nested_value is Dictionary:
			var nested := nested_value as Dictionary
			if not String(nested.get("command", nested.get("intent", ""))).strip_edges().is_empty():
				return true
	return false

func _infer_target_object_from_player_text(player_text: String) -> String:
	var text := player_text.strip_edges().to_lower()
	if text.is_empty():
		return ""
	var has_inspect_verb := false
	for verb in ["看看", "看下", "看一下", "查看", "检查", "去看", "过去", "去", "打开", "瞧瞧", "瞅瞅"]:
		if text.find(verb) >= 0:
			has_inspect_verb = true
			break
	if not has_inspect_verb:
		return ""
	var aliases := [
		{"target": "food_cabinet", "words": ["食品柜", "食物柜", "食物", "食品", "补给柜", "补给", "吃的", "罐头", "水柜"]},
		{"target": "medical_cabinet", "words": ["医疗柜", "医药柜", "药柜", "药品", "医疗", "急救"]},
		{"target": "equipment_cabinet", "words": ["武器柜", "装备柜", "武器", "装备"]},
		{"target": "utility_storage_box", "words": ["杂物箱", "物资箱", "工具箱", "箱子", "储物箱", "柜子", "柜"]},
		{"target": "table_main", "words": ["桌子", "餐桌", "桌"]},
		{"target": "bed", "words": ["床", "床铺"]},
		{"target": "chair", "words": ["椅子", "座位", "坐的"]},
	]
	for alias in aliases:
		for word in alias.get("words", []):
			if text.find(String(word)) >= 0:
				return String(alias.get("target", ""))
	return ""

func _infer_marker_role_from_player_text(player_text: String) -> String:
	var text := player_text.strip_edges().to_lower()
	if text.find("打开") >= 0:
		return "open"
	if text.find("看") >= 0 or text.find("查") >= 0 or text.find("瞧") >= 0 or text.find("瞅") >= 0:
		return "approach"
	return "approach"

func _apply_action_hint(action_hint: Dictionary) -> void:
	if action_hint.is_empty():
		return
	dialogue_action_hint_received.emit(action_hint.duplicate(true))
	_apply_affective_response(action_hint)

	var action_name := String(action_hint.get("action", "")).strip_edges()

	if auto_apply_ai_response and _action_router != null and _action_router.has_method("apply_ai_response"):
		var route_summary: Dictionary = _action_router.call("apply_ai_response", action_hint.duplicate(true))
		if not action_name.is_empty() and bool(route_summary.get("action_applied", false)):
			_early_action_applied = action_name
			_log("early_action_applied action=%s" % action_name)

func _apply_affective_response(ai_data: Dictionary) -> void:
	if _affective_director == null or not is_instance_valid(_affective_director):
		_affective_director = _resolve_affective_director()
	if _affective_director == null or not _affective_director.has_method("apply_ai_response"):
		return
	_affective_director.call("apply_ai_response", ai_data.duplicate(true))

func _notify_companion_external_action(ai_data: Dictionary) -> void:
	if _companion_director == null or not is_instance_valid(_companion_director):
		_companion_director = _resolve_companion_director()
	if _companion_director == null or not _companion_director.has_method("notify_external_ai_action"):
		return
	var has_command := not String(ai_data.get("command", "")).strip_edges().is_empty()
	var command_payload: Variant = ai_data.get("command_payload", {})
	if command_payload is Dictionary and not (command_payload as Dictionary).is_empty():
		has_command = true
	var action_text := String(ai_data.get("action", "")).strip_edges()
	var has_non_idle_action := not action_text.is_empty() and action_text != "Idle"
	if has_command or has_non_idle_action:
		_companion_director.call("notify_external_ai_action", ai_data.duplicate(true))

func _log(message: String) -> void:
	if always_log:
		print("[XiaokongAIDialogue] %s" % message)
