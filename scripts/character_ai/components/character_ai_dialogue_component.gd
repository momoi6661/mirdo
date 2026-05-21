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
@export_range(0, 64, 1) var max_nav_points_in_prompt: int = 24

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
@export var use_streaming_request: bool = false
@export var auto_apply_ai_response: bool = true
@export var direct_subtitle_enabled: bool = true
@export var fallback_reply_text: String = "我有点没听清，可以再说一次吗？"
@export var suppress_error_dialogue_output: bool = true
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

func _ready() -> void:
	_refresh_refs()
	_bind_ai_signals()

func chat(text: String, given_item: String = "") -> bool:
	var result := send_player_text(text, given_item)
	return bool(result.get("ok", false))

func send_player_text(player_text: String, given_item: String = "") -> Dictionary:
	_refresh_refs()
	_bind_ai_signals()
	var text := player_text.strip_edges()
	if text.is_empty():
		return {"ok": false, "error": "empty_text"}
	if _ai_manager == null:
		_emit_local_fallback("ai_manager_missing")
		return {"ok": false, "error": "ai_manager_missing"}
	if _request_in_flight:
		return {"ok": false, "error": "request_in_flight"}

	var payload := _build_chat_payload(text, given_item)
	_last_payload = payload.duplicate(true)
	_stream_text = ""
	_request_in_flight = true
	dialogue_requested.emit(payload.duplicate(true))

	var sent := false
	if use_streaming_request and _ai_manager.has_method("request_chat_stream"):
		sent = bool(_ai_manager.call("request_chat_stream", payload, {"type": "character_dialogue", "npc": npc_display_name}))
	elif _ai_manager.has_method("request_chat_once"):
		sent = bool(_ai_manager.call("request_chat_once", payload, {"type": "character_dialogue", "npc": npc_display_name}))
	elif _ai_manager.has_method("send_chat_payload"):
		sent = bool(_ai_manager.call("send_chat_payload", payload, {"type": "character_dialogue", "npc": npc_display_name}))
	if not sent:
		_request_in_flight = false
		_emit_local_fallback("request_failed")
		return {"ok": false, "error": "request_failed"}
	return {"ok": true, "payload": payload}

func _build_chat_payload(player_text: String, given_item: String) -> Dictionary:
	var clean_session_id := session_id.strip_edges()
	if clean_session_id.is_empty():
		clean_session_id = "default_session"
	session_id = clean_session_id
	var context_data := {
		"session_id": clean_session_id,
		"save_slot": _resolve_save_slot_name(),
		"request_source": "godot_runtime",
		"npc": _build_npc_contract_context(),
	}
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
	if _ai_manager != null and _ai_manager.has_method("build_chat_request"):
		return _ai_manager.call(
			"build_chat_request",
			player_text,
			clean_session_id,
			1,
			0,
			{"hunger": 50, "thirst": 50, "mood": 55, "favor": 20},
			given_item.strip_edges(),
			context_data,
			-1
		)
	return {
		"day": 1,
		"time": 0,
		"time_min": 0,
		"session_id": clean_session_id,
		"npc_stats": {"hunger": 50, "thirst": 50, "mood": 55, "favor": 20},
		"player_text": player_text,
		"given_item": given_item.strip_edges(),
		"context": context_data,
	}

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
	return {
		"name": npc_display_name.strip_edges(),
		"role_prompt": npc_role_prompt.strip_edges(),
		"personality_knowledge": npc_personality_knowledge.strip_edges(),
		"response_contract": response_contract_prompt.strip_edges(),
		"available_body_actions": _packed_to_clean_array(available_body_actions),
		"available_expressions": _packed_to_clean_array(available_expressions),
		"available_visemes": _packed_to_clean_array(available_visemes),
		"navigation_contract": "ai_nav_points/known_nav_points are Mirdo's remembered global map points with positions and action contract. perception is only current Area3D vision/nearby sensing. If movement is needed, prefer command='go_to_nav_point' or command_payload.intent='go_to_nav_point' with target_nav_point equal to one ai_nav_points.id; choose action from that point's action_options and expression from expression_options.",
	}

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
			return value as Array
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
			return (value as Dictionary).duplicate(true)
	if _autonomous_life != null and _autonomous_life.has_method("get_resume_debug_snapshot"):
		var resume_value: Variant = _autonomous_life.call("get_resume_debug_snapshot")
		if resume_value is Dictionary:
			return (resume_value as Dictionary).duplicate(true)
	return {}

func _build_nav_point_context() -> Array:
	var tree := get_tree()
	if tree == null or max_nav_points_in_prompt <= 0:
		return []
	var observer := _find_observer_node()
	var out: Array = []
	for candidate in tree.get_nodes_in_group(ai_nav_point_group):
		if out.size() >= max_nav_points_in_prompt:
			break
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
	return out

func _find_observer_node() -> Node3D:
	var current: Node = self
	while current != null:
		if current is Node3D:
			return current as Node3D
		current = current.get_parent()
	return null

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

func _on_ai_error(error_text: String) -> void:
	if not _request_in_flight:
		return
	_request_in_flight = false
	_emit_local_fallback(error_text)

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
	elif _contains_any(lowered, ["感觉", "状态", "怎么样", "累", "饿", "渴"]):
		var resource := _build_resource_stats_context()
		var mind := _build_mind_state_context()
		var energy := float(resource.get("energy", 70.0))
		var mood := float(resource.get("mood", 55.0))
		var tiredness := float(mind.get("tiredness", 0.0))
		if energy < 35.0 or tiredness > 0.62:
			dialogue = "老师，我有点累，不过还能继续陪你。"
			expression = "sorrow"
			action = "rub_eye"
		elif mood >= 55.0:
			dialogue = "老师，我现在状态不错，想再看看避难所。"
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
		dialogue = "老师，我听到啦。要我检查补给，还是陪你看看周围？"
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
