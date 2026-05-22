extends Node
class_name CharacterAIDialogueComponent

signal dialogue_requested(payload: Dictionary)
signal dialogue_chunk_received(chunk: String)
signal dialogue_stream_finished(dialogue_text: String)
signal dialogue_completed(report: Dictionary)
signal dialogue_failed(error_text: String)

@export var ai_manager_path: NodePath
@export var perception_component_path: NodePath
@export var mind_state_path: NodePath
@export var state_component_path: NodePath
@export var player_awareness_path: NodePath
@export var autonomous_life_path: NodePath
@export var blackboard_path: NodePath
@export var action_semantics_path: NodePath
@export var action_executor_path: NodePath
@export var subtitle_target_path: NodePath
@export var face_component_path: NodePath
@export var ai_nav_point_group: StringName = &"ai_nav_point"
@export_range(0, 256, 1) var max_nav_points_in_prompt: int = 128

@export_category("NPC Contract")
@export var npc_display_name: String = "Mirdo"
@export_multiline var npc_role_prompt: String = "可爱的避难所少女 NPC，称呼玩家为老师，性格活泼、好奇、温柔。"
@export_multiline var npc_personality_knowledge: String = "Mirdo 是一个可爱的 VRChat 风格原创少女角色。她活泼、好奇、亲近玩家，会把玩家称作老师；她在避难所里会主动观察食物柜、医疗柜、工具箱、装备柜、工作台和床铺，关心食物、水、药品和工具是否够用。她说话短、自然、带一点可爱的自言自语，但不会刷屏。"
@export_multiline var response_contract_prompt: String = "后端回复应优先返回 JSON：dialogue 为 Mirdo 要说的话；expression 从 neutral/joy/fun/angry/sorrow/surprised/disappointed 中选择；action 从 available_body_actions 中选择；visemes 使用 aa、ih、ou、E、oh 五种，用顿号或逗号分隔。与老师互动时优先 tiny_wave/small_wave/small_nod/cute_explain/tilt_head_cute；点头用 react_nod，挥手用 react_wave/tiny_wave；需要回头或转向时可用 look_back/turn_left/turn_right/turn_180；坐着时优先 seated_idle/seated_sleepy，除非明确起身不要给站姿动作。"
@export var available_body_actions: PackedStringArray = PackedStringArray([
	"idle_normal", "idle_relaxed", "idle_sleepy", "idle_alert", "idle_fidget", "listen", "happy_bounce",
	"walk", "run", "seated_idle", "seated_sleepy",
	"work_inspect_cabinet", "work_check_shelf", "work_check_lower", "work_count_supplies",
	"work_reach", "work_take_item", "work_place_item", "work_drink", "work_explain",
	"react_nod", "react_wave", "tiny_wave", "rub_eye", "sleepy_yawn", "cute_startle",
	"curious_peek", "tilt_head_cute", "look_back", "look_around", "turn_left", "turn_right", "turn_180",
])
@export var available_expressions: PackedStringArray = PackedStringArray(["neutral", "joy", "fun", "angry", "sorrow", "surprised", "disappointed"])
@export var available_visemes: PackedStringArray = PackedStringArray(["aa", "ih", "ou", "E", "oh"])

@export_category("Request")
@export var session_id: String = "mirdo_session"
@export var save_slot_name: String = ""
@export var use_save_scoped_session_id: bool = true
@export var use_streaming_request: bool = false
@export var auto_apply_ai_response: bool = true
@export var direct_subtitle_enabled: bool = true
@export var compact_backend_context: bool = true
@export var fallback_reply_text: String = "我有点没听清，可以再说一次吗？"
@export var suppress_error_dialogue_output: bool = true
@export var local_fallback_variety_enabled: bool = true
@export var speak_local_fallback_when_ai_busy: bool = false
@export var aggregate_player_dialogue_enabled: bool = true
@export_range(0.0, 1.5, 0.05) var player_dialogue_aggregate_delay_sec: float = 0.45
@export_range(0.0, 5.0, 0.1) var player_dialogue_aggregate_max_wait_sec: float = 2.5
@export var queue_player_dialogue_while_busy: bool = true
@export var queue_autonomous_dialogue_while_busy: bool = false
@export var merge_queued_player_dialogue: bool = true
@export_range(120, 1200, 10) var max_merged_player_dialogue_chars: int = 420
@export_range(0, 8, 1) var max_queued_dialogue_requests: int = 4
@export_range(0.05, 2.0, 0.05) var queued_dialogue_retry_delay_sec: float = 0.25
@export var always_log: bool = true

var _ai_manager: AIManager
var _perception_component: Node
var _mind_state: Node
var _state_component: Node
var _player_awareness: Node
var _autonomous_life: Node
var _blackboard: Node
var _action_semantics: Node
var _action_executor: Node
var _subtitle_target: Node
var _face_component: Node
var _request_in_flight: bool = false
var _last_payload: Dictionary = {}
var _stream_text: String = ""
var _last_ai_error_text: String = ""
var _ai_error_handled_during_send: bool = false
var _sending_request: bool = false
var _queued_dialogue_requests: Array[Dictionary] = []
var _queue_retry_scheduled: bool = false
var _pending_player_dialogue_parts: Array[String] = []
var _pending_player_given_item: String = ""
var _pending_player_source_decision: Dictionary = {}
var _pending_player_flush_token: int = 0
var _pending_player_first_input_ticks_msec: int = 0
var _player_input_draft_text: String = ""

func _ready() -> void:
	_refresh_refs()
	_bind_ai_signals()

func chat(text: String, given_item: String = "") -> bool:
	var result := send_player_text(text, given_item)
	return bool(result.get("ok", false))

func send_player_text(player_text: String, given_item: String = "") -> Dictionary:
	return _send_dialogue_text(player_text, given_item, "player", {})

func send_autonomous_text(prompt_text: String, autonomous_decision: Dictionary = {}) -> Dictionary:
	return _send_dialogue_text(prompt_text, "", "autonomous", autonomous_decision)

func _send_dialogue_text(
	player_text: String,
	given_item: String = "",
	request_source: String = "player",
	source_decision: Dictionary = {},
	bypass_player_aggregation: bool = false
) -> Dictionary:
	_refresh_refs()
	_bind_ai_signals()
	var text := player_text.strip_edges()
	if text.is_empty():
		return {"ok": false, "error": "empty_text"}
	if _should_aggregate_player_dialogue(request_source, bypass_player_aggregation):
		return _aggregate_player_dialogue_text(text, given_item, source_decision)
	if _ai_manager == null:
		_emit_local_fallback("ai_manager_missing")
		return {"ok": false, "error": "ai_manager_missing"}
	if _request_in_flight:
		if _can_queue_dialogue_request(request_source):
			return _enqueue_dialogue_text(text, given_item, request_source, source_decision)
		return {"ok": false, "error": "request_in_flight"}

	var payload := _build_chat_payload(text, given_item, request_source, source_decision)
	_last_payload = payload.duplicate(true)
	_stream_text = ""
	_last_ai_error_text = ""
	_ai_error_handled_during_send = false
	_request_in_flight = true
	dialogue_requested.emit(payload.duplicate(true))

	var sent := false
	_sending_request = true
	if use_streaming_request and _ai_manager.has_method("request_chat_stream"):
		sent = bool(_ai_manager.call("request_chat_stream", payload, {"type": "character_dialogue", "npc": npc_display_name}))
	elif _ai_manager.has_method("request_chat_once"):
		sent = bool(_ai_manager.call("request_chat_once", payload, {"type": "character_dialogue", "npc": npc_display_name}))
	elif _ai_manager.has_method("send_chat_payload"):
		sent = bool(_ai_manager.call("send_chat_payload", payload, {"type": "character_dialogue", "npc": npc_display_name}))
	_sending_request = false
	if not sent:
		var error_text := _last_ai_error_text if not _last_ai_error_text.strip_edges().is_empty() else "request_failed"
		if error_text == "request_in_progress" and _can_queue_dialogue_request(request_source):
			_request_in_flight = false
			var queued := _enqueue_dialogue_text(text, given_item, request_source, source_decision, true)
			_schedule_queued_dialogue_retry(queued_dialogue_retry_delay_sec)
			return queued
		if not _ai_error_handled_during_send:
			_handle_dialogue_error(error_text)
		return {"ok": false, "error": error_text}
	return {"ok": true, "payload": payload}

func get_queued_dialogue_count() -> int:
	return _queued_dialogue_requests.size()

func clear_queued_dialogue() -> void:
	_queued_dialogue_requests.clear()

func notify_player_input_draft_changed(draft_text: String) -> void:
	_player_input_draft_text = draft_text.strip_edges()

func _should_aggregate_player_dialogue(request_source: String, bypass_player_aggregation: bool) -> bool:
	if bypass_player_aggregation:
		return false
	if not aggregate_player_dialogue_enabled:
		return false
	if player_dialogue_aggregate_delay_sec <= 0.0:
		return false
	var source := request_source.strip_edges()
	return source.is_empty() or source == "player"

func _aggregate_player_dialogue_text(player_text: String, given_item: String = "", source_decision: Dictionary = {}) -> Dictionary:
	if _pending_player_dialogue_parts.is_empty():
		_pending_player_first_input_ticks_msec = Time.get_ticks_msec()
	_pending_player_dialogue_parts.append(player_text.strip_edges())
	if _pending_player_given_item.is_empty() and not given_item.strip_edges().is_empty():
		_pending_player_given_item = given_item.strip_edges()
	if _pending_player_source_decision.is_empty() and not source_decision.is_empty():
		_pending_player_source_decision = source_decision.duplicate(true)
	_pending_player_flush_token += 1
	var token := _pending_player_flush_token
	_log("dialogue_aggregate_pending parts=%d text=%s" % [
		_pending_player_dialogue_parts.size(),
		_preview_text(player_text),
	])
	var timer := get_tree().create_timer(player_dialogue_aggregate_delay_sec)
	timer.timeout.connect(func() -> void:
		_flush_pending_player_dialogue_if_current(token)
	)
	return {"ok": true, "queued": true, "aggregating": true, "parts": _pending_player_dialogue_parts.size()}

func _flush_pending_player_dialogue_if_current(token: int) -> void:
	if token != _pending_player_flush_token:
		return
	if _should_delay_pending_player_dialogue_flush():
		_pending_player_flush_token += 1
		var next_token := _pending_player_flush_token
		var timer := get_tree().create_timer(player_dialogue_aggregate_delay_sec)
		timer.timeout.connect(func() -> void:
			_flush_pending_player_dialogue_if_current(next_token)
		)
		return
	_flush_pending_player_dialogue()

func _flush_pending_player_dialogue() -> void:
	if _pending_player_dialogue_parts.is_empty():
		return
	var merged_text := _format_related_player_dialogue(_pending_player_dialogue_parts)
	var item := _pending_player_given_item
	var decision := _pending_player_source_decision.duplicate(true)
	_pending_player_dialogue_parts.clear()
	_pending_player_given_item = ""
	_pending_player_source_decision = {}
	_pending_player_first_input_ticks_msec = 0
	_send_dialogue_text(merged_text, item, "player", decision, true)

func _should_delay_pending_player_dialogue_flush() -> bool:
	if _pending_player_dialogue_parts.is_empty():
		return false
	if _player_input_draft_text.is_empty():
		return false
	if player_dialogue_aggregate_max_wait_sec <= 0.0:
		return false
	var first_ticks := _pending_player_first_input_ticks_msec
	if first_ticks <= 0:
		return true
	var elapsed_sec := float(Time.get_ticks_msec() - first_ticks) / 1000.0
	return elapsed_sec < player_dialogue_aggregate_max_wait_sec

func _format_related_player_dialogue(parts: Array[String]) -> String:
	var clean_parts: Array[String] = []
	for part in parts:
		var clean := String(part).strip_edges()
		if not clean.is_empty():
			clean_parts.append(clean)
	if clean_parts.is_empty():
		return ""
	if clean_parts.size() == 1:
		return clean_parts[0]
	var lines: Array[String] = [
		"玩家连续输入了几句话，请像 AI Agent 处理连续用户消息一样按时间顺序理解：",
		"后续内容可能是补充、修正、打断、强调或新目标；不要机械逐句回答，综合判断玩家当前最终意图后自然回应。",
	]
	for i in range(clean_parts.size()):
		var prefix := "第%d句：" % int(i + 1)
		if i == 1:
			prefix = "随后："
		elif i > 1:
			prefix = "继续："
		lines.append("%s%s" % [prefix, clean_parts[i]])
	var merged := "\n".join(lines)
	if merged.length() <= max_merged_player_dialogue_chars:
		return merged
	return "…" + merged.substr(merged.length() - max_merged_player_dialogue_chars + 1)

func _can_queue_dialogue_request(request_source: String) -> bool:
	if max_queued_dialogue_requests <= 0:
		return false
	var source := request_source.strip_edges()
	if source.is_empty() or source == "player":
		return queue_player_dialogue_while_busy
	return queue_autonomous_dialogue_while_busy

func _enqueue_dialogue_text(
	player_text: String,
	given_item: String = "",
	request_source: String = "player",
	source_decision: Dictionary = {},
	front: bool = false
) -> Dictionary:
	var entry := {
		"player_text": player_text.strip_edges(),
		"given_item": given_item.strip_edges(),
		"request_source": request_source.strip_edges() if not request_source.strip_edges().is_empty() else "player",
		"source_decision": source_decision.duplicate(true),
	}
	if entry["player_text"].is_empty():
		return {"ok": false, "error": "empty_text"}
	if _try_merge_queued_dialogue(entry):
		_log("dialogue_merged count=%d text=%s" % [
			_queued_dialogue_requests.size(),
			_preview_text(String((_queued_dialogue_requests.back() as Dictionary).get("player_text", ""))),
		])
		return {"ok": true, "queued": true, "merged": true, "queue_size": _queued_dialogue_requests.size()}
	while _queued_dialogue_requests.size() >= max_queued_dialogue_requests:
		if front:
			_queued_dialogue_requests.pop_back()
		else:
			_queued_dialogue_requests.pop_front()
	if front:
		_queued_dialogue_requests.push_front(entry)
	else:
		_queued_dialogue_requests.append(entry)
	_log("dialogue_queued source=%s count=%d text=%s" % [
		String(entry.get("request_source", "")),
		_queued_dialogue_requests.size(),
		_preview_text(String(entry.get("player_text", ""))),
	])
	return {"ok": true, "queued": true, "queue_size": _queued_dialogue_requests.size()}

func _try_merge_queued_dialogue(entry: Dictionary) -> bool:
	if not merge_queued_player_dialogue:
		return false
	if _queued_dialogue_requests.is_empty():
		return false
	if String(entry.get("request_source", "player")) != "player":
		return false
	var tail := _queued_dialogue_requests.back() as Dictionary
	if String(tail.get("request_source", "player")) != "player":
		return false
	var old_text := String(tail.get("player_text", "")).strip_edges()
	var new_text := String(entry.get("player_text", "")).strip_edges()
	if old_text.is_empty() or new_text.is_empty():
		return false
	var merged := _merge_player_dialogue_text(old_text, new_text)
	tail["player_text"] = merged
	var old_item := String(tail.get("given_item", "")).strip_edges()
	var new_item := String(entry.get("given_item", "")).strip_edges()
	if old_item.is_empty() and not new_item.is_empty():
		tail["given_item"] = new_item
	_queued_dialogue_requests[_queued_dialogue_requests.size() - 1] = tail
	return true

func _merge_player_dialogue_text(old_text: String, new_text: String) -> String:
	var parts := _extract_related_player_dialogue_parts(old_text)
	var clean_new := new_text.strip_edges()
	if not clean_new.is_empty():
		parts.append(clean_new)
	return _format_related_player_dialogue(parts)

func _extract_related_player_dialogue_parts(text: String) -> Array[String]:
	var clean_text := text.strip_edges()
	var parts: Array[String] = []
	if clean_text.is_empty():
		return parts
	var lines := clean_text.split("\n", false)
	for raw_line in lines:
		var line := String(raw_line).strip_edges()
		if line.is_empty():
			continue
		var content := _extract_related_player_dialogue_content(line)
		if not content.is_empty():
			parts.append(content)
	if parts.is_empty():
		parts.append(clean_text)
	return parts

func _extract_related_player_dialogue_content(line: String) -> String:
	if line.begins_with("随后："):
		return line.substr("随后：".length()).strip_edges()
	if line.begins_with("继续："):
		return line.substr("继续：".length()).strip_edges()
	if line.begins_with("补充："):
		return line.substr("补充：".length()).strip_edges()
	if line.begins_with("第"):
		var marker_index := line.find("句：")
		if marker_index > 0:
			return line.substr(marker_index + "句：".length()).strip_edges()
	return ""

func _build_chat_payload(player_text: String, given_item: String, request_source: String = "player", source_decision: Dictionary = {}) -> Dictionary:
	var save_slot := _resolve_save_slot_name()
	var clean_session_id := _resolve_effective_session_id(save_slot)
	session_id = clean_session_id
	var context_data := _build_ai_checkpoint_context(save_slot, clean_session_id)
	context_data["request_source"] = request_source.strip_edges() if not request_source.strip_edges().is_empty() else "player"
	context_data["npc"] = _build_npc_contract_context()
	if not source_decision.is_empty():
		context_data["source_decision"] = _compact_decision(source_decision)
	var blackboard := _build_blackboard_context()
	if not blackboard.is_empty():
		context_data["blackboard"] = blackboard
	var perception := _build_compact_perception_context()
	if not perception.is_empty():
		context_data["perception"] = perception
	var mind_state := _build_mind_state_context()
	if not mind_state.is_empty():
		context_data["mind_state"] = mind_state
	var resource_stats := _build_resource_stats_context()
	if not resource_stats.is_empty():
		context_data["resource_stats"] = resource_stats
	var player_awareness := _build_player_awareness_context()
	if not player_awareness.is_empty():
		context_data["player_awareness"] = player_awareness
	var current_behavior := _build_current_behavior_context()
	if not current_behavior.is_empty():
		context_data["current_behavior"] = current_behavior
	var nav_points := _build_nav_point_context()
	if not nav_points.is_empty():
		context_data["ai_nav_points"] = nav_points
		context_data["known_nav_points"] = nav_points
	var action_contract := _build_action_contract_context()
	if not action_contract.is_empty():
		context_data["action_contract"] = action_contract
	var ai_stats := _build_npc_stats_for_request(context_data)
	if _ai_manager != null and _ai_manager.has_method("build_chat_request"):
		return _ai_manager.call(
			"build_chat_request",
			player_text,
			clean_session_id,
			1,
			0,
			ai_stats,
			given_item.strip_edges(),
			context_data,
			-1
		)
	return {
		"day": 1,
		"time": 0,
		"time_min": 0,
		"session_id": clean_session_id,
		"npc_stats": ai_stats,
		"player_text": player_text,
		"given_item": given_item.strip_edges(),
		"context": context_data,
	}


func _build_ai_checkpoint_context(save_slot: String, clean_session_id: String) -> Dictionary:
	var context := {
		"session_id": clean_session_id,
		"save_slot": save_slot,
	}
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("build_ai_checkpoint_context"):
		var checkpoint = save_manager.call("build_ai_checkpoint_context")
		if checkpoint is Dictionary:
			for key in (checkpoint as Dictionary).keys():
				context[key] = checkpoint[key]
	context["session_id"] = clean_session_id
	return context


func _record_ai_progress_from_response(final_data: Dictionary) -> void:
	var timeline := String(final_data.get("session_id", session_id)).strip_edges()
	var turn_id := int(final_data.get("turn_id", 0))
	if timeline.is_empty() or turn_id <= 0:
		return
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("record_ai_progress"):
		save_manager.call("record_ai_progress", timeline, turn_id)

func _build_npc_stats_for_request(context_data: Dictionary) -> Dictionary:
	var stats := {}
	var raw: Variant = context_data.get("resource_stats", {})
	if raw is Dictionary:
		stats = (raw as Dictionary).duplicate(true)
	return {
		"hunger": int(round(float(stats.get("hunger", 50)))),
		"thirst": int(round(float(stats.get("thirst", 50)))),
		"mood": int(round(float(stats.get("mood", 55)))),
		"favor": int(round(float(stats.get("favor", 20)))),
	}


func _resolve_effective_session_id(save_slot: String = "") -> String:
	var clean := session_id.strip_edges()
	var slot := save_slot.strip_edges()
	if slot.is_empty():
		slot = _resolve_save_slot_name()
	if use_save_scoped_session_id and (clean.is_empty() or clean == "default_session" or clean == "mirdo_session" or clean == "current_save_slot"):
		return _build_save_scoped_session_id(slot)
	if clean.is_empty():
		return "default_session"
	return clean


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


func _build_npc_contract_context() -> Dictionary:
	var context := {
		"name": npc_display_name.strip_edges(),
		"role_prompt": npc_role_prompt.strip_edges(),
		"personality_knowledge": npc_personality_knowledge.strip_edges(),
		"response_contract": response_contract_prompt.strip_edges(),
		"available_expressions": _packed_to_clean_array(available_expressions),
		"available_visemes": _packed_to_clean_array(available_visemes),
		"navigation_contract": "ai_nav_points/known_nav_points are Mirdo's remembered global map points with positions and action contract. perception is only current Area3D vision/nearby sensing. If movement is needed, prefer command='go_to_nav_point' or command_payload.intent='go_to_nav_point' with target_nav_point equal to one ai_nav_points.id; choose action from that point's action_options and expression from expression_options.",
	}
	if compact_backend_context:
		context["preferred_social_actions"] = ["listen", "tiny_wave", "small_nod", "cute_explain", "tilt_head_cute", "seated_idle"]
		context["preferred_work_actions"] = ["work_inspect_cabinet", "work_check_shelf", "work_check_lower", "work_count_supplies", "work_take_item", "work_drink"]
	else:
		context["available_body_actions"] = _packed_to_clean_array(available_body_actions)
	return context

func _build_blackboard_context() -> Dictionary:
	_refresh_refs()
	if _blackboard != null and _blackboard.has_method("build_llm_context"):
		var value: Variant = _blackboard.call("build_llm_context")
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	if _blackboard != null and _blackboard.has_method("build_blackboard_snapshot"):
		var snapshot_value: Variant = _blackboard.call("build_blackboard_snapshot")
		if snapshot_value is Dictionary:
			return (snapshot_value as Dictionary).duplicate(true)
	return {}

func _build_action_contract_context() -> Array:
	_refresh_refs()
	if _action_semantics != null and _action_semantics.has_method("build_action_contract"):
		var value: Variant = _action_semantics.call("build_action_contract", available_body_actions)
		if value is Array:
			var actions := value as Array
			return _compact_action_contract(actions) if compact_backend_context else actions
	return []

func _build_compact_perception_context() -> Dictionary:
	var perception := _resolve_perception_component()
	if perception == null or not perception.has_method("build_perception_snapshot"):
		return {}
	var snapshot_value: Variant = perception.call("build_perception_snapshot")
	if snapshot_value is not Dictionary:
		return {}
	var snapshot := snapshot_value as Dictionary
	var compact := {}
	for key in ["source", "semantic_model", "vision_note", "radius"]:
		if snapshot.has(key):
			compact[key] = snapshot[key]
	var nearby := _compact_entries(snapshot.get("nearby_objects", []), 10)
	if not nearby.is_empty():
		compact["nearby_objects"] = nearby
	var areas := _compact_entries(snapshot.get("areas", []), 5)
	if not areas.is_empty():
		compact["areas"] = areas
	var visible := _compact_entries(snapshot.get("visible_items", []), 8)
	if not visible.is_empty():
		compact["visible_items"] = visible
	return compact

func _build_mind_state_context() -> Dictionary:
	_refresh_refs()
	if _mind_state != null and _mind_state.has_method("get_state_snapshot"):
		var value: Variant = _mind_state.call("get_state_snapshot")
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	return {}

func _build_resource_stats_context() -> Dictionary:
	_refresh_refs()
	if _state_component != null and _state_component.has_method("get_snapshot"):
		var value: Variant = _state_component.call("get_snapshot")
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	if _state_component != null and _state_component.has_method("build_ai_stats"):
		var stats_value: Variant = _state_component.call("build_ai_stats")
		if stats_value is Dictionary:
			return (stats_value as Dictionary).duplicate(true)
	return {}

func _build_player_awareness_context() -> Dictionary:
	_refresh_refs()
	if _player_awareness != null and _player_awareness.has_method("build_player_awareness_snapshot"):
		var value: Variant = _player_awareness.call("build_player_awareness_snapshot")
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	return {}

func _build_current_behavior_context() -> Dictionary:
	_refresh_refs()
	if _autonomous_life != null and _autonomous_life.has_method("get_current_behavior_snapshot"):
		var value: Variant = _autonomous_life.call("get_current_behavior_snapshot")
		if value is Dictionary:
			return _compact_current_behavior(value as Dictionary) if compact_backend_context else (value as Dictionary).duplicate(true)
	if _autonomous_life != null and _autonomous_life.has_method("get_resume_debug_snapshot"):
		var resume_value: Variant = _autonomous_life.call("get_resume_debug_snapshot")
		if resume_value is Dictionary:
			return _compact_current_behavior(resume_value as Dictionary) if compact_backend_context else (resume_value as Dictionary).duplicate(true)
	return {}

func _build_nav_point_context() -> Array:
	var tree := get_tree()
	if tree == null or max_nav_points_in_prompt <= 0:
		return []
	var observer := _find_observer_node()
	var out: Array = []
	for candidate in tree.get_nodes_in_group(ai_nav_point_group):
		var node := candidate as Node
		if node == null or not is_instance_valid(node):
			continue
		if not node.has_method("build_ai_nav_point_summary"):
			continue
		var value: Variant = node.call("build_ai_nav_point_summary", observer)
		if value is not Dictionary:
			continue
		var entry := value as Dictionary
		if bool(entry.get("enabled", true)) == false:
			continue
		var compact := {}
		for key in [
			"id", "name", "type", "description", "tags", "arrival_action", "arrival_expression",
			"action_options", "expression_options", "action_hint", "target_object_id",
			"face_mode", "marker_role", "position", "global_position", "forward",
			"knowledge_scope", "map_role", "distance", "cooldown_sec", "dwell_time_sec"
		]:
			if entry.has(key):
				compact[key] = entry[key]
		if not compact.is_empty():
			out.append(compact)
	_sort_compact_entries_by_distance(out)
	return out.slice(0, mini(max_nav_points_in_prompt, out.size()))

func _find_observer_node() -> Node3D:
	var current: Node = self
	while current != null:
		if current is Node3D:
			return current as Node3D
		current = current.get_parent()
	return null

func _sort_compact_entries_by_distance(entries: Array) -> void:
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("distance", 0.0)) < float(b.get("distance", 0.0))
	)

func _compact_entries(entries_value: Variant, limit: int) -> Array:
	var out: Array = []
	if entries_value is not Array:
		return out
	for entry_value in entries_value:
		if out.size() >= limit:
			break
		if entry_value is not Dictionary:
			continue
		var entry := entry_value as Dictionary
		var compact := {}
		for key in ["id", "name", "type", "description", "tags", "actions", "distance", "marker_roles"]:
			if entry.has(key):
				compact[key] = entry[key]
		if not compact.is_empty():
			out.append(compact)
	return out

func _compact_current_behavior(snapshot: Dictionary) -> Dictionary:
	var out := {}
	for key in ["navigating", "current_kind", "current_target", "last_kind", "last_target", "has_resume", "resume_kind", "resume_target", "external_grace_left", "dwell_left"]:
		if snapshot.has(key):
			out[key] = snapshot[key]
	var current := _compact_decision(snapshot.get("current_decision", {}))
	if not current.is_empty():
		out["current_decision"] = current
	var navigation := _compact_decision(snapshot.get("navigation_decision", {}))
	if not navigation.is_empty():
		out["navigation_decision"] = navigation
	var stack_value: Variant = snapshot.get("task_stack", [])
	if stack_value is Array:
		var stack: Array = []
		for entry in stack_value:
			if entry is Dictionary:
				var compact_entry := _compact_decision(entry)
				if not compact_entry.is_empty():
					stack.append(compact_entry)
			if stack.size() >= 3:
				break
		if not stack.is_empty():
			out["resume_task_stack"] = stack
	return out

func _compact_decision(value: Variant) -> Dictionary:
	if value is not Dictionary:
		return {}
	var decision := value as Dictionary
	var out := {}
	for key in [
		"kind", "target_object", "target_nav_point", "target_ref", "marker_role",
		"action", "arrival_action", "arrival_expression", "face_target",
		"dwell_time_sec", "resume_reason", "score", "feedback"
	]:
		if decision.has(key):
			out[key] = decision[key]
	return out

func _compact_action_contract(actions: Array) -> Array:
	var preferred := [
		"listen", "tiny_wave", "small_nod", "cute_explain", "tilt_head_cute", "seated_idle", "seated_sleepy",
		"work_inspect_cabinet", "work_check_shelf", "work_check_lower", "work_count_supplies", "work_take_item", "work_drink",
		"look_around", "curious_peek", "rub_eye", "sleepy_yawn", "walk", "run", "turn_left", "turn_right", "turn_180"
	]
	var out: Array = []
	for entry_value in actions:
		if entry_value is not Dictionary:
			continue
		var entry := entry_value as Dictionary
		var name := String(entry.get("name", "")).strip_edges()
		if not preferred.has(name):
			continue
		var compact := {}
		for key in ["name", "category", "posture", "loop", "interruptible", "uses_root_motion", "default_expression", "tags", "description"]:
			if entry.has(key):
				compact[key] = entry[key]
		out.append(compact)
	return out

func _bind_ai_signals() -> void:
	if _ai_manager == null:
		return
	if _ai_manager.has_signal("on_ai_stream_chunk_received"):
		var chunk_cb := Callable(self, "_on_ai_chunk")
		if not _ai_manager.is_connected("on_ai_stream_chunk_received", chunk_cb):
			_ai_manager.connect("on_ai_stream_chunk_received", chunk_cb)
	if _ai_manager.has_signal("on_ai_stream_dialogue_finished"):
		var stream_done_cb := Callable(self, "_on_ai_stream_dialogue_finished")
		if not _ai_manager.is_connected("on_ai_stream_dialogue_finished", stream_done_cb):
			_ai_manager.connect("on_ai_stream_dialogue_finished", stream_done_cb)
	if _ai_manager.has_signal("on_ai_response_completed"):
		var done_cb := Callable(self, "_on_ai_completed")
		if not _ai_manager.is_connected("on_ai_response_completed", done_cb):
			_ai_manager.connect("on_ai_response_completed", done_cb)
	if _ai_manager.has_signal("on_ai_request_error"):
		var error_cb := Callable(self, "_on_ai_error")
		if not _ai_manager.is_connected("on_ai_request_error", error_cb):
			_ai_manager.connect("on_ai_request_error", error_cb)

func _on_ai_chunk(chunk: String) -> void:
	if not _request_in_flight:
		return
	_stream_text += chunk
	dialogue_chunk_received.emit(chunk)

func _on_ai_stream_dialogue_finished(dialogue_text: String) -> void:
	if not _request_in_flight:
		return
	dialogue_stream_finished.emit(dialogue_text)

func _on_ai_completed(final_data: Dictionary) -> void:
	if not _request_in_flight:
		return
	_request_in_flight = false
	_record_ai_progress_from_response(final_data)
	var dialogue_text := _extract_dialogue(final_data)
	if dialogue_text.is_empty():
		dialogue_text = _stream_text.strip_edges()
	if dialogue_text.is_empty():
		dialogue_text = "……"
	if _should_suppress_error(dialogue_text, final_data):
		_emit_local_fallback(_extract_error_reason(dialogue_text, final_data))
		return
	var route_summary := {}
	if auto_apply_ai_response:
		route_summary = _apply_ai_response(final_data)
	if direct_subtitle_enabled:
		_show_subtitle(dialogue_text)
	var report := {
		"ok": true,
		"dialogue": dialogue_text,
		"ai_data": final_data.duplicate(true),
		"route_summary": route_summary,
		"request_payload": _last_payload.duplicate(true),
	}
	dialogue_completed.emit(report)
	_drain_queued_dialogue_deferred()

func _on_ai_error(error_text: String) -> void:
	if not _request_in_flight:
		return
	_last_ai_error_text = error_text
	_ai_error_handled_during_send = true
	_handle_dialogue_error(error_text)

func _handle_dialogue_error(error_text: String) -> void:
	_request_in_flight = false
	if _should_speak_local_fallback_for_error(error_text):
		_emit_local_fallback(error_text)
		return
	_log("local_fallback_suppressed reason=%s" % error_text)
	dialogue_failed.emit(error_text)
	if not _sending_request:
		_drain_queued_dialogue_deferred()

func _should_speak_local_fallback_for_error(error_text: String) -> bool:
	var reason := error_text.strip_edges()
	if reason == "request_in_progress":
		return speak_local_fallback_when_ai_busy
	return true

func _drain_queued_dialogue_deferred() -> void:
	if _queued_dialogue_requests.is_empty() or _request_in_flight:
		return
	call_deferred("_drain_queued_dialogue")

func _drain_queued_dialogue() -> void:
	if _request_in_flight or _queued_dialogue_requests.is_empty():
		return
	var entry: Dictionary = _queued_dialogue_requests.pop_front()
	var result := _send_dialogue_text(
		String(entry.get("player_text", "")),
		String(entry.get("given_item", "")),
		String(entry.get("request_source", "player")),
		(entry.get("source_decision", {}) as Dictionary).duplicate(true) if entry.get("source_decision", {}) is Dictionary else {},
		true
	)
	if bool(result.get("queued", false)):
		_schedule_queued_dialogue_retry(queued_dialogue_retry_delay_sec)

func _schedule_queued_dialogue_retry(delay_sec: float) -> void:
	if _queue_retry_scheduled:
		return
	_queue_retry_scheduled = true
	var timer := get_tree().create_timer(maxf(0.01, delay_sec))
	timer.timeout.connect(_on_queue_retry_timer_timeout)

func _on_queue_retry_timer_timeout() -> void:
	_queue_retry_scheduled = false
	if not _request_in_flight:
		_drain_queued_dialogue_deferred()
	elif not _queued_dialogue_requests.is_empty():
		_schedule_queued_dialogue_retry(queued_dialogue_retry_delay_sec)

func _apply_ai_response(ai_data: Dictionary) -> Dictionary:
	_refresh_refs()
	var route_summary := {}
	if _action_executor != null and _action_executor.has_method("apply_ai_response"):
		route_summary = _action_executor.call("apply_ai_response", ai_data.duplicate(true))
	elif _face_component != null:
		_apply_face_only(ai_data)
	return route_summary

func _apply_face_only(ai_data: Dictionary) -> void:
	var expression := String(ai_data.get("expression", "")).strip_edges()
	if expression.is_empty():
		expression = "joy" if String(ai_data.get("emotion", "")).find("开心") >= 0 else ""
	if not expression.is_empty() and _face_component.has_method("set_face_expression"):
		_face_component.call("set_face_expression", StringName(expression))
	var visemes := String(ai_data.get("visemes", ai_data.get("viseme_sequence", ""))).strip_edges()
	if not visemes.is_empty() and _face_component.has_method("play_external_visemes"):
		_face_component.call("play_external_visemes", visemes)

func _emit_local_fallback(reason: String) -> void:
	var player_text := String(_last_payload.get("player_text", "")).strip_edges()
	var given_item := String(_last_payload.get("given_item", "")).strip_edges()
	var data := _build_local_dialogue_response(player_text, given_item, reason)
	_log("local_fallback reason=%s dialogue=%s" % [reason, String(data.get("dialogue", ""))])
	if auto_apply_ai_response:
		_apply_ai_response(data)
	if direct_subtitle_enabled:
		_show_subtitle(String(data.get("dialogue", fallback_reply_text)))
	dialogue_failed.emit(reason)
	dialogue_completed.emit({
		"ok": false,
		"dialogue": String(data.get("dialogue", fallback_reply_text)),
		"ai_data": data,
		"route_summary": {},
		"request_payload": _last_payload.duplicate(true),
		"fallback": true,
		"fallback_reason": reason,
	})
	_drain_queued_dialogue_deferred()

func _build_local_dialogue_response(player_text: String, given_item: String = "", reason: String = "local_fallback") -> Dictionary:
	var text := player_text.strip_edges()
	var lowered := text.to_lower()
	var dialogue := fallback_reply_text.strip_edges()
	var expression := "joy"
	var action := "listen"
	var command := "talk"
	var target_hint := ""
	if dialogue.is_empty():
		dialogue = "老师，我在听呢。"
	if not given_item.strip_edges().is_empty():
		dialogue = "老师，我收到%s啦，我会注意状态的。" % given_item.strip_edges()
		expression = "joy"
		action = "small_nod"
	elif _contains_any(lowered, ["感觉", "状态", "怎么样", "累", "困", "饿", "渴"]):
		var resource := _build_resource_stats_context()
		var mind := _build_mind_state_context()
		var hunger := float(resource.get("hunger", 65.0))
		var thirst := float(resource.get("thirst", 60.0))
		var energy := float(resource.get("energy", 70.0))
		var mood := float(resource.get("mood", 55.0))
		var tiredness := float(mind.get("tiredness", 0.0))
		var asks_hunger := _contains_any(lowered, ["饿不饿", "饿吗", "你饿", "肚子饿", "hungry"])
		var asks_thirst := _contains_any(lowered, ["渴不渴", "渴吗", "你渴", "口渴", "thirsty"])
		var asks_tired := _contains_any(lowered, ["累不累", "累吗", "你累", "困不困", "困吗", "tired", "sleepy"])
		if asks_hunger:
			if hunger <= 25.0:
				dialogue = "老师，Mirdo 有点饿了……等会儿想看看食物柜。"
				expression = "sorrow"
			elif hunger <= 50.0:
				dialogue = "老师，有一点点饿，不过还可以陪你哦。"
				expression = "neutral"
			else:
				dialogue = "老师，我现在不太饿哦，先不用担心。"
				expression = "joy"
			action = "small_nod"
		elif asks_thirst:
			if thirst <= 25.0:
				dialogue = "老师，Mirdo 有点渴了……等会儿想补一点水。"
				expression = "sorrow"
			elif thirst <= 50.0:
				dialogue = "老师，有一点点渴，但还可以忍住哦。"
				expression = "neutral"
			else:
				dialogue = "老师，我现在不太渴哦，谢谢老师关心。"
				expression = "joy"
			action = "small_nod"
		elif asks_tired or energy < 35.0 or tiredness > 0.62:
			if energy < 35.0 or tiredness > 0.62:
				dialogue = "老师，Mirdo 有点累了……但还能继续陪你。"
				expression = "sorrow"
				action = "rub_eye"
			else:
				dialogue = "老师，我现在不累哦，精神还可以。"
				expression = "joy"
				action = "small_nod"
		elif hunger <= 25.0:
			dialogue = "老师，我有点饿，想先确认一下食物补给。"
			expression = "sorrow"
			action = "small_nod"
		elif thirst <= 25.0:
			dialogue = "老师，我有点渴，想先确认一下饮水。"
			expression = "sorrow"
			action = "small_nod"
		elif mood >= 55.0:
			dialogue = "老师，我现在状态不错，可以继续陪你守着避难所。"
			expression = "joy"
			action = "small_nod"
		else:
			dialogue = "老师，我还好，就是想确认一下补给。"
			expression = "neutral"
			action = "tilt_head_cute"
	elif _contains_any(lowered, ["附近", "周围", "看到", "有什么"]):
		dialogue = _build_nearby_summary_line()
		expression = "fun"
		action = "look_around"
		command = "inspect_surroundings"
	elif _contains_any(lowered, ["食物柜", "食品柜", "food", "吃的"]):
		dialogue = "老师，我去看看食物柜，顺便清点一下。"
		expression = "joy"
		action = "work_count_supplies"
		command = "go_to_nav_point"
		target_hint = "food_cabinet 食物柜"
	elif _contains_any(lowered, ["医疗", "药", "medical"]):
		dialogue = "老师，我去检查医疗柜，药品要留意。"
		expression = "neutral"
		action = "work_check_shelf"
		command = "go_to_nav_point"
		target_hint = "medical_cabinet 医疗柜"
	elif _contains_any(lowered, ["工具", "装备", "tool", "设备"]):
		dialogue = "老师，我去看看工具和装备有没有缺的。"
		expression = "fun"
		action = "work_check_lower"
		command = "go_to_nav_point"
		target_hint = "tool_cabinet 工具柜"
	elif _contains_any(lowered, ["接下来", "做什么", "下一步"]):
		dialogue = "老师，我们先确认食物、水和药品，再决定要不要外出。"
		expression = "fun"
		action = "cute_explain"
		command = "suggest_task"
	elif _contains_any(lowered, ["跟着", "跟随", "follow"]):
		dialogue = "好呀老师，我会跟紧一点。"
		expression = "joy"
		action = "tiny_wave"
		command = "follow_player"
	elif _contains_any(lowered, ["停下", "别动", "等等", "stop"]):
		dialogue = "嗯，老师，我先停在这里。"
		expression = "neutral"
		action = "small_nod"
		command = "stop"
	elif _contains_any(lowered, ["你好", "嗨", "hello", "在吗"]):
		dialogue = "老师，我在哦，有什么想让我做的吗？"
		expression = "joy"
		action = "tiny_wave"
	else:
		dialogue = _pick_general_fallback_line(text, reason)
		expression = "joy"
		action = "tilt_head_cute"
	var data := {
		"dialogue": _limit_text(dialogue, 42),
		"emotion": expression,
		"expression": expression,
		"action": action,
		"command": command,
		"intent": command,
		"visemes": _simple_visemes_for_text(dialogue),
		"local_fallback": true,
		"fallback_reason": reason,
	}
	if not target_hint.is_empty():
		data["target_hint"] = target_hint
		data["target_nav_point"] = target_hint
		data["target_object"] = target_hint
	return data

func _pick_general_fallback_line(player_text: String, reason: String = "") -> String:
	if not local_fallback_variety_enabled:
		return fallback_reply_text.strip_edges() if not fallback_reply_text.strip_edges().is_empty() else "老师，我在听呢。"
	var options := [
		"老师，我在听。刚才那句我可能没完全理解。",
		"嗯，老师，我听见了。你可以再说具体一点吗？",
		"老师，我有点没跟上，不过我会继续听你说。",
		"我在哦，老师。你想让我靠近一点，还是先等一下？",
		"老师，我收到啦。你再补一句，我就更明白了。",
	]
	var seed_text := "%s|%s|%s" % [player_text, reason, Time.get_ticks_msec()]
	var index := absi(seed_text.hash()) % options.size()
	return options[index]

func _build_nearby_summary_line() -> String:
	var perception := _build_compact_perception_context()
	var entries: Array = []
	for key in ["nearby_objects", "visible_items", "areas"]:
		var value: Variant = perception.get(key, [])
		if value is Array:
			for entry_value in value:
				if entries.size() >= 3:
					break
				if entry_value is Dictionary:
					var name := String((entry_value as Dictionary).get("name", (entry_value as Dictionary).get("id", ""))).strip_edges()
					if not name.is_empty() and not entries.has(name):
						entries.append(name)
	if entries.is_empty():
		return "老师，我先环顾一下，附近暂时没有特别明显的东西。"
	return "老师，我看到%s，可以先检查一下。" % "、".join(entries)

func _contains_any(text: String, needles: Array) -> bool:
	for needle in needles:
		if text.find(String(needle).to_lower()) >= 0:
			return true
	return false

func _limit_text(text: String, max_chars: int) -> String:
	var clean := text.strip_edges()
	if clean.length() <= max_chars:
		return clean
	return clean.substr(0, maxi(1, max_chars - 1)) + "…"

func _preview_text(text: String, max_chars: int = 36) -> String:
	var clean := text.strip_edges()
	if clean.length() <= max_chars:
		return clean
	return clean.substr(0, maxi(1, max_chars - 3)) + "..."

func _simple_visemes_for_text(text: String) -> String:
	var count = clampi(int(ceil(float(maxi(1, text.length())) / 6.0)), 1, 5)
	var pool := ["aa", "ih", "ou", "E", "oh"]
	var out: Array[String] = []
	for i in range(count):
		out.append(pool[i % pool.size()])
	return "、".join(out)

func _show_subtitle(text: String) -> void:
	var subtitle := _resolve_subtitle_target()
	if subtitle != null and subtitle.has_method("show_once"):
		subtitle.call("show_once", text, npc_display_name.strip_edges())

func _extract_dialogue(data: Dictionary) -> String:
	for key in ["dialogue", "reply", "text", "message", "summary"]:
		var value := String(data.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return ""

func _should_suppress_error(dialogue_text: String, data: Dictionary) -> bool:
	if not suppress_error_dialogue_output:
		return false
	if data.has("ok") and not bool(data.get("ok", true)):
		return true
	var error_text := String(data.get("error", data.get("model_error", ""))).strip_edges()
	return not error_text.is_empty() or dialogue_text.begins_with("模型调用失败")

func _extract_error_reason(dialogue_text: String, data: Dictionary) -> String:
	var error_text := String(data.get("error", data.get("model_error", ""))).strip_edges()
	if not error_text.is_empty():
		return error_text
	return dialogue_text if not dialogue_text.is_empty() else "dialogue_error"

func _refresh_refs() -> void:
	_ai_manager = get_node_or_null(ai_manager_path) as AIManager if ai_manager_path != NodePath() else null
	_perception_component = get_node_or_null(perception_component_path) if perception_component_path != NodePath() else null
	_mind_state = get_node_or_null(mind_state_path) if mind_state_path != NodePath() else null
	_state_component = get_node_or_null(state_component_path) if state_component_path != NodePath() else null
	_player_awareness = get_node_or_null(player_awareness_path) if player_awareness_path != NodePath() else null
	_autonomous_life = get_node_or_null(autonomous_life_path) if autonomous_life_path != NodePath() else null
	_blackboard = get_node_or_null(blackboard_path) if blackboard_path != NodePath() else null
	_action_semantics = get_node_or_null(action_semantics_path) if action_semantics_path != NodePath() else null
	_action_executor = get_node_or_null(action_executor_path) if action_executor_path != NodePath() else null
	_subtitle_target = get_node_or_null(subtitle_target_path) if subtitle_target_path != NodePath() else null
	_face_component = get_node_or_null(face_component_path) if face_component_path != NodePath() else null
	if _ai_manager == null:
		_ai_manager = _find_sibling_with_type("AIManager") as AIManager
	if _perception_component == null:
		_perception_component = _find_sibling_with_method(&"build_perception_snapshot")
	if _mind_state == null:
		_mind_state = _find_sibling_with_method(&"get_state_snapshot")
	if _state_component == null:
		_state_component = _find_sibling_with_method(&"get_snapshot")
	if _player_awareness == null:
		_player_awareness = _find_sibling_with_method(&"build_player_awareness_snapshot")
	if _autonomous_life == null:
		_autonomous_life = _find_sibling_with_method(&"get_current_behavior_snapshot")
	if _blackboard == null:
		_blackboard = _find_sibling_with_method(&"build_blackboard_snapshot")
	if _action_semantics == null:
		_action_semantics = _find_sibling_with_method(&"get_action_semantics")
	if _action_executor == null:
		_action_executor = _find_sibling_with_method(&"apply_ai_response")
	if _subtitle_target == null:
		_subtitle_target = _find_sibling_with_method(&"show_once")
	if _face_component == null:
		_face_component = _find_sibling_with_method(&"set_face_expression")

func _resolve_perception_component() -> Node:
	if _perception_component == null or not is_instance_valid(_perception_component):
		_refresh_refs()
	return _perception_component

func _resolve_subtitle_target() -> Node:
	if _subtitle_target == null or not is_instance_valid(_subtitle_target):
		_refresh_refs()
	return _subtitle_target

func _find_sibling_with_method(method_name: StringName) -> Node:
	var parent_node := get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var node := child as Node
		if node != null and node != self and node.has_method(method_name):
			return node
	return null

func _find_sibling_with_type(type_name: String) -> Node:
	var parent_node := get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var node := child as Node
		if node != null and node.get_class() == type_name:
			return node
		if node != null and node.get_script() != null and String(node.get_script().get_global_name()) == type_name:
			return node
	return null

func _packed_to_clean_array(values: PackedStringArray) -> Array:
	var out: Array = []
	for value in values:
		var clean := String(value).strip_edges()
		if not clean.is_empty():
			out.append(clean)
	return out

func _log(message: String) -> void:
	if always_log:
		print("[CharacterAIDialogue] %s" % message)
